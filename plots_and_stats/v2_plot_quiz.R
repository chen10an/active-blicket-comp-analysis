library(data.table)
library(magrittr)

source("plotting_helperfuns.R")

quizDT <- fread(file="../ignore/output/v2_quiz_rating.csv")

# TODO: 
# fquizDT <- fread(file="../ignore/output/nine_combo_quiz_design_matrix.csv")

# combine (rowwise) full and filtered data sets for the sake of plotting
# quizDT[, is_filtered := 0]
# fquizDT[, is_filtered := 1]
# allQuizDT <- rbind(quizDT, fquizDT)

# make factors
# order from "least blocks" to "most blocks" needed for activation
quizDT[, training := factor(training, levels = c('d1', 'nd1', 'c1', 'nc1', 'cc1', 'ncc1'))]
quizDT[, is_blicket := factor(is_blicket, levels = c(1, 0))]

# box plot -----
box_p <- ggplot(data=quizDT, aes(x = training, y = rating, color = is_blicket)) +
  geom_boxplot() +
  facet_grid(cols = vars(level)) +
  scale_color_manual(values=c("black", "gray")) +
  theme_mine()
box_p

save_plot(filename = "../ignore/v2_paper/imgs/ratings_box.pdf", plot = box_p, base_height = NULL, base_width = 8, base_asp = 3.1)

# line plot -----
# standard error
se <- function(x) sd(x)/sqrt(length(x))
# calculate mean and standard error used in plot
# agg for "aggregated over all participants"
summDT <- quizDT[, .(mean_rating = mean(rating), se_mean_rating = se(rating)), by=.(training, level, is_blicket)]

# TODO: error bars
line_p <- ggplot(data=summDT, aes(x = training, y = mean_rating, linetype=is_blicket, shape=is_blicket, group=is_blicket)) +
  geom_line() +
  geom_point(size=2) +
  geom_ribbon(data=summDT[is_blicket == 0], aes(ymin = 0, ymax = mean_rating), alpha = 0.3, outline.type = "upper") +
  geom_ribbon(data=summDT[is_blicket == 1], aes(ymin = mean_rating, ymax = 10), alpha = 0.3, outline.type = "lower") +
  facet_grid(cols = vars(level)) +
  scale_shape_manual(values=c(1, 16)) +
  scale_linetype_manual(values=c("solid", "dashed")) +
  theme_mine()
line_p

save_plot(filename = "../ignore/v2_paper/imgs/ratings_line.pdf", plot = line_p, base_height = NULL, base_width = 8, base_asp = 3.1)