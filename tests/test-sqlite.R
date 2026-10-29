test_that("SQL and dbplyr execute against the same stored data", {
  con <- local_test_db_connection()
  on.exit(close_connection(con), add = TRUE)
  populate_mock_data(con)

  expect_s4_class(con, "SQLiteConnection")
  expect_setequal(DBI::dbListTables(con), names(omop_table_specs()))
  sql <- DBI::dbGetQuery(con, "SELECT subject_id FROM patient WHERE year_of_birth < 1960 ORDER BY subject_id")
  collected <- omop_patient(con) |>
    dplyr::filter(year_of_birth < 1960) |>
    dplyr::select(subject_id) |>
    dplyr::arrange(subject_id) |>
    dplyr::collect()
  expect_equal(collected$subject_id, sql$subject_id)
  expect_gt(nrow(collected), 0L)

  sql_prevalence <- DBI::dbGetQuery(con, "
    SELECT condition_concept_id, COUNT(DISTINCT c.subject_id) AS patient_count,
      1.0 * COUNT(DISTINCT c.subject_id) / (SELECT COUNT(*) FROM patient) AS prevalence
    FROM condition_occurrence c JOIN patient p ON c.subject_id = p.subject_id
    GROUP BY condition_concept_id ORDER BY condition_concept_id
  ")
  report <- calculate_condition_prevalence(con) |>
    dplyr::arrange(condition_concept_id)
  expect_equal(sql_prevalence$patient_count, report$patient_count)
  expect_equal(sql_prevalence$prevalence, report$prevalence)

  DBI::dbExecute(con, "UPDATE patient SET year_of_birth = 1950 WHERE patient_id = 1")
  expect_equal(get_table_data(con, "patient")$year_of_birth[1], 1950L)
})

test_that("SQLite persists rows and repeated initialization preserves edits", {
  db_path <- tempfile(fileext = ".sqlite")
  con <- create_connection(db_path)
  on.exit({ close_connection(con); unlink(db_path) }, add = TRUE)
  initialize_mock_database(con)
  DBI::dbExecute(con, "UPDATE patient SET gender = 'Edited' WHERE patient_id = 1")
  counts <- example_table_counts(con)
  close_connection(con)
  expect_false(check_connection(con))

  con <- create_connection(db_path)
  initialize_mock_database(con)
  expect_equal(example_table_counts(con), counts)
  expect_equal(DBI::dbGetQuery(con, "SELECT gender FROM patient WHERE patient_id = 1")$gender, "Edited")
  expect_error(populate_mock_data(con), "already contain data")
  expect_equal(example_table_counts(con), counts)
})

test_that("SQLite enforces patient links and preserves readable dates", {
  con <- local_test_db_connection()
  on.exit(close_connection(con), add = TRUE)
  populate_mock_data(con)
  expect_error(DBI::dbExecute(con, "INSERT INTO visit_occurrence (subject_id) VALUES (-1)"), "FOREIGN KEY")
  expect_error(DBI::dbExecute(con, "INSERT INTO patient (subject_id) SELECT subject_id FROM patient LIMIT 1"), "UNIQUE")
  expect_equal(nrow(DBI::dbGetQuery(con, "PRAGMA foreign_key_check")), 0L)

  dates <- DBI::dbGetQuery(con, "
    SELECT COUNT(*) AS n FROM condition_occurrence
    WHERE date(condition_start_datetime) IS NULL
       OR date(condition_start_datetime) != condition_start_date
       OR datetime(condition_end_datetime) < datetime(condition_start_datetime)
  ")
  expect_equal(dates$n, 0L)
})
