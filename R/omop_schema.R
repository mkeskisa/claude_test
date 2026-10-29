# OMOP CDM Schema Definitions
# Minimal OMOP-style dbplyr wrappers for the integration tests.

omop_table <- function(con, table_name) {
  if (!table_exists(con, table_name)) {
    stop(sprintf("Table '%s' is not available on this connection.", table_name), call. = FALSE)
  }

  dplyr::tbl(con, table_name)
}

omop_patient <- function(con) {
  omop_table(con, "patient") |>
    dplyr::select(
      patient_id,
      subject_id,
      gender_concept_id,
      year_of_birth,
      month_of_birth,
      day_of_birth,
      gender,
      race_concept_id,
      ethnicity_concept_id,
      race,
      ethnicity,
      race_source_value,
      ethnicity_source_value
    )
}

omop_visit_occurrence <- function(con) {
  omop_table(con, "visit_occurrence") |>
    dplyr::select(
      visit_occurrence_id,
      subject_id,
      visit_start_date,
      visit_start_datetime,
      visit_end_date,
      visit_end_datetime,
      visit_source_value
    )
}

omop_condition_occurrence <- function(con) {
  omop_table(con, "condition_occurrence") |>
    dplyr::select(
      condition_occurrence_id,
      subject_id,
      condition_concept_id,
      condition_start_date,
      condition_start_datetime,
      condition_end_date,
      condition_end_datetime,
      condition_type_concept_id,
      condition_source_value
    )
}

omop_drug_exposure <- function(con) {
  omop_table(con, "drug_exposure") |>
    dplyr::select(
      drug_exposure_id,
      subject_id,
      drug_concept_id,
      drug_source_value,
      drug_source_exposure
    )
}

omop_procedure_occurrence <- function(con) {
  omop_table(con, "procedure_occurrence") |>
    dplyr::select(
      procedure_occurrence_id,
      subject_id,
      procedure_concept_id,
      procedure_date,
      procedure_datetime,
      procedure_source_value
    )
}

omop_observation <- function(con) {
  omop_table(con, "observation") |>
    dplyr::select(
      observation_id,
      subject_id,
      observation_concept_id,
      observation_date,
      observation_datetime,
      observation_source_value
    )
}

omop_measurement <- function(con) {
  omop_table(con, "measurement") |>
    dplyr::select(
      measurement_id,
      subject_id,
      measurement_concept_id,
      measurement_date,
      measurement_datetime,
      measurement_source_value
    )
}
