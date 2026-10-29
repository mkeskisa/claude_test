# OMOP Clinical Data Example

Learn SQL and database analysis with 250 synthetic patients in a local SQLite
database. Use RStudio for SQL, or chat with Codex as a read-only data analyst.
This is a simplified OMOP-style teaching dataset, not clinical evidence.

## 1. Install and Run

1. Install [R](https://cran.r-project.org/) and then [RStudio Desktop](https://docs.posit.co/ide/user/download.html).
2. Download or clone [this repository](https://github.com/mkeskisa/claude_test), extract it into a writable folder, and open `claude_test.Rproj` in RStudio.
3. Run the following in the **R Console**, not the Terminal:

```r
# Install once. Accept a personal library if prompted.
install.packages(
  c("DBI", "RSQLite", "dbplyr", "dplyr", "testthat"),
  repos = "https://cloud.r-project.org"
)

# Run whenever you start a new R session.
source("run_me.R")
DBI::dbGetQuery(con, "SELECT COUNT(*) AS patients FROM patient")
```

Expect **250 patients** and passing tests. The script creates
`outputs/omop.sqlite`, populates seven tables, and leaves `con` open for queries.
Rerunning preserves existing data. SQLite is included in RSQLite: **no PostgreSQL,
Docker, database download, username, or password is needed**.
After installation, the R workflow works offline.

## 2. Query in RStudio

In the same **R Console**:

```r
DBI::dbListTables(con)
DBI::dbListFields(con, "condition_occurrence")
DBI::dbGetQuery(con, "
  SELECT gender, COUNT(DISTINCT subject_id) AS patients
  FROM patient GROUP BY gender
")

# Worked example: Black male patients with hypertension and their drug use.
source("sandbox_for_the_dummy.R")
drug_usage

# Export prevalence and utilization summaries to outputs/analysis/.
source("run_analysis.R")

# When finished. Run source("run_me.R") to reconnect later.
close_connection(con)
```

Tables are `patient`, `visit_occurrence`, `condition_occurrence`, `drug_exposure`,
`procedure_occurrence`, `observation`, and `measurement`; join them on
`subject_id`. Records cover 2024-2025. Condition `319835` means hypertension
**in this example**. Prevalence counts distinct patients, including patients
without diagnoses in the denominator. Drug exposure counts are not dose or duration.

## 3. Chat with the Analyst in Codex

**Codex is the agent. You do not need a separate Python AI application.**

| Component | Purpose |
| --- | --- |
| Codex | Runs the conversation and chooses tools to answer your questions. |
| [AGENTS.md](AGENTS.md) | Your analyst's role, analysis rules, and reporting instructions. |
| `omop-sqlite` MCP server | Gives Codex read-only tools for the local database. |

`AGENTS.md` is a Markdown instruction file, not executable code. Codex
[reads it when starting a session in this project](https://learn.chatgpt.com/docs/agent-configuration/agents-md).
It does not install or connect MCP by itself. The old standalone SDK example
has been removed; this approach uses your normal Codex sign-in, without an
additional API key or Agents SDK.

### One-Time MCP Setup

Skip this setup if `omop-sqlite` already works. First create the database in
section 1. Install [Python 3.11+](https://www.python.org/downloads/) and the
[Codex CLI](https://learn.chatgpt.com/docs/cli). For the npm installation below,
install [Node.js LTS](https://nodejs.org/en/download) first.

Run in **PowerShell** from the project folder, not in the R Console:

```powershell
# Skip this installation if Codex CLI is already installed.
npm.cmd install -g @openai/codex

# Replace this path with your project folder.
Set-Location 'C:\path\to\claude_test'
python -m venv .venv-mcp
.\.venv-mcp\Scripts\python.exe -m pip install -r mcp_sqlite/requirements.txt
.\.venv-mcp\Scripts\python.exe mcp_sqlite/check_connection.py
codex.cmd mcp add omop-sqlite -- "$PWD\.venv-mcp\Scripts\python.exe" "$PWD\mcp_sqlite\server.py" --db "$PWD\outputs\omop.sqlite"
codex.cmd mcp get omop-sqlite
```

The check should list three tools and seven tables; registration should show
`enabled: true`. The CLI saves absolute paths in your local Codex configuration,
not in the repository. Rerun registration if you move the project. Codex starts
the server automatically; RStudio does not need to remain open.
See the [MCP configuration guide](https://learn.chatgpt.com/docs/extend/mcp?surface=cli).

On **macOS/Linux**, install Python and Codex, then use these commands instead:

```bash
python3 -m venv .venv-mcp
.venv-mcp/bin/python -m pip install -r mcp_sqlite/requirements.txt
.venv-mcp/bin/python mcp_sqlite/check_connection.py
codex mcp add omop-sqlite -- "$(pwd)/.venv-mcp/bin/python" "$(pwd)/mcp_sqlite/server.py" --db "$(pwd)/outputs/omop.sqlite"
codex mcp get omop-sqlite
```

### Start a Conversation

Open this project in Codex, sign in if needed, reload MCP servers if needed,
and start a **new local chat** so the new `AGENTS.md` instructions are loaded.
Alternatively, run `codex.cmd` (Windows) or `codex` (macOS/Linux) from the
project directory. Ask normally; you do not need to mention MCP:

> What is the recorded prevalence of hypertension in this database?

> Among Black male patients with hypertension, which drugs have the most recorded exposures?

> Compare hypertension prevalence by gender, showing numerators and denominators.

For the unchanged sample, the first question should return **76 / 250 = 30.4%**,
based on all available records. Answers should use actual queries, explain
assumptions, and label results as synthetic. To change the analyst's behavior,
edit `AGENTS.md` and start a new chat.

### Safety

MCP exposes `list_tables`, `describe_table`, and `query`. The server enforces
read-only access, blocks writes and external database attachment, and limits
results to 500 rows / approximately 100 KB with a five-second query timeout.
`AGENTS.md` guides behavior; it is **not a security sandbox** or an automatic
privacy filter. Database results can be sent to the AI provider: use synthetic
data only. Codex needs network access and is subject to your account's usage
limits. A separate cloud/web session cannot access this local connection.

## Checks and Troubleshooting

Run R tests in the **R Console**:

```r
testthat::test_dir("tests")
```

Run MCP tests in **PowerShell** (macOS/Linux: use `.venv-mcp/bin/python`):

```powershell
.\.venv-mcp\Scripts\python.exe -m unittest discover -s mcp_sqlite -p test_server.py -v
```

| Problem | Fix |
| --- | --- |
| Missing R package | Repeat `install.packages(...)` in the RStudio session you use. |
| Missing file or `con` | Open `claude_test.Rproj` and run `source("run_me.R")`. |
| `python` not found on Windows | Try `py -3 -m venv .venv-mcp`, or reinstall Python and reopen the terminal. |
| `No module named mcp` | Install requirements using the same `.venv-mcp` Python shown above. |
| MCP tools absent | Check `codex.cmd mcp get omop-sqlite`, reload servers, and start a new local project chat. |
| Analyst instructions not applied | Confirm the project-root file is named `AGENTS.md`; start a new chat and ask which instructions are active. |
| Database locked | Finish open write transactions in other clients and retry. |

## Project Files

| Path | Purpose |
| --- | --- |
| `AGENTS.md` | Conversational analyst instructions. |
| `run_me.R` | Create/reopen the database, seed if empty, and run tests. |
| `sandbox_for_the_dummy.R` | Editable DBI queries and cohort/drug example. |
| `run_analysis.R` | Export summary CSV files. |
| `R/`, `db/`, `tests/` | Schema, synthetic data, connections, analysis, and R tests. |
| `mcp_sqlite/` | Read-only MCP server, pinned requirements, connection check, and tests. |

`outputs/`, `.venv-mcp/`, and local secrets (`.Renviron`, `.env*`) are ignored
by Git. No credentials belong in commits. The mock seed is `20260318`; ordinary
runs preserve edits. Tested on Windows with R 4.4.1 and Python 3.12.

