# Main entry point script
# Sources all relevant scripts in order to run the project

# Source configuration
source("R/config.R", local = TRUE)
check_packages()

# Source database connection management
source("db/connection.R", local = TRUE)

# Source database setup functions
source("R/database_setup.R", local = TRUE)

# Source OMOP schema definitions
source("R/omop_schema.R", local = TRUE)

# Source analytics helpers
source("R/analytics.R", local = TRUE)

# Reuse this project's open connection when sourced again in RStudio.
reuse_connection <- exists("con", inherits = FALSE) &&
  inherits(con, "SQLiteConnection") && check_connection(con) &&
  identical(
    normalizePath(DBI::dbGetInfo(con)$dbname, winslash = "/", mustWork = FALSE),
    normalizePath(DB_PATH, winslash = "/", mustWork = FALSE)
  )
if (!reuse_connection) con <- create_connection()
tryCatch(initialize_mock_database(con), error = function(e) {
  close_connection(con)
  stop(e)
})

# Display connection info
cat("SQLite database ready.\n")
cat("Backend:", DB_BACKEND, "\n")
cat("File:", DB_PATH, "\n")
cat("Patients loaded:", nrow(get_table_data(con, "patient")), "\n")

# Display available tables
cat("\nAvailable OMOP tables:\n")
cat("  - patient\n")
cat("  - visit_occurrence\n")
cat("  - condition_occurrence\n")
cat("  - drug_exposure\n")
cat("  - procedure_occurrence\n")
cat("  - observation\n")
cat("  - measurement\n")

cat("\nTop condition prevalence rows:\n")
print(utils::head(calculate_condition_prevalence(con), 5))

# Run tests
cat("\nRunning tests...\n")
testthat::test_dir(file.path(PROJECT_ROOT, "tests"))

cat("\nConnection 'con' remains open for queries in this R session.\n")
cat('Try: DBI::dbGetQuery(con, "SELECT * FROM patient LIMIT 10")\n')
cat("When finished: close_connection(con)\n")
