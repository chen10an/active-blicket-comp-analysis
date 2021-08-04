library(data.table)
library(magrittr)

source("plotting_helperfuns.R")

quizDT <- fread(file="../ignore/output/v2_quiz_design_matrix.csv")

# TODO: 
# fquizDT <- fread(file="../ignore/output/nine_combo_quiz_design_matrix.csv")

# combine (rowwise) full and filtered data sets for the sake of plotting
# quizDT[, is_filtered := 0]
# fquizDT[, is_filtered := 1]
# allQuizDT <- rbind(quizDT, fquizDT)

# make factors
# order from "least blocks" to "most blocks" needed for activation
quizDT[, training := factor(training, levels = c('d1', 'nd1', 'c1', 'nc1', 'cc1', 'ncc1'))]

# standard error
se <- function(x) sd(x)/sqrt(length(x))
# calculate mean and standard error used in plot
# agg for "aggregated over all participants"
summDT <- quizDT[, .(blicket_mean_rating = mean(blicket_mean_rating), se_blicket_mean_rating = se(blicket_mean_rating), nonblicket_mean_rating = mean(nonblicket_mean_rating), se_nonblicket_mean_rating = se(nonblicket_mean_rating)), by=.(training, level)]

# reshape wide to long for ggplot-style grouped plotting
meanDT <- melt(summDT, id.vars = c('training', 'level'), measure.vars <- c('blicket_mean_rating', 'nonblicket_mean_rating'), value.name = 'mean_rating', variable.factor = FALSE)
meanDT[variable == 'blicket_mean_rating']$variable <- 1
meanDT[variable == 'nonblicket_mean_rating']$variable <- 0
setnames(meanDT, 'variable', 'is_blicket')

seDT <- melt(summDT, id.vars = c('training', 'level'), measure.vars <- c('se_blicket_mean_rating', 'se_nonblicket_mean_rating'), value.name = 'se_mean_rating', variable.factor = FALSE)
seDT[variable == 'se_blicket_mean_rating']$variable <- 1
seDT[variable == 'se_nonblicket_mean_rating']$variable <- 0
setnames(seDT, 'variable', 'is_blicket')

setkey(meanDT, training, level, is_blicket)
setkey(seDT, training, level, is_blicket)
plotDT <- meanDT[seDT, nomatch=0]  # inner join
stopifnot(nrow(plotDT) == nrow(meanDT))  # num rows should not change from this join

# TODO: error bars
p <- ggplot(data=plotDT, aes(x = training, y = mean_rating, linetype=is_blicket, shape=is_blicket, group=is_blicket)) +
  geom_line() +
  geom_point(size=2) +
  geom_ribbon(data=plotDT[is_blicket == 0], aes(ymin = 0, ymax = mean_rating), alpha = 0.3, outline.type = "upper") +
  geom_ribbon(data=plotDT[is_blicket == 1], aes(ymin = mean_rating, ymax = 10), alpha = 0.3, outline.type = "lower") +
  facet_grid(cols = vars(level)) +
  scale_shape_manual(values=c(1, 16)) +
  scale_linetype_manual(values=c("dashed", "solid")) +
  theme_mine()

save_plot(filename = "../ignore/v2_paper/imgs/ratings.pdf", plot = p, base_height = NULL, base_width = 8, base_asp = 3.1)