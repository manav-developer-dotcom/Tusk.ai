# Tusk.ai External Agent Service Launcher
param(
    [string]$AgentName = "",
    [int]$AgentPort = 8001,
    [string]$AgentEndpoint = ""
)

$ErrorActionPreference = "Stop"

$workspaceRoot = $PSScriptRoot | Split-Path -Parent
$backendDir = Join-Path $workspaceRoot "backend"
$venvPython = Join-Path $backendDir ".venv\Scripts\python.exe"

Write-Host "=========================================="
Write-Host " Tusk.ai - External Agent Service"
Write-Host " Backend  : $backendDir"
Write-Host " Port     : $AgentPort"
if ($AgentName) { Write-Host " Name     : $AgentName" }
Write-Host "=========================================="

if (-not (Test-Path $venvPython)) {
    Write-Error "Virtual environment not found at $venvPython. Run 'python -m venv .venv && .venv\Scripts\pip install -r requirements.txt' inside backend/."
    exit 1
}

$env:TUSK_AGENT_PORT = "$AgentPort"
if ($AgentName)     { $env:TUSK_AGENT_NAME     = $AgentName }
if ($AgentEndpoint) { $env:TUSK_AGENT_ENDPOINT = $AgentEndpoint }

Push-Location $backendDir
try {
    Write-Host "Starting Tusk.ai external agent on port $AgentPort..."
    & $venvPython -m app.agent.agent
} finally {
    Pop-Location
}
