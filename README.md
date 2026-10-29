# OMOP Database Testing Project

A small R project for learning database queries with synthetic healthcare data.
It creates a real SQLite database with seven OMOP-style tables, demonstrates
SQL and `dbplyr` queries, and calculates prevalence and drug-use summaries.

**Start with sections 1-5 below. MCP is optional.** The main instructions use
Windows and RStudio. The R scripts also use portable paths; terminal commands
for macOS/Linux are noted separately.

This is a simplified teaching dataset, not a complete OMOP CDM implementation
or a source of clinical evidence.

## What You Need

| Component | Needed for | How to get it |
| --- | --- | --- |
| R | Running the project | Install R in section 1. |
| RStudio Desktop | Recommended interface for R | Install after R in section 1. |
| Five R packages | Database access, queries, and tests | Install together in section 3. |
| SQLite | Storing the data | Included in RSQLite; the database file is created automatically. |
| Python 3.11 or newer | Optional MCP server only | Install in section 8 if you want AI-assisted queries. Tested with Python 3.12. |
| Codex CLI | Optional MCP registration using the supplied script | Install in section 8. The npm installation method also needs Node.js/npm. |
| Git | Optional way to download the repository | A repository ZIP download also works. |

Internet access is needed to download software and packages. After setup, the
R example and database work locally. Codex requires its own sign-in and network
access for AI-assisted queries.

There is no PostgreSQL service to install, no Docker setup, and no database
username or password. [RSQLite embeds the SQLite engine](https://rsqlite.r-dbi.org/)
inside the R package.

## 1. Install R and RStudio

1. Download and install R for your operating system from [CRAN](https://cran.r-project.org/). Windows users can use the [Windows installer](https://cran.r-project.org/bin/windows/base/). Choose a current supported release; the project has been tested with R 4.4.1.
2. Download and install [RStudio Desktop](https://docs.posit.co/ide/user/download.html).
3. Open RStudio. In its **Console** pane, run:

```r
R.version.string
```

You should see an R version. R is the language/runtime; RStudio is the editor
that runs it. Installing RStudio alone does not complete the R setup.

Throughout this guide, blocks marked `r` go in the **R Console**.
Blocks marked `powershell` go in **Windows PowerShell**, including RStudio's
Terminal pane when it is running PowerShell. Do not paste terminal commands
into the R Console.

## 2. Download and Open the Project

Download the complete repository as a ZIP and extract it into a folder you
can write to, or clone it with Git. Keep the whole directory structure, including
`R/`, `db/`, `tests/`, and `mcp_sqlite/`.

In RStudio, use **File > Open Project** and select `claude_test.Rproj` from
the extracted folder. Check the location in the R Console:

```r
getwd()
file.exists("run_me.R")
```

The second command must return `TRUE`. The working directory must be the
project root: the folder containing `run_me.R` and `README.md`.

If you are using R without RStudio, set the directory yourself, replacing
this example path with your actual project folder:

```r
setwd("C:/path/to/claude_test")
```

This project is run as scripts. Use the Console or the editor's **Source**
button; you do not need RStudio's Build/Install workflow.

## 3. Install the R Packages

Run this once in the **R Console**:

```r
install.packages(
  c("DBI", "RSQLite", "dbplyr", "dplyr", "testthat"),
  repos = "https://cloud.r-project.org"
)
```

R also installs the dependencies required by these packages. If R asks to
create a personal package library, accept it. On Windows, prefer binary
packages if asked whether to compile newer packages from source.

| Package | Purpose |
| --- | --- |
| `DBI` | Opens database connections and runs SQL. |
| `RSQLite` | Supplies the SQLite engine and DBI driver. |
| `dbplyr` | Translates R data manipulation into SQL. |
| `dplyr` | Provides filtering, joins, and summaries. |
| `testthat` | Runs the checks included in `run_me.R`. |

Verify the installation from the project root:

```r
source("R/config.R")
check_packages()
```

Success returns to the prompt without an error. The scripts check dependencies
but do not install packages automatically. You do not need `tidyverse` or
`devtools` for the main example; `R/means_one.R` is a separate, unused
scratch example.

## 4. Create the Database and Run the Example

In the **R Console**:

```r
source("run_me.R")
```

On the first run, the script:

1. Creates `outputs/omop.sqlite` and the seven example tables.
2. Populates an empty database with 250 reproducible mock patients and related records.
3. Prints a prevalence summary and runs the R tests.
4. Leaves the database connection in an R object called `con`, ready for your queries.

No separate SQLite installer, SQL import, or database download is needed.
The `outputs/` folder and database file are generated locally and are ignored
by Git, so their absence after downloading the repository is expected.

Check that the setup worked:

```r
DBI::dbIsValid(con)
DBI::dbListTables(con)
DBI::dbGetQuery(con, "SELECT COUNT(*) AS patients FROM patient")
```

For a fresh database, expect `TRUE`, seven table names, and a patient count
of `250`. The test report should show zero failures and zero skips.

| Table | Fresh mock dataset rows |
| --- | ---: |
| `patient` | 250 |
| `visit_occurrence` | 702 |
| `condition_occurrence` | 266 |
| `drug_exposure` | 220 |
| `procedure_occurrence` | 228 |
| `observation` | 500 |
| `measurement` | 500 |

Tables are linked by `subject_id`. Dates are stored as ISO text
(`YYYY-MM-DD`), and timestamps use UTC.

Rerunning `run_me.R` reopens or reuses the connection and preserves existing
rows and edits. It only generates mock data when all example tables are empty.

## 5. Query the Data Yourself

After running `run_me.R`, try these commands in the **same R Console**:

```r
# Inspect records and column names.
DBI::dbGetQuery(con, "SELECT * FROM patient LIMIT 10")
DBI::dbListFields(con, "condition_occurrence")

# Calculate recorded condition prevalence in this sample.
DBI::dbGetQuery(con, "
  SELECT condition_concept_id,
    MIN(condition_source_value) AS condition,
    COUNT(DISTINCT subject_id) AS patients,
    ROUND(
      100.0 * COUNT(DISTINCT subject_id) /
      (SELECT COUNT(*) FROM patient), 1
    ) AS prevalence_percent
  FROM condition_occurrence
  GROUP BY condition_concept_id
  ORDER BY prevalence_percent DESC
")

# Run a dbplyr query and bring its results back into R.
omop_patient(con) |>
  dplyr::filter(year_of_birth < 1960) |>
  dplyr::collect()
```

For the worked example selecting Black male patients with hypertension and
ranking their recorded drug exposures, run:

```r
source("sandbox_for_the_dummy.R")
hypertension_patients
drug_usage
```

This sandbox also runs `run_me.R`, so it can be used in a fresh R session.
The hypertension concept used in this example is `319835`. Drug rankings
count exposure records and distinct patients; they do not measure dose or
treatment duration.

When finished querying:

```r
close_connection(con)
```

To reconnect in the same session, run `con <- create_connection()`.
After restarting RStudio, run `source("run_me.R")` again. A restored R workspace
does not restore a live database connection.

## 6. Generate Summary CSV Files

In the **R Console**, run:

```r
source("run_analysis.R")
```

The script reads the same database and writes:

- `outputs/analysis/prevalence.csv`: overall condition prevalence.
- `outputs/analysis/demographic_prevalence.csv`: prevalence by gender and age group.
- `outputs/analysis/utilization.csv`: patient, visit, drug, and procedure summaries.

The results also remain in the R object `report`. This script creates and
seeds the database if needed, uses its own connection, and leaves an existing
`con` open. Rerunning it replaces the CSV summaries without replacing
populated database tables.

Prevalence uses distinct patients with a recorded condition divided by all
patients in the sample, including those with no conditions. Demographic
denominators include all patients in each group, including groups with zero
cases. The generated records cover 2024-2025 and age groups use birth year
at 2025. These are synthetic sample summaries, not population estimates.
The example does not calculate incidence because it lacks observation
periods and a disease-free baseline.

## 7. Run from a Terminal or Run Tests Only

The RStudio workflow above is sufficient. As an alternative, open a terminal
in the project root and run:

```powershell
Rscript run_me.R
Rscript run_analysis.R
```

On Windows, if `Rscript` is not on `PATH`, use its full installed path.
Replace `R-<version>` with the folder name on your machine:

```powershell
& 'C:/Program Files/R/R-<version>/bin/Rscript.exe' run_me.R
```

A terminal `Rscript` process creates the database file, but its R objects do
not appear in an already-open RStudio session. Use `source("run_me.R")` in
RStudio when you want to continue querying with `con` there.

To run only the R tests, use the **R Console** from the project root:

```r
testthat::test_dir("tests")
```

Tests use separate in-memory or temporary SQLite databases. They check SQL
execution, persistence, table relationships, mock dates, prevalence, and CSV
exports without changing your `outputs/omop.sqlite`.

## 8. Optional: Query Through MCP in Codex

Skip this section if you only want RStudio and SQL. Model Context Protocol
(MCP) lets a compatible AI client call tools that inspect and query the
database. This project's MCP server runs on your computer and reads the same
SQLite file.

### Install the Additional Software

Install [Python](https://www.python.org/downloads/) 3.11 or newer, including
`pip` and `venv`. Python 3.12 is the tested version. Open a new PowerShell
window after installation and check:

```powershell
python --version
python -m pip --version
```

If Windows cannot find `python`, check `py -3 --version`. You can use
`py -3 -m venv .venv-mcp` instead of the `python -m venv` command below.

You also need Codex access and the [Codex CLI](https://learn.chatgpt.com/docs/cli)
for the supplied registration script. If `codex --version` already works,
skip its installation. For the npm installation method, first install
[Node.js LTS](https://nodejs.org/en/download), which includes npm, then run
these **PowerShell** commands:

```powershell
node --version
npm.cmd --version
npm.cmd install -g @openai/codex
codex --version
```

Run `codex` once and complete its sign-in flow if you have not already done so.
Node.js is only needed for this npm installation method; the SQLite MCP
server itself runs in Python. The standalone CLI installation options are
in the official Codex guide linked above.

### Create the Python Environment

Finish section 4 first so `outputs/omop.sqlite` exists. In **PowerShell**,
switch to your project directory, replacing the example path:

```powershell
Set-Location 'C:\path\to\claude_test'
python -m venv .venv-mcp
.\.venv-mcp\Scripts\python.exe -m pip install -r mcp_sqlite/requirements.txt
```

This creates an isolated Python environment inside the project and installs
the pinned MCP SDK plus its dependencies. It is separate from the R package
library. No environment activation is needed because the commands use its
Python executable directly.

### Test and Register the Server

Still in **PowerShell** at the project root:

```powershell
.\.venv-mcp\Scripts\python.exe -m unittest discover -s mcp_sqlite -p test_server.py -v
.\.venv-mcp\Scripts\python.exe mcp_sqlite/check_connection.py
.\mcp_sqlite\register.ps1
codex mcp get omop-sqlite
```

The first command tests the connector using temporary databases. The second
uses the actual MCP protocol against your existing database: expect
`list_tables`, `describe_table`, and `query`, seven tables, and 250 patients
if you have not changed the sample. Registration should report
`enabled: true` and `transport: stdio`.

The registration script uses `codex mcp add`. It writes the server command
and absolute project paths to your user-level Codex configuration, normally
`~/.codex/config.toml`; it is not stored in the repository. Rerun registration
if you move the project or recreate the Python environment at another path.

In the app's **Settings > MCP servers**, restart/reload the servers after
registration. Start a new session if the tools are not yet visible. You can
then ask:

> Use omop-sqlite to list the tables.

> Use omop-sqlite to find the most-used drugs among Black male patients with hypertension.

Local stdio configuration requires a client running on the computer that
can access this database; adding it does not make the file accessible to a
separate web/cloud client. See the [official MCP configuration guide](https://learn.chatgpt.com/docs/extend/mcp?surface=cli).

### Tools and Limits

| Tool | Purpose |
| --- | --- |
| `list_tables()` | List user tables and views. |
| `describe_table(name)` | Inspect columns, primary keys, and foreign keys. |
| `query(sql, params, max_rows)` | Execute a read-only SELECT or CTE; bind values with `?` placeholders. |

Queries return column names and row arrays. The default limit is 100 rows,
with a maximum of 500 rows and approximately 100 KB of row data. Check
`truncated` and narrow or page the SQL when needed. Queries have an
approximately five-second execution limit.

The server opens the file read-only for each call. Committed changes from
RStudio appear on subsequent queries, and RStudio need not stay open.
Writes, attaching other databases, arbitrary PRAGMAs, and extension loading
are blocked. Query results are passed to the AI client; the server does not
upload a separate database copy.

To remove the connection while keeping the database and source files:

```powershell
codex mcp remove omop-sqlite
```

### macOS/Linux MCP Commands

The R workflow is the same. After installing Python 3.11+ and Codex, use the
following **shell** commands from the project root instead of the Windows
environment and registration commands:

```bash
python3 -m venv .venv-mcp
.venv-mcp/bin/python -m pip install -r mcp_sqlite/requirements.txt
.venv-mcp/bin/python -m unittest discover -s mcp_sqlite -p test_server.py -v
.venv-mcp/bin/python mcp_sqlite/check_connection.py
codex mcp add omop-sqlite -- "$(pwd)/.venv-mcp/bin/python" "$(pwd)/mcp_sqlite/server.py" --db "$(pwd)/outputs/omop.sqlite"
codex mcp get omop-sqlite
```

Windows is the tested platform for this project. A Linux distribution may
provide `venv` as a separate OS package; install it if `python3 -m venv`
reports it missing.

## Troubleshooting

| Symptom | What to check |
| --- | --- |
| `cannot open file 'R/config.R'` or `run_me.R` | Open `claude_test.Rproj` or change to the project root. Verify `file.exists("run_me.R")` in R. |
| `there is no package called ...` | Repeat section 3 in the same R installation used by RStudio. Inspect `R.version.string` and `.libPaths()` if multiple R versions are installed. |
| Package installation asks for a compiler on Windows | Use available binary packages. If source compilation is necessary, follow the package's build requirements for your R version. |
| `object 'con' not found` or invalid connection | Run `source("run_me.R")` in the current RStudio console, even if you already ran it in a terminal. |
| Database file missing in a fresh download | This is expected. Run section 4; the database is generated, not checked into Git. |
| Permission denied creating the database | Extract the project into a writable folder in your user account, then reopen its R project. |
| `database is locked` | Finish open write transactions in other database clients and retry. |
| `Rscript`, `python`, `npm`, or `codex` not recognized | Install the relevant optional/required software, reopen the terminal, and check its executable path. RStudio does not require `Rscript` on `PATH`. |
| `No module named mcp` | Run pip with `.venv-mcp/Scripts/python.exe` as shown above; installing into a different Python does not configure this environment. |
| MCP server says database not found | Create it with `source("run_me.R")`; rerun registration if the project moved. |
| MCP registered but tools are absent | Confirm `codex mcp get omop-sqlite`, restart MCP servers, and try a new local session. |
| MCP returns `not authorized` for a write | Access is intentionally read-only. Use the R/DBI connection for edits. |

If Windows PowerShell blocks `register.ps1` or the npm-provided `codex.ps1`,
you can use the npm command shim and register directly from the project root:

```powershell
codex.cmd --version
codex.cmd mcp add omop-sqlite -- "$PWD\.venv-mcp\Scripts\python.exe" "$PWD\mcp_sqlite\server.py" --db "$PWD\outputs\omop.sqlite"
codex.cmd mcp get omop-sqlite
```

Warnings such as an R package being built under a newer R release are distinct
from test failures. Check that commands finish successfully and the tests
report no failures; update/reinstall the affected package if necessary.

## Files and Reproducibility

| Path | Purpose |
| --- | --- |
| `claude_test.Rproj` | Opens the project in RStudio. |
| `run_me.R` | Initializes the database, runs tests, and leaves `con` open. |
| `sandbox_for_the_dummy.R` | Editable SQL and hypertension/drug-use example. |
| `run_analysis.R` | Produces summary tables and CSV exports. |
| `R/config.R` | Database location and R package checks. |
| `R/database_setup.R` | Table definitions, mock generation, and initialization. |
| `R/omop_schema.R` | Queryable dbplyr table wrappers. |
| `R/analytics.R` | Prevalence and utilization calculations. |
| `db/connection.R` | SQLite connection helpers. |
| `tests/` | R tests using isolated databases. |
| `mcp_sqlite/` | Optional Python MCP server, tests, and registration script. |
| `outputs/` | Generated database and summary files, ignored by Git. |
| `.venv-mcp/` | Generated Python environment, ignored by Git. |

The default mock seed is `20260318`. To deliberately replace all existing
example rows with freshly generated data, run this in R after `run_me.R`:

```r
populate_mock_data(con, seed = 20260318, n_patients = 250, overwrite = TRUE)
```

This deletes and replaces the example rows, including your edits; ordinary
runs of `run_me.R` do not do this. Keep a separate copy of the SQLite file
if you want to preserve edits before regenerating.

R dependencies are listed in `DESCRIPTION` but are not version-locked.
The MCP SDK version is pinned in `mcp_sqlite/requirements.txt`; its transitive
dependencies are resolved during installation. `.Renviron` and `.env` files
are ignored by Git and are not needed for this SQLite example.

