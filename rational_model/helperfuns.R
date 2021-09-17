createDirs <- function(dirpath) {
  # recursively create the directories if they don't already exist
  
  if (!dir.exists(dirpath)) {
    dir.create(dirpath, recursive = TRUE)
  }
}

softmax <- function(vec, temperature) {
  beta <- 1/temperature
  numerators = exp(vec*beta)
  denom = sum(numerators)
  numerators/denom
}
# softmax(c(0, 10), 100)
# 0.4750208 0.5249792

weightedSoftmax <- function(vec, temperature, randP, epsilon) {
  assert(epsilon >= 0 && epsilon <= 1)
  epsilon*randP + (1-epsilon)*softmax(vec, temperature)
}

weightedAdd <- function(vec1, vec2, weight1) {
  stopifnot(length(vec1) == length(vec2))
  stopifnot(weight1 >= 0 && weight1 <= 1)
  
  weight1*vec1 + (1-weight1)*vec2
}
# weightedAdd(c(1, 10), c(10, 100), 0.1)
# 9.1 91

idColsToStr <- function(resultsDT, ids) {
  idCols <- sapply(ids, function(x) paste0("id_", x))
  strCols <- sapply(ids, function(x) paste0("str_", x))
  dt <- resultsDT[, ..idCols]
  
  for (i in 1:length(ids)) {
    dt[, (strCols[i]) := ""]
    dt[dt[[idCols[i]]] == 1, (strCols[i]) := as.character(ids[i])]
    dt[, (idCols[i]) := NULL]  # remove original column
  }
  
  apply(dt, 1, paste0, collapse="")
}

se <- function(x) sd(x, na.rm = TRUE)/sqrt(length(x))
