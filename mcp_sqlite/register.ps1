$ErrorActionPreference = 'Stop'
$projectRoot = Split-Path -Parent $PSScriptRoot
$pythonPath = Join-Path $projectRoot '.venv-mcp/Scripts/python.exe'
$serverPath = Join-Path $PSScriptRoot 'server.py'
$databasePath = Join-Path $projectRoot 'outputs/omop.sqlite'

if (-not (Test-Path -LiteralPath $pythonPath)) {
    throw 'Create .venv-mcp and install mcp_sqlite/requirements.txt first. See README.md.'
}
if (-not (Test-Path -LiteralPath $databasePath)) {
    throw 'Run source("run_me.R") in the R project first.'
}

& codex mcp add omop-sqlite -- $pythonPath $serverPath --db $databasePath
if ($LASTEXITCODE -ne 0) { throw 'Codex MCP registration failed.' }
& codex mcp get omop-sqlite
if ($LASTEXITCODE -ne 0) { throw 'Could not verify Codex MCP registration.' }
