# Persistent SQLite database, independent of old PostgreSQL environment settings.
PROJECT_ROOT <- local({
  # Nested source() calls retain the outer script in sys.frame(1).
  source_files <- Filter(Negate(is.null), lapply(sys.frames(), function(frame) frame$ofile))
  root <- if (length(source_files)) {
    file.path(dirname(tail(source_files, 1)[[1]]), "..")
  } else {
    "."
  }
  normalizePath(root, winslash = "/", mustWork = TRUE)
})
DB_PATH <- file.path(PROJECT_ROOT, "outputs", "omop.sqlite")
DB_SCHEMA <- "main"
DB_BACKEND <- "RSQLite"

# Load required packages
required_packages <- c("DBI", "RSQLite", "dbplyr", "dplyr", "testthat")

check_packages <- function() {
  for (pkg in required_packages) {
    if (!requireNamespace(pkg, quietly = TRUE)) {
      stop(sprintf("Package '%s' is required. Run install.packages('%s') once.", pkg, pkg), call. = FALSE)
    }
  }
}
