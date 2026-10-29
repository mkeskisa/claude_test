# Query the persistent example database and export summary CSV files.

source("R/config.R", local = TRUE)
source("db/connection.R", local = TRUE)
source("R/database_setup.R", local = TRUE)
source("R/omop_schema.R", local = TRUE)
source("R/analytics.R", local = TRUE)

run_analysis <- function() {
  check_packages()
  analysis_con <- create_connection()
  on.exit(close_connection(analysis_con), add = TRUE)
  initialize_mock_database(analysis_con)

  report <- build_mock_analysis_report(analysis_con)
  export_paths <- export_mock_analysis_report(report, file.path(PROJECT_ROOT, "outputs", "analysis"))

  cat("Synthetic OMOP-style data in SQLite:\n", DB_PATH, "\n")
  counts <- example_table_counts(analysis_con)
  for (table_name in names(counts)) {
    cat(table_name, ": ", counts[[table_name]], " rows\n", sep = "")
  }

  cat("\nRecorded condition prevalence in the synthetic sample (2024-2025):\n")
  print(report$prevalence)
  cat("\nDemographic prevalence sample:\n")
  print(utils::head(report$demographic_prevalence, 10))
  cat("\nUtilization summary:\n")
  print(report$utilization)
  cat("\nCSV summaries written to:\n")
  cat(paste0("  ", export_paths, collapse = "\n"), "\n")
  invisible(report)
}

report <- run_analysis()
