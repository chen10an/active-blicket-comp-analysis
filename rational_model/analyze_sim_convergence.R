library(data.table)
library(magrittr)

d1Sims <- fread("plots/sims/enum-uniform/d1/d1_1-100.csv")
nd1Sims <- fread("plots/sims/enum-uniform/nd1/nd1_1-100.csv")
c1Sims <- fread("plots/sims/enum-uniform/c1/c1_1-100.csv")
nc1Sims <- fread("plots/sims/enum-uniform/nc1/nc1_1-100.csv")
cc1Sims <- fread("plots/sims/enum-uniform/cc1/cc1_1-100.csv")
ncc1Sims <- fread("plots/sims/enum-uniform/ncc1/ncc1_1-100.csv")
c2Sims <- fread("plots/sims/enum-uniform/c2/c2_1-100.csv")

all(d1Sims$convergedHyp == "0-disj")
all(c1Sims$convergedHyp == "01-conj")
all(cc1Sims$convergedHyp == "012-conj3")

all(c2Sims$convergedHyp == "012-conj")

nd1Sims[, all(convergedHyp == "0-noisy_disj"), by=simID][, sum(V1)]
nc1Sims[, all(convergedHyp == "01-noisy_conj"), by=simID][, sum(V1)]
ncc1Sims[, all(convergedHyp == "012-noisy_conj3"), by=simID][, sum(V1)]
