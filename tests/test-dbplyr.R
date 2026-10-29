# dbplyr functionality tests
# Test basic dbplyr operations

test_that("dbplyr basic operations work", {
  con <- local_test_db_connection()
  on.exit(close_connection(con), add = TRUE)

  expect_true(table_exists(con, "patient"))

  query <- omop_patient(con)
  expect_s3_class(query, "tbl_lazy")

  result <- dplyr::select(query, patient_id, subject_id)
  expect_s3_class(result, "tbl_lazy")

  filtered <- dplyr::filter(query, subject_id > 0)
  expect_s3_class(filtered, "tbl_lazy")

  grouped <- dplyr::group_by(query, subject_id)
  expect_s3_class(grouped, "tbl_lazy")
  expect_equal(dplyr::group_vars(grouped), "subject_id")

  joined <- dplyr::left_join(query, query, by = "subject_id")
  expect_s3_class(joined, "tbl_lazy")
})

test_that("dbplyr SQL generation works", {
  con <- local_test_db_connection()
  on.exit(close_connection(con), add = TRUE)

  query <- omop_patient(con)
  sql <- dbplyr::sql_render(dplyr::select(query, patient_id, subject_id))
  expect_true(is.character(sql))
  expect_true(nchar(sql) > 0)
  expect_match(sql, "SELECT", ignore.case = TRUE)
})
