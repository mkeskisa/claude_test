# Database setup functions
# Create and populate persistent SQLite tables.

create_database <- function(dbname = DB_PATH) {
  con <- create_connection(dbname)
  on.exit(close_connection(con), add = TRUE)
  invisible(dbname)
}

omop_table_specs <- function() {
  list(
    patient = list(
      patient_id = integer(),
      subject_id = integer(),
      gender_concept_id = integer(),
      year_of_birth = integer(),
      month_of_birth = integer(),
      day_of_birth = integer(),
      gender = character(),
      race_concept_id = integer(),
      ethnicity_concept_id = integer(),
      race = character(),
      ethnicity = character(),
      race_source_value = character(),
      ethnicity_source_value = character()
    ),
    visit_occurrence = list(
      visit_occurrence_id = integer(),
      subject_id = integer(),
      visit_start_date = as.Date(character()),
      visit_start_datetime = as.POSIXct(character(), tz = "UTC"),
      visit_end_date = as.Date(character()),
      visit_end_datetime = as.POSIXct(character(), tz = "UTC"),
      visit_source_value = character()
    ),
    condition_occurrence = list(
      condition_occurrence_id = integer(),
      subject_id = integer(),
      condition_concept_id = integer(),
      condition_start_date = as.Date(character()),
      condition_start_datetime = as.POSIXct(character(), tz = "UTC"),
      condition_end_date = as.Date(character()),
      condition_end_datetime = as.POSIXct(character(), tz = "UTC"),
      condition_type_concept_id = integer(),
      condition_source_value = character()
    ),
    drug_exposure = list(
      drug_exposure_id = integer(),
      subject_id = integer(),
      drug_concept_id = integer(),
      drug_source_value = character(),
      drug_source_exposure = character()
    ),
    procedure_occurrence = list(
      procedure_occurrence_id = integer(),
      subject_id = integer(),
      procedure_concept_id = integer(),
      procedure_date = as.Date(character()),
      procedure_datetime = as.POSIXct(character(), tz = "UTC"),
      procedure_source_value = character()
    ),
    observation = list(
      observation_id = integer(),
      subject_id = integer(),
      observation_concept_id = integer(),
      observation_date = as.Date(character()),
      observation_datetime = as.POSIXct(character(), tz = "UTC"),
      observation_source_value = character()
    ),
    measurement = list(
      measurement_id = integer(),
      subject_id = integer(),
      measurement_concept_id = integer(),
      measurement_date = as.Date(character()),
      measurement_datetime = as.POSIXct(character(), tz = "UTC"),
      measurement_source_value = character()
    )
  )

}

create_tables <- function(con = create_connection()) {
  if (missing(con)) {
    on.exit(close_connection(con), add = TRUE)
  }
  specs <- omop_table_specs()
  DBI::dbWithTransaction(con, {
    for (table_name in names(specs)) {
      columns <- specs[[table_name]]
      types <- vapply(columns, function(x) if (is.integer(x)) "INTEGER" else "TEXT", character(1))
      types[[paste0(table_name, "_id")]] <- "INTEGER PRIMARY KEY"
      types[["subject_id"]] <- if (table_name == "patient") {
        "INTEGER NOT NULL UNIQUE"
      } else {
        "INTEGER NOT NULL REFERENCES patient(subject_id)"
      }
      fields <- paste(DBI::dbQuoteIdentifier(con, names(types)), types)
      sql <- sprintf("CREATE TABLE IF NOT EXISTS %s (%s)",
        DBI::dbQuoteIdentifier(con, table_name), paste(fields, collapse = ", "))
      DBI::dbExecute(con, sql)
      if (!all(names(columns) %in% DBI::dbListFields(con, table_name))) {
        stop(sprintf("Existing table '%s' has an incompatible schema.", table_name), call. = FALSE)
      }
    }
  })

  invisible(TRUE)
}

drop_database <- function(con) {
  # Explicitly remove only the example tables, children before their parent.
  DBI::dbWithTransaction(con, {
    for (table_name in rev(names(omop_table_specs()))) {
      if (table_exists(con, table_name)) DBI::dbRemoveTable(con, table_name)
    }
  })
  invisible(TRUE)
}

generate_mock_omop_data <- function(seed = 20260318, n_patients = 250) {
  set.seed(seed)

  patient_ids <- seq_len(n_patients)
  subject_ids <- sample(seq(100000L, 999999L), n_patients)
  birth_year <- sample(1940:2015, n_patients, replace = TRUE)
  birth_month <- sample(1:12, n_patients, replace = TRUE)
  birth_day <- sample(1:28, n_patients, replace = TRUE)
  gender <- sample(c("Male", "Female"), n_patients, replace = TRUE, prob = c(0.47, 0.53))
  race <- sample(
    c("White", "Black", "Asian", "Hispanic", "Other"),
    n_patients,
    replace = TRUE,
    prob = c(0.52, 0.16, 0.11, 0.14, 0.07)
  )
  ethnicity <- ifelse(race == "Hispanic", "Hispanic or Latino", "Not Hispanic or Latino")

  patient <- data.frame(
    patient_id = patient_ids,
    subject_id = subject_ids,
    gender_concept_id = ifelse(gender == "Male", 8507L, 8532L),
    year_of_birth = birth_year,
    month_of_birth = birth_month,
    day_of_birth = birth_day,
    gender = gender,
    race_concept_id = c(8527L, 8516L, 8515L, 38003563L, 0L)[match(race, c("White", "Black", "Asian", "Hispanic", "Other"))],
    ethnicity_concept_id = ifelse(ethnicity == "Hispanic or Latino", 38003563L, 38003564L),
    race = race,
    ethnicity = ethnicity,
    race_source_value = race,
    ethnicity_source_value = ethnicity,
    stringsAsFactors = FALSE
  )

  concept_catalog <- data.frame(
    condition_concept_id = c(201826L, 319835L, 4329847L, 316139L, 315296L),
    condition_name = c("Type 2 diabetes", "Hypertension", "Asthma", "Depressive disorder", "Ischemic heart disease"),
    base_prevalence = c(0.12, 0.28, 0.10, 0.14, 0.08),
    stringsAsFactors = FALSE
  )

  observation_dates <- as.Date("2024-01-01") + sample(0:730, n_patients, replace = TRUE)
  age_2025 <- 2025L - patient$year_of_birth
  bmi_values <- pmax(rnorm(n_patients, mean = 27, sd = 5), 16)
  smoker_values <- sample(c("Never", "Former", "Current"), n_patients, replace = TRUE, prob = c(0.58, 0.24, 0.18))

  visit_counts <- pmax(1L, rpois(n_patients, lambda = 2.6))
  visit_patient_index <- rep(seq_len(n_patients), visit_counts)
  n_visits <- length(visit_patient_index)
  visit_start_date <- as.Date("2024-01-01") + sample(0:730, n_visits, replace = TRUE)
  visit_end_date <- visit_start_date + sample(0:4, n_visits, replace = TRUE)
  visit_hour <- sample(7:18, n_visits, replace = TRUE)
  visit_end_datetime <- as.POSIXct(visit_end_date, tz = "UTC") +
    (visit_hour + sample(1:6, n_visits, replace = TRUE)) * 3600
  visit_occurrence <- data.frame(
    visit_occurrence_id = seq_len(n_visits),
    subject_id = patient$subject_id[visit_patient_index],
    visit_start_date = visit_start_date,
    visit_start_datetime = as.POSIXct(visit_start_date) + visit_hour * 3600,
    visit_end_date = as.Date(visit_end_datetime, tz = "UTC"),
    visit_end_datetime = visit_end_datetime,
    visit_source_value = sample(c("Outpatient", "Inpatient", "Emergency"), n_visits, replace = TRUE, prob = c(0.72, 0.14, 0.14)),
    stringsAsFactors = FALSE
  )

  condition_rows <- vector("list", length = nrow(concept_catalog))
  next_condition_id <- 1L
  for (i in seq_len(nrow(concept_catalog))) {
    concept <- concept_catalog[i, ]
    age_adjustment <- ifelse(age_2025 >= 65, 0.09, ifelse(age_2025 >= 45, 0.04, 0))
    concept_adjustment <- switch(
      as.character(concept$condition_concept_id),
      "201826" = ifelse(bmi_values >= 30, 0.12, 0.02),
      "319835" = ifelse(age_2025 >= 55, 0.10, 0.01),
      "4329847" = ifelse(smoker_values == "Current", 0.10, 0.02),
      "316139" = ifelse(smoker_values != "Never", 0.03, 0.01),
      "315296" = ifelse(age_2025 >= 60, 0.08, 0.01),
      0
    )
    gender_adjustment <- ifelse(concept$condition_concept_id == 315296L & patient$gender == "Male", 0.03, 0)
    probability <- pmin(concept$base_prevalence + age_adjustment + concept_adjustment + gender_adjustment, 0.85)
    has_condition <- stats::runif(n_patients) < probability
    patient_idx <- which(has_condition)

    if (length(patient_idx) == 0) {
      next
    }

    start_date <- as.Date("2024-01-01") + sample(0:730, length(patient_idx), replace = TRUE)
    start_datetime <- as.POSIXct(start_date, tz = "UTC") +
      sample(8:17, length(patient_idx), replace = TRUE) * 3600
    end_date <- start_date + sample(0:60, length(patient_idx), replace = TRUE)
    end_datetime <- pmax(
      start_datetime,
      as.POSIXct(end_date, tz = "UTC") +
        sample(8:17, length(patient_idx), replace = TRUE) * 3600
    )
    condition_rows[[i]] <- data.frame(
      condition_occurrence_id = seq.int(next_condition_id, length.out = length(patient_idx)),
      subject_id = patient$subject_id[patient_idx],
      condition_concept_id = rep(concept$condition_concept_id, length(patient_idx)),
      condition_start_date = start_date,
      condition_start_datetime = start_datetime,
      condition_end_date = end_date,
      condition_end_datetime = end_datetime,
      condition_type_concept_id = sample(c(32020L, 32817L, 44786627L), length(patient_idx), replace = TRUE),
      condition_source_value = rep(concept$condition_name, length(patient_idx)),
      stringsAsFactors = FALSE
    )
    next_condition_id <- next_condition_id + length(patient_idx)
  }
  condition_occurrence <- dplyr::bind_rows(condition_rows)

  drug_map <- data.frame(
    condition_concept_id = c(201826L, 319835L, 4329847L, 316139L, 315296L),
    drug_concept_id = c(1503297L, 1310149L, 19019073L, 19040817L, 19018935L),
    drug_source_value = c("Metformin", "Lisinopril", "Albuterol", "Sertraline", "Atorvastatin"),
    stringsAsFactors = FALSE
  )
  condition_with_drugs <- merge(condition_occurrence, drug_map, by = "condition_concept_id", all.x = TRUE, sort = FALSE)
  selected_drugs <- condition_with_drugs[stats::runif(nrow(condition_with_drugs)) < 0.82, ]
  drug_exposure <- data.frame(
    drug_exposure_id = seq_len(nrow(selected_drugs)),
    subject_id = selected_drugs$subject_id,
    drug_concept_id = selected_drugs$drug_concept_id,
    drug_source_value = selected_drugs$drug_source_value,
    drug_source_exposure = paste(selected_drugs$drug_source_value, sample(c("5 mg", "10 mg", "20 mg", "500 mg"), nrow(selected_drugs), replace = TRUE)),
    stringsAsFactors = FALSE
  )

  procedure_counts <- pmax(0L, rpois(n_patients, lambda = 0.9))
  procedure_patient_index <- rep(seq_len(n_patients), procedure_counts)
  n_procedures <- length(procedure_patient_index)
  procedure_date <- as.Date("2024-01-01") + sample(0:730, n_procedures, replace = TRUE)
  procedure_occurrence <- data.frame(
    procedure_occurrence_id = seq_len(n_procedures),
    subject_id = patient$subject_id[procedure_patient_index],
    procedure_concept_id = sample(c(2213283L, 2000001L, 4301351L, 2211357L), n_procedures, replace = TRUE),
    procedure_date = procedure_date,
    procedure_datetime = as.POSIXct(procedure_date) + sample(7:17, n_procedures, replace = TRUE) * 3600,
    procedure_source_value = sample(c("HbA1c test", "Chest X-ray", "Lipid panel", "Pulmonary function test"), n_procedures, replace = TRUE),
    stringsAsFactors = FALSE
  )

  observation <- data.frame(
    observation_id = seq_len(2L * n_patients),
    subject_id = rep(patient$subject_id, each = 2L),
    observation_concept_id = rep(c(3027018L, 4076627L), times = n_patients),
    observation_date = rep(observation_dates, each = 2L),
    observation_datetime = as.POSIXct(rep(observation_dates, each = 2L)) + rep(c(9L, 10L), times = n_patients) * 3600,
    observation_source_value = c(rbind(paste("BMI", round(bmi_values, 1)), paste("Smoking status:", smoker_values))),
    stringsAsFactors = FALSE
  )

  measurement <- data.frame(
    measurement_id = seq_len(2L * n_patients),
    subject_id = rep(patient$subject_id, each = 2L),
    measurement_concept_id = rep(c(3004249L, 3004410L), times = n_patients),
    measurement_date = rep(observation_dates, each = 2L),
    measurement_datetime = as.POSIXct(rep(observation_dates, each = 2L)) + rep(c(8L, 8L), times = n_patients) * 3600,
    measurement_source_value = c(rbind(
      paste0(round(rnorm(n_patients, mean = 127, sd = 15)), " mmHg"),
      paste0(round(pmax(rnorm(n_patients, mean = 7.2, sd = 1.4), 4.5), 1), " %")
    )),
    stringsAsFactors = FALSE
  )

  list(
    patient = patient,
    visit_occurrence = visit_occurrence,
    condition_occurrence = condition_occurrence,
    drug_exposure = drug_exposure,
    procedure_occurrence = procedure_occurrence,
    observation = observation,
    measurement = measurement
  )
}

sqlite_rows <- function(rows) {
  # ISO dates remain readable and usable by SQLite date()/datetime() functions.
  rows[] <- lapply(rows, function(x) {
    if (inherits(x, "POSIXt")) {
      format(x, "%Y-%m-%d %H:%M:%S", tz = "UTC")
    } else if (inherits(x, "Date")) {
      as.character(x)
    } else {
      x
    }
  })
  rows
}

example_table_counts <- function(con) {
  vapply(names(omop_table_specs()), function(table_name) {
    sql <- paste("SELECT COUNT(*) AS n FROM", DBI::dbQuoteIdentifier(con, table_name))
    as.numeric(DBI::dbGetQuery(con, sql)$n)
  }, numeric(1))
}

populate_mock_data <- function(con, seed = 20260318, n_patients = 250, overwrite = FALSE) {
  create_tables(con)
  table_data <- generate_mock_omop_data(seed = seed, n_patients = n_patients)

  DBI::dbWithTransaction(con, {
    if (any(example_table_counts(con) > 0) && !isTRUE(overwrite)) {
      stop("Example tables already contain data. Use overwrite = TRUE to replace it explicitly.", call. = FALSE)
    }
    if (isTRUE(overwrite)) {
      for (table_name in rev(names(table_data))) {
        DBI::dbExecute(con, paste("DELETE FROM", DBI::dbQuoteIdentifier(con, table_name)))
      }
    }
    for (table_name in names(table_data)) {
      DBI::dbAppendTable(con, table_name, sqlite_rows(table_data[[table_name]]))
    }
  })

  invisible(con)
}

initialize_mock_database <- function(con) {
  create_tables(con)
  counts <- example_table_counts(con)
  if (all(counts == 0)) {
    populate_mock_data(con)
  } else if (counts[["patient"]] == 0) {
    stop("Existing example records have no patients; refusing to replace them automatically.", call. = FALSE)
  }
  invisible(con)
}
