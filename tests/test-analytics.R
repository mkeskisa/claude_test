analytics_fixture <- function() {
  con <- local_test_db_connection()
  DBI::dbAppendTable(con, "patient", data.frame(
    patient_id = 1:4,
    subject_id = 1:4,
    gender = c("Female", "Male", "Female", "Male"),
    year_of_birth = c(2025L, 1985L, 1945L, 1986L)
  ))
  DBI::dbAppendTable(con, "condition_occurrence", data.frame(
    condition_occurrence_id = 1:4,
    subject_id = c(1L, 1L, 2L, 2L),
    condition_concept_id = c(10L, 10L, 10L, 20L),
    condition_source_value = c("Condition A", "Alternate label", "Condition A", "Condition B")
  ))
  con
}

test_that("prevalence counts patients once per concept and includes healthy patients", {
  con <- analytics_fixture()
  on.exit(close_connection(con), add = TRUE)
  result <- calculate_condition_prevalence(con)
  expect_equal(nrow(result), 2L)
  expect_equal(result$patient_count[match(c(10L, 20L), result$condition_concept_id)], c(2L, 1L))
  expect_equal(result$total_patients, c(4L, 4L))
  expect_equal(result$prevalence[match(c(10L, 20L), result$condition_concept_id)], c(0.5, 0.25))
})

test_that("demographic prevalence includes zero-case groups and age zero", {
  con <- analytics_fixture()
  on.exit(close_connection(con), add = TRUE)
  result <- calculate_demographic_prevalence(con)
  expect_equal(nrow(result), 6L)
  expect_false(anyNA(result$age_group))
  older <- result[result$gender == "Female" & result$age_group == "65+", ]
  expect_equal(older$patient_count, c(0L, 0L))
  expect_equal(older$group_total, c(1L, 1L))
  expect_equal(older$prevalence, c(0, 0))
  middle <- result[result$gender == "Male" & result$age_group == "35-49", ]
  expect_equal(middle$group_total, c(2L, 2L))
  expect_equal(middle$prevalence, c(0.5, 0.5))
})

test_that("CSV exports preserve all summary columns and calculated values", {
  con <- local_test_db_connection()
  on.exit(close_connection(con), add = TRUE)
  populate_mock_data(con)
  report <- build_mock_analysis_report(con)
  output_dir <- tempfile("omop-report-")
  on.exit(unlink(output_dir, recursive = TRUE), add = TRUE)

  paths <- export_mock_analysis_report(report, output_dir)
  expect_named(paths, c("prevalence", "demographic_prevalence", "utilization"))
  expect_true(all(file.exists(paths)))
  for (name in names(report)) {
    actual <- utils::read.csv(paths[[name]], stringsAsFactors = FALSE)
    expected <- as.data.frame(report[[name]])
    expected[] <- lapply(expected, function(x) if (is.factor(x)) as.character(x) else x)
    expect_equal(actual, expected, tolerance = 1e-12, info = name)
  }
})
