/*
 * Core application logic (handles web requests from client, detects new client initializations via socket.io)
 * Much of this code borrowed from https://github.com/hawkrobe/MWERT/blob/master/app.js
 */

/*
 * To run this locally:
 * 1. cd /rps
 * 2. `node app.js`
 * 3. in browser, visit http://localhost:3000/index.html
 *    -> to run a test version, visit http://localhost:3000/index.html?&mode=test
 *    -> to run a bot version, visit http://localhost:3000/index.html?&ver=2
 *    -> to view status of gameServer, visit http://localhost:3000/admin
 */


// GLOBALS
const JSPATH = "/lib"; // path to static js files

// Server variables
var app = require("express")(); // initialize express server
var server = app.listen(3000); // listen on port 3000 (nginx will proxy requests on 80 to 3000)
var io = require("socket.io").listen(server); // initialize socket.io
var UUID = require("uuid"); // UUID library for generating unique IDs
var gameServer = require(__dirname + JSPATH + "/" + "game.js"); // object for keeping track of games


// Initializing server
// General purpose getter for js files
app.get("/*", function(req, res) {
    var file = req.params[0];
    if (file == "admin") { // admin endpoint returns state of game server for quick debugging
        res.setHeader('Content-Type', 'application/json');
        res.end(JSON.stringify(gameServer.getState(), null, 3));
    } else {
        res.sendFile(__dirname + "/" + file);
    }
});

// socket.io will call this function when a client connects
io.on("connection", function (client) {
    console.log("app.js:\t new user connected");
    client.userid = UUID()
    // tell the client it connected successfully and pass along unique ID
    client.emit("onconnected", {id: client.userid});
    initializeClient(client);
});

// Function to handle socket interactions between gameServer and clients
initializeClient = function(client) {
    // extract relevant info from client request
    var istest = client.handshake.query.istest == "true";
    var version = client.handshake.query.version;
    // assign client to an existing game or start a new one
    gameServer.findGame(client, version, istest);

    // handle player move submissions
    client.on("player_move", function(data) {
        console.log("app.js:\t detected player move: ", data);
        gameServer.processMove(client, data);
    });

    // handle player signal that they're ready for the next round
    client.on("player_round_complete", function(data) {
        console.log("app.js:\t detected player round complete");
        gameServer.nextRound(client, data);
    });

    // handle player submitting exit survey free response data
    client.on("free_response_submit", function(data) {
        console.log("app.js:\t detected player free response submission");
        gameServer.writeFreeRespData(data);
    });

    // handle player submitting exit survey slider data
    client.on("slider_submit", function(data) {
        console.log("app.js:\t detected player Likert slider submission");
        gameServer.writeSliderData(data);
    });

    // handle disconnect
    client.on("disconnect", function() {
        console.log("app.js:\t detected client disconnect");
        gameServer.clientDisconnect(client);
    });
};
