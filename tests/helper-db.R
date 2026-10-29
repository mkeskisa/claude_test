project_root <- if (basename(getwd()) == "tests") {
  normalizePath("..", winslash = "/", mustWork = TRUE)
} else {
  normalizePath(".", winslash = "/", mustWork = TRUE)
}

source(file.path(project_root, "R", "config.R"), local = TRUE)
source(file.path(project_root, "db", "connection.R"), local = TRUE)
source(file.path(project_root, "R", "database_setup.R"), local = TRUE)
source(file.path(project_root, "R", "omop_schema.R"), local = TRUE)
source(file.path(project_root, "R", "analytics.R"), local = TRUE)

local_test_db_connection <- function() {
  con <- create_connection(":memory:")

  tryCatch(
    create_tables(con),
    error = function(e) {
      close_connection(con)
      stop(e)
    }
  )

  con
}
