# Tusk.ai Backend Service Launcher
param(
    [string]$HostAddress = "0.0.0.0",
    [int]$Port = 8000
)

$ErrorActionPreference = "Stop"

$workspaceRoot = $PSScriptRoot | Split-Path -Parent
$backendDir = Join-Path $workspaceRoot "backend"
$venvPython = Join-Path $backendDir ".venv\Scripts\python.exe"
$venvUvicorn = Join-Path $backendDir ".venv\Scripts\uvicorn.exe"

Write-Host "=========================================="
Write-Host " Tusk.ai - Backend Service Launcher"
Write-Host " Host: $HostAddress"
Write-Host " Port: $Port"
Write-Host "=========================================="

if (-not (Test-Path $venvPython)) {
    Write-Error "Virtual environment not found at $venvPython. Please run 'python -m venv .venv' inside backend/."
    exit 1
}

Push-Location $backendDir
try {
    Write-Host "Starting FastAPI application on http://${HostAddress}:${Port}..."
    & $venvUvicorn app.main:app --host $HostAddress --port $Port --reload
} finally {
    Pop-Location
}
