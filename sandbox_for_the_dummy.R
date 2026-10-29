# Run from the open R project: source("sandbox_for_the_dummy.R")
# This creates/reopens the SQLite database and leaves con open for more queries.
source("run_me.R", local = TRUE)

# Basic DBI commands: list the tables and inspect the first ten patients.
table_names <- DBI::dbListTables(con)
print(table_names)

patient_preview <- DBI::dbGetQuery(con, "SELECT * FROM patient LIMIT 10")
print(patient_preview)

# Select every Black male patient with a recorded hypertension diagnosis.
# EXISTS avoids duplicating patients who have multiple diagnosis records.
cohort_sql <- "
  SELECT p.*
  FROM patient AS p
  WHERE p.race = ?
    AND p.gender = ?
    AND EXISTS (
      SELECT 1
      FROM condition_occurrence AS c
      WHERE c.subject_id = p.subject_id
        AND c.condition_concept_id = ?
    )
  ORDER BY p.patient_id
"
cohort_params <- list("Black", "Male", 319835L)

hypertension_patients <- DBI::dbGetQuery(
  con, cohort_sql, params = cohort_params
)
cat("\nBlack male patients with recorded hypertension:", nrow(hypertension_patients), "\n")
print(hypertension_patients)

# Rank ALL drugs recorded for this cohort, regardless of treatment indication.
# "Most used" means most drug_exposure rows, not dose or duration of treatment.
# patient_count counts each person once per drug; cohort_percent includes
# patients with hypertension who have no recorded drug exposures.
drug_usage_sql <- paste0("
  WITH cohort AS (
", cohort_sql, "
  )
  SELECT
    d.drug_concept_id,
    MIN(d.drug_source_value) AS drug_name,
    COUNT(*) AS exposure_count,
    COUNT(DISTINCT d.subject_id) AS patient_count,
    ROUND(
      100.0 * COUNT(DISTINCT d.subject_id) /
      NULLIF((SELECT COUNT(*) FROM cohort), 0), 1
    ) AS cohort_percent
  FROM drug_exposure AS d
  INNER JOIN cohort AS p ON p.subject_id = d.subject_id
  GROUP BY d.drug_concept_id
  ORDER BY exposure_count DESC, patient_count DESC, drug_name
")

drug_usage <- DBI::dbGetQuery(con, drug_usage_sql, params = cohort_params)
cat("\nDrugs ranked by recorded exposure count in this synthetic cohort:\n")
print(drug_usage)

if (nrow(hypertension_patients) == 0L) {
  cat("No patients match the selected criteria.\n")
} else if (nrow(drug_usage) == 0L) {
  cat("These patients have no recorded drug exposures.\n")
}

# Results remain available as hypertension_patients and drug_usage in RStudio.
# When finished with all your queries, run: close_connection(con)
