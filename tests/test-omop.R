# OMOP data model query tests
# Test OMOP CDM schema queries

test_that("OMOP patient queries work", {
  con <- local_test_db_connection()
  on.exit(close_connection(con), add = TRUE)

  patient <- omop_patient(con)
  count <- dplyr::count(patient)
  expect_s3_class(count, "tbl_lazy")

  patients <- dplyr::filter(patient, subject_id > 0)
  expect_s3_class(patients, "tbl_lazy")
})

test_that("OMOP condition occurrence queries work", {
  con <- local_test_db_connection()
  on.exit(close_connection(con), add = TRUE)

  condition <- omop_condition_occurrence(con)
  condition_counts <- condition |>
    dplyr::group_by(condition_concept_id) |>
    dplyr::summarize(count = dplyr::n())

  expect_s3_class(condition_counts, "tbl_lazy")
})

test_that("OMOP drug exposure queries work", {
  con <- local_test_db_connection()
  on.exit(close_connection(con), add = TRUE)

  drug <- omop_drug_exposure(con)
  drug_patient <- dplyr::left_join(drug, omop_patient(con), by = "subject_id")
  expect_s3_class(drug_patient, "tbl_lazy")
})
