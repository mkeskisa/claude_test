# Database connection management
# Use a real DBI connection for SQL execution and dbplyr queries.

create_connection <- function(dbname = DB_PATH) {
  if (!identical(dbname, ":memory:")) {
    directory <- dirname(dbname)
    if (!dir.exists(directory) && !dir.create(directory, recursive = TRUE)) {
      stop("Could not create the database directory.", call. = FALSE)
    }
  }
  con <- DBI::dbConnect(RSQLite::SQLite(), dbname = dbname)
  tryCatch({
    DBI::dbExecute(con, "PRAGMA foreign_keys = ON")
    DBI::dbExecute(con, "PRAGMA busy_timeout = 5000")
  }, error = function(e) {
    DBI::dbDisconnect(con)
    stop(e)
  })
  con
}

close_connection <- function(con) {
  if (check_connection(con)) {
    DBI::dbDisconnect(con)
  }
  invisible(TRUE)
}

get_connection <- function(dbname = DB_PATH) {
  create_connection(dbname)
}

check_connection <- function(con) {
  inherits(con, "DBIConnection") && isTRUE(tryCatch(DBI::dbIsValid(con), error = function(e) FALSE))
}

table_exists <- function(con, table_name) {
  DBI::dbExistsTable(con, table_name)
}

table_data_exists <- function(con, table_name) {
  table_exists(con, table_name)
}

get_table_data <- function(con, table_name) {
  if (!table_data_exists(con, table_name)) {
    stop(sprintf("Data for table '%s' is not available on this connection.", table_name), call. = FALSE)
  }

  DBI::dbReadTable(con, table_name)
}
