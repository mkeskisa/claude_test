# Mock data generation and analytics tests

test_that("mock data populate all OMOP tables", {
  con <- local_test_db_connection()
  on.exit(close_connection(con), add = TRUE)

  populate_mock_data(con, seed = 1, n_patients = 120)

  expected_tables <- c(
    "patient",
    "visit_occurrence",
    "condition_occurrence",
    "drug_exposure",
    "procedure_occurrence",
    "observation",
    "measurement"
  )

  for (table_name in expected_tables) {
    expect_true(table_exists(con, table_name))
    expect_true(table_data_exists(con, table_name))
    expect_gt(nrow(get_table_data(con, table_name)), 0)
  }
})

test_that("prevalence report returns bounded metrics", {
  con <- local_test_db_connection()
  on.exit(close_connection(con), add = TRUE)

  populate_mock_data(con, seed = 99, n_patients = 180)
  report <- build_mock_analysis_report(con)

  expect_true(all(c("condition_source_value", "patient_count", "prevalence") %in% names(report$prevalence)))
  expect_true(all(report$prevalence$prevalence > 0))
  expect_true(all(report$prevalence$prevalence <= 1))
  expect_true(all(report$demographic_prevalence$prevalence <= 1))
  expect_true(any(report$utilization$metric == "mean_visits_per_patient"))
})

test_that("mock tables have unique keys and valid patient relationships", {
  tables <- generate_mock_omop_data()
  expect_identical(tables, generate_mock_omop_data())
  expect_equal(anyDuplicated(tables$patient$subject_id), 0L)

  for (table_name in names(tables)) {
    rows <- tables[[table_name]]
    primary_key <- paste0(table_name, "_id")
    expect_false(anyNA(rows[[primary_key]]), info = table_name)
    expect_equal(anyDuplicated(rows[[primary_key]]), 0L, info = table_name)
    expect_true(all(rows$subject_id %in% tables$patient$subject_id), info = table_name)
  }
})

test_that("mock date and timestamp intervals are consistent", {
  tables <- generate_mock_omop_data()
  for (prefix in c("visit", "condition")) {
    rows <- tables[[paste0(prefix, "_occurrence")]]
    start_date <- rows[[paste0(prefix, "_start_date")]]
    end_date <- rows[[paste0(prefix, "_end_date")]]
    start_time <- rows[[paste0(prefix, "_start_datetime")]]
    end_time <- rows[[paste0(prefix, "_end_datetime")]]
    expect_true(all(end_time >= start_time), info = prefix)
    expect_equal(as.Date(start_time, tz = "UTC"), start_date, info = prefix)
    expect_equal(as.Date(end_time, tz = "UTC"), end_date, info = prefix)
  }
})
