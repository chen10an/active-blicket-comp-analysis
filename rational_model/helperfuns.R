createDirs <- function(dirpath) {
  # recursively create the directories if they don't already exist
  
  if (!dir.exists(dirpath)) {
    dir.create(dirpath, recursive = TRUE)
  }
}