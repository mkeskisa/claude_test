# Analytics helpers for the mock OMOP dataset.

condition_labels <- function(condition) {
  condition |>
    dplyr::select(condition_concept_id, condition_source_value) |>
    dplyr::distinct(condition_concept_id, .keep_all = TRUE)
}

calculate_condition_prevalence <- function(con) {
  patient <- get_table_data(con, "patient")
  condition <- get_table_data(con, "condition_occurrence")

  counts <- condition |>
    dplyr::semi_join(patient, by = "subject_id") |>
    dplyr::distinct(subject_id, condition_concept_id) |>
    dplyr::count(condition_concept_id, name = "patient_count")

  condition_labels(condition) |>
    dplyr::left_join(counts, by = "condition_concept_id") |>
    dplyr::mutate(
      patient_count = dplyr::coalesce(patient_count, 0L),
      total_patients = dplyr::n_distinct(patient$subject_id),
      prevalence = ifelse(total_patients > 0L, patient_count / total_patients, NA_real_)
    ) |>
    dplyr::arrange(dplyr::desc(prevalence), condition_source_value)
}

calculate_demographic_prevalence <- function(con, reference_year = 2025L) {
  patient <- get_table_data(con, "patient") |>
    dplyr::distinct(subject_id, .keep_all = TRUE) |>
    dplyr::mutate(
      age_group = cut(
        reference_year - year_of_birth,
        breaks = c(0, 17, 34, 49, 64, Inf),
        labels = c("0-17", "18-34", "35-49", "50-64", "65+"),
        right = TRUE,
        include.lowest = TRUE
      )
    )

  condition <- get_table_data(con, "condition_occurrence")
  cases <- condition |>
    dplyr::distinct(subject_id, condition_concept_id)
  groups <- patient |>
    dplyr::count(gender, age_group, name = "group_total")

  counts <- patient |>
    dplyr::inner_join(cases, by = "subject_id") |>
    dplyr::count(gender, age_group, condition_concept_id, name = "patient_count")

  dplyr::cross_join(condition_labels(condition), groups) |>
    dplyr::left_join(
      counts,
      by = c("condition_concept_id", "gender", "age_group")
    ) |>
    dplyr::mutate(
      patient_count = dplyr::coalesce(patient_count, 0L),
      prevalence = patient_count / group_total
    ) |>
    dplyr::arrange(condition_source_value, gender, age_group)
}

calculate_utilization_summary <- function(con) {
  patient <- get_table_data(con, "patient")
  visits <- get_table_data(con, "visit_occurrence")
  drugs <- get_table_data(con, "drug_exposure")
  procedures <- get_table_data(con, "procedure_occurrence")

  data.frame(
    metric = c("patients", "visits", "drugs", "procedures", "mean_visits_per_patient"),
    value = c(
      nrow(patient),
      nrow(visits),
      nrow(drugs),
      nrow(procedures),
      round(nrow(visits) / nrow(patient), 2)
    ),
    stringsAsFactors = FALSE
  )
}

build_mock_analysis_report <- function(con) {
  list(
    prevalence = calculate_condition_prevalence(con),
    demographic_prevalence = calculate_demographic_prevalence(con),
    utilization = calculate_utilization_summary(con)
  )
}

export_mock_analysis_report <- function(report, output_dir = file.path("outputs", "analysis")) {
  if (!dir.exists(output_dir) && !dir.create(output_dir, recursive = TRUE)) {
    stop("Could not create analysis output directory.", call. = FALSE)
  }

  paths <- file.path(output_dir, paste0(names(report), ".csv"))
  names(paths) <- names(report)
  for (name in names(report)) {
    utils::write.csv(report[[name]], paths[[name]], row.names = FALSE, fileEncoding = "UTF-8")
  }
  invisible(paths)
}
