#'
#' RPS *adaptive* bot analysis for CogSci 2021
#' Examines human performance against bot opponents with varying
#' adaptive strategies
#'



# SETUP ========================================================================
source('manuscript_analysis.R') # NB: if this fails, run again (takes ~20-30s)

setwd("/Users/erikbrockbank/web/vullab/rps/analysis/")
# rm(list = ls())
library(tidyverse)
library(viridis)
library(wesanderson)
library(patchwork)



# GLOBALS ======================================================================

DATA_FILE = "rps_v3_data.csv" # name of file containing full dataset for all rounds
FREE_RESP_FILE = "rps_v3_data_freeResp.csv" # file containing free response data by participant
SLIDER_FILE = "rps_v3_data_sliderData.csv" # file containing slider Likert data by participant
NUM_ROUNDS = 300 # number of rounds in each complete game

# In order of complexity
STRATEGY_LEVELS = c(
  # 1x3
  # "opponent_moves",
  "opponent_transitions",
  "opponent_courn_transitions",
  # 3x3
  "opponent_prev_move",
  "bot_prev_move",
  "opponent_outcome_transitions",
  # 9x3
  "opponent_bot_prev_move",
  "opponent_prev_two_moves",
  # "bot_prev_two_moves",
  "opponent_outcome_prev_transition_dual"
)

STRATEGY_LOOKUP = list(
  # "opponent_moves" = "Move distribution",
  "opponent_prev_move" = "Transition given player's prior choice",
  "bot_prev_move" = "Transition given opponent's prior choice",
  "opponent_bot_prev_move" = "Choice given player's prior choice & opponent's prior choice",
  "opponent_prev_two_moves" = "Choice given player's prior two choices",
  # "bot_prev_two_moves" = "Bot previous two moves",
  "opponent_transitions" = "Transition baserate (+/-/0)",
  "opponent_courn_transitions" = "Opponent transition baserate (+/-/0)",
  "opponent_outcome_transitions" = "Transition given prior outcome (W/L/T)",
  "opponent_outcome_prev_transition_dual" = "Transition given prior transition & prior outcome"
)



# ANALYSIS FUNCTIONS ===========================================================

# Read in and process free response data
read_free_resp_data = function(filename, game_data) {
  data = read_csv(filename)
  # Join with game data to get bot strategy, etc.
  data = data %>%
    inner_join(game_data, by = c("game_id", "player_id")) %>%
    distinct(bot_strategy, game_id, player_id, free_resp_answer)
  # Order bot strategies
  data$bot_strategy = factor(data$bot_strategy, levels = STRATEGY_LEVELS)
  # Add plain english strategy, string process free resposne answers
  data = data %>%
    group_by(bot_strategy, player_id) %>%
    mutate(strategy = STRATEGY_LOOKUP[[bot_strategy]],
           free_resp_answer = str_replace_all(free_resp_answer, "\n" , "[newline]")) %>%
    ungroup()

  return(data)
}

# Read in and process slider data
read_slider_data = function(filename, game_data) {
  data = read_csv(filename)
  data = data %>%
    inner_join(game_data, by = c("game_id", "player_id")) %>%
    distinct(game_id, player_id, bot_strategy, index, statement, resp)
  # Order bot strategies
  data$bot_strategy = factor(data$bot_strategy, levels = STRATEGY_LEVELS)
  # Add plain english strategy
  data = data %>%
    group_by(bot_strategy, player_id, index) %>%
    mutate(strategy = STRATEGY_LOOKUP[[bot_strategy]]) %>%
    ungroup()

  return(data)
}

get_slider_summary = function(slider_data) {
  slider_data %>%
    group_by(statement, bot_strategy, strategy) %>%
    summarize(n = n(),
              mean_resp = mean(resp),
              se = sd(resp) / sqrt(n),
              se_upper = mean_resp + se,
              se_lower = mean_resp - se)
}


get_bot_strategy_win_count_differential = function(data) {
  win_diff = data %>%
    group_by(bot_strategy, game_id, player_id, is_bot) %>%
    count(win_count = player_outcome == "win") %>%
    filter(win_count == TRUE) %>%
    group_by(bot_strategy, game_id) %>%
    # Win count for bots minus win count for human opponents
    # NB: if the person or bot *never* wins, this count will fail for them
    summarize(win_count_diff = n[is_bot == 1] - n[is_bot == 0]) %>%
    as.data.frame()
  return(win_diff)
}

get_bot_strategy_win_count_differential_summary = function(strategy_data) {
  strategy_data %>%
    group_by(bot_strategy) %>%
    summarize(mean_win_count_diff = mean(win_count_diff),
              n = n(),
              se = sd(win_count_diff) / sqrt(n),
              lower_se = mean_win_count_diff - se,
              upper_se = mean_win_count_diff + se)
}

# Divide each subject's trials into blocks of size blocksize (e.g. 10 trials)
# then get each *bot's* win percent in each block
get_bot_block_data = function(data, blocksize) {
  data %>%
    filter(is_bot == 1) %>%
    group_by(bot_strategy, round_index) %>%
    mutate(round_block = ceiling(round_index / blocksize)) %>%
    select(bot_strategy, round_index, game_id, player_id, player_outcome, round_block) %>%
    group_by(bot_strategy, game_id, player_id, round_block) %>%
    count(win = player_outcome == "win") %>%
    mutate(total = sum(n),
           win_pct = n / total) %>%
    filter(win == TRUE)
}

# Take in block win percent data (calculated above) and summarize by bot strategy
get_block_data_summary = function(subject_block_data) {
  subject_block_data %>%
    group_by(bot_strategy, round_block) %>%
    summarize(subjects = n(),
              mean_win_pct = mean(win_pct),
              se_win_pct = sd(win_pct) / sqrt(subjects),
              lower_ci = mean_win_pct - se_win_pct,
              upper_ci = mean_win_pct + se_win_pct)
}


# GRAPH STYLE ==================================================================

default_plot_theme = theme(
  # titles
  plot.title = element_text(face = "bold", size = 20),
  axis.title.y = element_text(face = "bold", size = 16),
  axis.title.x = element_text(face = "bold", size = 16),
  legend.title = element_text(face = "bold", size = 16),
  # axis text
  axis.text.y = element_text(size = 14, face = "bold"),
  axis.text.x = element_text(size = 14, angle = 45, vjust = 0.5, face = "bold"),
  # legend text
  legend.text = element_text(size = 16, face = "bold"),
  # facet text
  strip.text = element_text(size = 12),
  # backgrounds, lines
  panel.background = element_blank(),
  strip.background = element_blank(),

  panel.grid = element_line(color = "gray"),
  axis.line = element_line(color = "black"),
  # positioning
  legend.position = "bottom",
  legend.key = element_rect(colour = "transparent", fill = "transparent")
)

label_width = 48 # default: 10
# label_width = 10 # default: 10

strategy_labels = c("opponent_moves" = str_wrap(STRATEGY_LOOKUP[["opponent_moves"]], label_width),
                    "opponent_prev_move" = str_wrap(STRATEGY_LOOKUP[["opponent_prev_move"]], label_width),
                    "bot_prev_move" = str_wrap(STRATEGY_LOOKUP[["bot_prev_move"]], label_width),
                    "opponent_bot_prev_move" = str_wrap(STRATEGY_LOOKUP[["opponent_bot_prev_move"]], label_width),
                    "opponent_prev_two_moves" = str_wrap(STRATEGY_LOOKUP[["opponent_prev_two_moves"]], label_width),
                    "bot_prev_two_moves" = str_wrap(STRATEGY_LOOKUP[["bot_prev_two_moves"]], label_width),
                    "opponent_transitions" = str_wrap(STRATEGY_LOOKUP[["opponent_transitions"]], label_width),
                    "opponent_courn_transitions" = str_wrap(STRATEGY_LOOKUP[["opponent_courn_transitions"]], label_width),
                    "opponent_outcome_transitions" = str_wrap(STRATEGY_LOOKUP[["opponent_outcome_transitions"]], label_width),
                    "opponent_outcome_prev_transition_dual" = str_wrap(STRATEGY_LOOKUP[["opponent_outcome_prev_transition_dual"]], label_width))


# GRAPH FUNCTIONS ==============================================================

plot_block_summary = function(summary_data, individ_data) {
  block_labels = c("1" = "30", "2" = "60", "3" = "90", "4" = "120", "5" = "150",
                   "6" = "180", "7" = "210", "8" = "240", "9" = "270", "10" = "300")
  summary_data %>%
    ggplot(aes(x = round_block, y = mean_win_pct, color = bot_strategy)) +
    geom_point(size = 6, alpha = 0.75) +
    geom_errorbar(aes(ymin = lower_ci, ymax = upper_ci), size = 1, width = 0.25, alpha = 0.75) +
    geom_jitter(data = individ_data, aes(x = round_block, y = win_pct),
                width = 0.1, height = 0, size = 2, alpha = 0.5) +
    geom_hline(yintercept = 1 / 3, linetype = "dashed", color = "red", size = 1) +
    labs(x = "Game round", y = "Bot win percentage") +
    # ggtitle("Bot win percentage against participants") +
    scale_color_viridis(discrete = T,
                        name = element_blank(),
                        labels = strategy_labels) +
    scale_x_continuous(labels = block_labels, breaks = seq(1:10)) +
    # ylim(c(0, 1)) +
    default_plot_theme +
    theme(#axis.text.x = element_blank(),
      axis.title.y = element_text(size = 24, face = "bold"),
      legend.text = element_text(face = "bold", size = 14),
      # legend.position = "right",
      legend.spacing.y = unit(1.0, 'lines'),
      #legend.key = element_rect(size = 2),
      legend.key.size = unit(4.75, 'lines'))
}

plot_slider_data = function(slider_summary, slider_indiv) {
  q = unique(slider_summary$statement)
  slider_summary %>%
    ggplot(aes(x = bot_strategy, y = mean_resp, color = bot_strategy)) +
    geom_point(size = 6) +
    # NB: comment out the jitter below to remove individual data points for easier summary
    geom_jitter(data = slider_indiv,
                aes(x = bot_strategy, y = resp, color = bot_strategy),
                alpha = 0.75) +
    geom_errorbar(aes(ymin = se_lower, ymax = se_upper), size = 1, width = 0.25) +
    scale_color_viridis(discrete = T,
                        name = element_blank(),
                        labels = element_blank()) +
    scale_x_discrete(name = element_blank(),
                     labels = strategy_labels) +
    # ylim(c(1, 7)) +
    labs(y = "Mean response (1: Strongly disagree, 7: Strongly agree)") +
    ggtitle(str_wrap(q, 50)) +
    default_plot_theme +
    theme(axis.text.x = element_text(angle = 0, vjust = 1),
          axis.title.x = element_blank(),
          legend.position = "none")
}



# PROCESS DATA =================================================================

# Read in data
data = read_csv(DATA_FILE)
data$bot_strategy = factor(data$bot_strategy, levels = STRATEGY_LEVELS)

# Remove all incomplete games
incomplete_games = data %>%
  group_by(game_id, player_id) %>%
  summarize(rounds = max(round_index)) %>%
  filter(rounds < NUM_ROUNDS) %>%
  select(game_id) %>%
  unique()
incomplete_games

data = data %>%
  filter(!(game_id %in% incomplete_games$game_id))

# TODO players with "NA" moves; look into this
# (processing python script writes NA for empty move values)
tmp = data %>% filter(is.na(player_move))
tmp %>% group_by(sona_survey_code) %>% summarize(n())
data = data %>% filter(!is.na(player_move))


# Remove any duplicate complete games that have the same SONA survey code
# NB: this can happen if somebody played all the way through but exited before receiving credit
# First, fetch sona survey codes with multiple complete games
repeat_codes = data %>%
  group_by(sona_survey_code) %>%
  filter(is_bot == 0) %>%
  summarize(trials = n()) %>%
  filter(trials > NUM_ROUNDS) %>%
  select(sona_survey_code)
repeat_codes
# Next, get game id for the earlier complete game
# NB: commented out code checks that we have slider/free resp data for at least one of the games
duplicate_games = data %>%
  filter(sona_survey_code %in% repeat_codes$sona_survey_code &
           is_bot == 0  &
           round_index == NUM_ROUNDS) %>%
  select(sona_survey_code, game_id, player_id, round_begin_ts) %>%
  # remove the later one to avoid results based on experience
  group_by(sona_survey_code) %>%
  filter(round_begin_ts == max(round_begin_ts)) %>%
  # joins below check whether we have slider/free resp data for earlier or later survey code responses
  # inner_join(fr_data, by = c("game_id", "player_id")) %>%
  # inner_join(slider_data, by = c("game_id", "player_id")) %>%
  distinct(game_id)
duplicate_games

data = data %>%
  filter(!game_id %in% duplicate_games$game_id)


# Sanity check: anybody with trials != 300?
trial_count = data %>%
  filter(is_bot == 0) %>%
  group_by(sona_survey_code) %>%
  summarize(trials = n()) %>%
  filter(trials != NUM_ROUNDS)
trial_count


# Check that there are no rows with memory >= 300
# (this was a bug in early data)
mem = data %>%
  filter(round_index == NUM_ROUNDS & is_bot == 1) %>%
  group_by(bot_strategy, game_id, sona_survey_code) %>%
  select(bot_strategy, game_id, sona_survey_code, bot_round_memory)

mem = mem %>%
  rowwise() %>%
  mutate(memory_sum =
           sum(as.numeric(unlist(regmatches(bot_round_memory, gregexpr("[[:digit:]]+", bot_round_memory))))))

mem = mem %>% filter(memory_sum >= NUM_ROUNDS)

data = data %>%
  filter(!sona_survey_code %in% mem$sona_survey_code)



fr_data = read_free_resp_data(FREE_RESP_FILE, data)
slider_data = read_slider_data(SLIDER_FILE, data)
slider_summary = get_slider_summary(slider_data)


# ANALYSIS: participant RTs etc. ===============================================

# How many complete participants for each bot?
data %>%
  filter(is_bot == 0, round_index == NUM_ROUNDS) %>%
  group_by(bot_strategy) %>%
  summarize(subjects = n()) %>%
  summarize(sum(subjects))

# How many times did players play a particular move?
# Note the first person here forced a bot WCD of -67; playing scissors repeatedly
# put the bot in a cycle of loss, tie, loss, ...
# Another person lost 288 times, so move choice is not an exclusion criteria by itself, but can be
data %>%
  filter(is_bot == 0) %>%
  group_by(game_id, player_id) %>%
  count(player_move) %>%
  filter(n >= 250)

# How long did participants take to choose a move?
rt_summary = data %>%
  filter(is_bot == 0) %>% # NB: filtering for actual moves here doesn't decrease mean that much
  group_by(player_id) %>%
  summarize(mean_rt = mean(player_rt),
            mean_log_rt = mean(log10(player_rt)),
            nrounds = n())
rt_summary
mean(rt_summary$mean_log_rt)
sd(rt_summary$mean_log_rt)

# And how often did they choose "none"?
none_moves = data %>%
  filter(is_bot == 0) %>%
  group_by(player_id) %>%
  filter(player_move == "none") %>%
  count(player_move)
none_moves %>% ungroup() %>% filter(n == max(n))

# How long do people spend overall?
completion_summary = data %>%
  filter(is_bot == 0) %>%
  group_by(player_id) %>%
  summarize(completion_time = round_begin_ts[round_index == NUM_ROUNDS],
            start_time =  round_begin_ts[round_index == 1],
            total_secs = (completion_time - start_time) / 1000)

mean(completion_summary$total_secs)
sd(completion_summary$total_secs)


# this person finished the experiment in 90s, chose paper 275 times, and lost 288 times
data = data %>%
  filter(game_id != "f7290e62-697c-46ec-b42d-51090ce3eed5")


# ANALYSIS: Bot strategy win count differentials ===============================
wcd_all = get_bot_strategy_win_count_differential(data)
# exclude data for participant with 200+ losing choices of paper
wcd_summary = get_bot_strategy_win_count_differential_summary(wcd_all)

complexity_lookup = c(
  "opponent_transitions" = "3 cell memory",
  "opponent_courn_transitions" = "3 cell memory",
  "opponent_prev_move" = "9 cell memory",
  "bot_prev_move" = "9 cell memory",
  "opponent_outcome_transitions" = "9 cell memory",
  "opponent_bot_prev_move" = "27 cell memory",
  "opponent_prev_two_moves" = "27 cell memory",
  "opponent_outcome_prev_transition_dual" = "27 cell memory"
)
wcd_summary = wcd_summary %>%
  rowwise() %>%
  mutate(complexity = complexity_lookup[bot_strategy])
wcd_summary$complexity = factor(wcd_summary$complexity,
                                levels = c("3 cell memory", "9 cell memory", "27 cell memory"))

wcd_all = wcd_all %>%
  rowwise() %>%
  mutate(complexity = complexity_lookup[bot_strategy])
wcd_all$complexity = factor(wcd_all$complexity,
                            levels = c("3 cell memory", "9 cell memory", "27 cell memory"))


wcd_summary %>%
  ggplot(aes(x = bot_strategy, y = mean_win_count_diff, color = complexity)) +
  geom_point(size = 6) +
  geom_errorbar(
    aes(ymin = lower_se, ymax = upper_se),
    width = 0.1, size = 1) +
  # geom_jitter(data = wcd_all, aes(x = bot_strategy, y = win_count_diff),
  #             size = 2, alpha = 0.75, width = 0.25, height = 0) +
  geom_hline(yintercept = 0, size = 1, linetype = "dashed") +
  labs(x = "", y = "Bot win count differential") +
  ggtitle("Adaptive bot performance against humans") +
  scale_x_discrete(
    name = element_blank(),
    labels = strategy_labels) +
  scale_color_manual(
    name = "Complexity",
    values = wes_palette("Zissou1", 3, type = "continuous")) +
  default_plot_theme +
  theme(
    plot.title = element_text(size = 32, face = "bold"),
    axis.title.y = element_text(size = 24, face = "bold"),
    # NB: axis title below is to give cushion for adding complexity labels in PPT
    # axis.title.x = element_text(size = 64),
    # axis.text.x = element_blank(),
    axis.text.x = element_text(size = 12, face = "bold", angle = 0, vjust = 1),
    axis.text.y = element_text(size = 14, face = "bold"),
    legend.position = "bottom",
    legend.title = element_text(size = 18, face = "bold"),
    legend.text = element_text(size = 16)
  )


# Basic analysis: which strategies are different from 0?
table(wcd_all$bot_strategy)

t.test(x = wcd_all$win_count_diff[wcd_all$bot_strategy == "opponent_transitions"]) # *
t.test(x = wcd_all$win_count_diff[wcd_all$bot_strategy == "opponent_courn_transitions"]) # ***
t.test(x = wcd_all$win_count_diff[wcd_all$bot_strategy == "opponent_prev_move"]) # NS
t.test(x = wcd_all$win_count_diff[wcd_all$bot_strategy == "bot_prev_move"]) # **
t.test(x = wcd_all$win_count_diff[wcd_all$bot_strategy == "opponent_outcome_transitions"]) # NS
t.test(x = wcd_all$win_count_diff[wcd_all$bot_strategy == "opponent_bot_prev_move"]) # *
t.test(x = wcd_all$win_count_diff[wcd_all$bot_strategy == "opponent_prev_two_moves"]) # ***
t.test(x = wcd_all$win_count_diff[wcd_all$bot_strategy == "opponent_outcome_prev_transition_dual"]) # ***


# Aggregating across strategy complexity
wcd_all = wcd_all %>%
  rowwise() %>%
  mutate(complexity = complexity_lookup[bot_strategy])
wcd_all$complexity = factor(wcd_all$complexity,
                            levels = c("3 cell memory", "9 cell memory", "27 cell memory"))


t.test(wcd_all$win_count_diff[wcd_all$complexity == "3 cell memory"]) # ***
t.test(wcd_all$win_count_diff[wcd_all$complexity == "9 cell memory"]) # ***
t.test(wcd_all$win_count_diff[wcd_all$complexity == "27 cell memory"]) # ***


# Difference between participant-relative and bot-relative deps
t.test(
  c(
    wcd_all$win_count_diff[wcd_all$bot_strategy == "opponent_transitions"],
    wcd_all$win_count_diff[wcd_all$bot_strategy == "opponent_prev_move"]),
  c(
    wcd_all$win_count_diff[wcd_all$bot_strategy == "opponent_courn_transitions"],
    wcd_all$win_count_diff[wcd_all$bot_strategy == "bot_prev_move"])
)

# Binomial tests
binom.test(
  x = sum(wcd_all$win_count_diff[wcd_all$bot_strategy == "opponent_transitions"] < 0),
  n = length(wcd_all$win_count_diff[wcd_all$bot_strategy == "opponent_transitions"])
)

binom.test(
  x = sum(wcd_all$win_count_diff[wcd_all$bot_strategy == "opponent_courn_transitions"] < 0),
  n = length(wcd_all$win_count_diff[wcd_all$bot_strategy == "opponent_courn_transitions"])
)

binom.test(
  x = sum(wcd_all$win_count_diff[wcd_all$bot_strategy == "opponent_prev_move"] < 0),
  n = length(wcd_all$win_count_diff[wcd_all$bot_strategy == "opponent_prev_move"])
)

binom.test(
  x = sum(wcd_all$win_count_diff[wcd_all$bot_strategy == "bot_prev_move"] < 0),
  n = length(wcd_all$win_count_diff[wcd_all$bot_strategy == "bot_prev_move"])
)

binom.test(
  x = sum(wcd_all$win_count_diff[wcd_all$bot_strategy == "opponent_outcome_transitions"] < 0),
  n = length(wcd_all$win_count_diff[wcd_all$bot_strategy == "opponent_outcome_transitions"])
)

binom.test(
  x = sum(wcd_all$win_count_diff[wcd_all$bot_strategy == "opponent_bot_prev_move"] < 0),
  n = length(wcd_all$win_count_diff[wcd_all$bot_strategy == "opponent_bot_prev_move"])
)

binom.test(
  x = sum(wcd_all$win_count_diff[wcd_all$bot_strategy == "opponent_prev_two_moves"] <= 0),
  n = length(wcd_all$win_count_diff[wcd_all$bot_strategy == "opponent_prev_two_moves"])
)

binom.test(
  x = sum(wcd_all$win_count_diff[wcd_all$bot_strategy == "opponent_outcome_prev_transition_dual"] <= 0),
  n = length(wcd_all$win_count_diff[wcd_all$bot_strategy == "opponent_outcome_prev_transition_dual"])
)




# ANALYSIS: compare to dyad results ============================================

dyad_wcd_summary = bind_rows(
  get_win_count_differential_summary(player_transition_utils, "opponent_transitions"),
  get_win_count_differential_summary(player_transition_cournot_utils, "opponent_courn_transitions"),
  get_win_count_differential_summary(player_prev_move_utils, "opponent_prev_move"),
  get_win_count_differential_summary(opponent_prev_move_utils, "bot_prev_move"),
  get_win_count_differential_summary(player_transition_prev_outcome_utils, "opponent_outcome_transitions"),
  get_win_count_differential_summary(player_opponent_prev_move_utils, "opponent_bot_prev_move"),
  get_win_count_differential_summary(player_prev_2move_utils, "opponent_prev_two_moves"),
  get_win_count_differential_summary(player_transition_prev_transition_prev_outcome_utils, "opponent_outcome_prev_transition_dual")
)

dyad_wcd_summary$category = factor(dyad_wcd_summary$category, levels = STRATEGY_LEVELS)



# Correlation between expected win count diff.
# and empirical win count diffs from adaptive bots
cor.test(dyad_wcd_summary$mean_wins, wcd_summary$mean_win_count_diff)



combined_wcd = wcd_summary %>%
  rename(category = bot_strategy) %>%
  inner_join(dyad_wcd_summary, by = c("category"))

combined_wcd %>%
  ggplot(aes(x = mean_wins, y = mean_win_count_diff,
             color = category)) +
  geom_point(size = 6) +
  geom_errorbar(aes(color = category,
                    ymin = lower_se, ymax = upper_se),
                width = 1, size = 1) +
  geom_errorbarh(aes(color = category,
                     xmin = ci_lower, xmax = ci_upper), size = 1) +
  geom_hline(yintercept = 0, size = 1, linetype = "dashed") +
  scale_color_manual(name = element_blank(),
                     labels = strategy_labels,
                     values = wes_palette("Zissou1", 8, type = "continuous")) +
  labs(x = "Human dyad expected win count differential \n",
       y = "Bot win count differential") +
  ggtitle("Exploitability in bots v. other humans") +
  default_plot_theme +
  theme(
    plot.title = element_text(size = 32, face = "bold"),
    axis.title.y = element_text(size = 24, face = "bold"),
    axis.text.y = element_text(size = 14, face = "bold", angle = 0, vjust = 1),
    axis.title.x = element_text(size = 24, face = "bold"),
    axis.text.x = element_text(size = 14, face = "bold", angle = 0, vjust = 1),
    legend.position = "bottom",
    legend.text = element_text(size = 14)
  ) +
  guides(color=guide_legend(ncol = 2))



# APPENDIX: Free response ======================================================

fr_data %>%
  arrange(bot_strategy, strategy, game_id, player_id, free_resp_answer) %>%
  select(strategy, game_id, player_id, free_resp_answer)


# APPENDIX: Slider scales ======================================================

slider_game_data = wcd_all %>%
  inner_join(slider_data, by = c("game_id"))



slider_qs = unique(slider_summary$statement)

# Do slider responses vary significantly across bot strategies?
anova_q1 = with(slider_data[slider_data$statement == slider_qs[1],],
                aov(resp ~ bot_strategy))
summary(anova_q1)

anova_q2 = with(slider_data[slider_data$statement == slider_qs[2],],
                aov(resp ~ bot_strategy))
summary(anova_q2)

anova_q3 = with(slider_data[slider_data$statement == slider_qs[3],],
                aov(resp ~ bot_strategy))
summary(anova_q3)

anova_q4 = with(slider_data[slider_data$statement == slider_qs[4],],
                aov(resp ~ bot_strategy))
summary(anova_q4)

anova_q5 = with(slider_data[slider_data$statement == slider_qs[5],],
                aov(resp ~ bot_strategy))
summary(anova_q5)



q1_plot = slider_summary %>%
  filter(statement == slider_qs[1]) %>%
  plot_slider_data(., slider_data[slider_data$statement == slider_qs[1],])

q2_plot = slider_summary %>%
  filter(statement == slider_qs[2]) %>%
  plot_slider_data(., slider_data[slider_data$statement == slider_qs[2],])

q3_plot = slider_summary %>%
  filter(statement == slider_qs[3]) %>%
  plot_slider_data(., slider_data[slider_data$statement == slider_qs[3],])

q4_plot = slider_summary %>%
  filter(statement == slider_qs[4]) %>%
  plot_slider_data(., slider_data[slider_data$statement == slider_qs[4],])

q5_plot = slider_summary %>%
  filter(statement == slider_qs[5]) %>%
  plot_slider_data(., slider_data[slider_data$statement == slider_qs[5],])


q1_plot + q2_plot + q3_plot + q4_plot + q5_plot +
  plot_layout(ncol = 2)



