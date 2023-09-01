library(data.table)
library(magrittr)
source("../plots_and_stats/plotting_helperfuns.R")
source("helperfuns.R")

# get interventions
interventionsDT <- fread(file = '../ignore/output/v2/interventions2.csv')
interventionsDT$timestamp <- as.POSIXct(interventionsDT$timestamp/1000, origin="1970-01-01") 
interventionsDT[, nthIntervention := rowid(session_id)]

block_id_cols <- c("id_0", "id_1", "id_2", "id_3", "id_4", "id_5")

plotSess <- function(sess) {
  sessDT <- interventionsDT[session_id == sess]
  sessDT <- melt(sessDT, measure.vars = block_id_cols, variable.name = "block_id", value.name = "block_state")
  levels(sessDT$block_id) <- list("Blicket 1"="id_0", "Blicket 2"="id_1", "Blicket 3"="id_2", "Non-Blicket 1"="id_3", "Non-Blicket 2"="id_4", "Non-Blicket 3"="id_5")
  sessDT[outcome == FALSE, outcome_char := "Nothing"]
  sessDT[outcome == TRUE, outcome_char := "Activation"]
  ggplot(data = sessDT, aes(x = nthIntervention, y = block_state, fill = outcome_char)) +
    geom_col(width = 0.1) +
    scale_fill_brewer(palette = "Dark2") +
    facet_grid("block_id ~ .", switch = "y") +
    scale_x_discrete(limits=1:max(sessDT$nthIntervention)) +
    ylab(NULL) +
    xlab("Intervention") +
    labs(fill = "Blicket Machine\nResponse") +
    theme_mine() +
    theme(panel.spacing = unit(0, "lines"),
          axis.text.y=element_blank(),
          axis.ticks.y=element_blank(),
          panel.border = element_blank(),
          panel.grid.major.y = element_blank(),
          panel.grid.major.x = element_line( size=.3, color="light gray"),
          strip.text.y.left = element_text(angle = 0, hjust = 0),
          legend.position = "top",
          plot.title = element_text(size = 10, face = "bold", margin = margin(0, 0, 5, 0), hjust = 0.05),
          legend.key.size = unit(0.5, 'cm'),
          plot.margin = margin(0, 0, 0.3, 0, unit = "cm"))
}

# plotSess("NUC1Zp1CqK4h3vT4okD2FAkSxWMS9gVb")

legend <- get_legend(plotSess("NUC1Zp1CqK4h3vT4okD2FAkSxWMS9gVb"))

hbmP <- plotSess("NUC1Zp1CqK4h3vT4okD2FAkSxWMS9gVb") + ggtitle("HBM Participant") + theme(legend.position = "none")

noTransferP <- plotSess("bh9MvmNflP9cVw63DvOMSx9qFBTWRkY0") + ggtitle("No-Transfer Participant") + theme(legend.position = "none")

structOnlyP <- plotSess("ye7cOoHSbasWoqnJrdnCf3adcQ5IlM4C") + ggtitle("Structure-Only-EIG Participant") + theme(legend.position = "none")

randP <- plotSess("kr7cXcBBAXw8qObaZeOrb9l9FSuds2bQ") + ggtitle("Random Participant") + theme(legend.position = "none")

allP <- plot_grid(hbmP, noTransferP, structOnlyP, randP, legend, ncol = 1, rel_heights = c(rep(0.93/4, 4), 0.07), labels = c("a", "b", "c", "d"), label_size = 10, hjust = 0, vjust = 1.15)

save_plot(filename = "../../../Dropbox/drafts/2021-Feb_active_overhypo_modeling/imgs/example_ind.pdf", plot = allP, base_height = NULL, base_width = 5, base_asp = 0.7)