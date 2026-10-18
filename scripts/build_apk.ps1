# Tusk.ai Local Debug APK Build Workflow

$ErrorActionPreference = "Stop"

$workspaceRoot = $PSScriptRoot | Split-Path -Parent
$appDir = Join-Path $workspaceRoot "app"
$artifactsDir = Join-Path $workspaceRoot "artifacts\apk"
$targetApk = Join-Path $artifactsDir "TuskAI-debug.apk"
$buildApk = Join-Path $appDir "build\app\outputs\flutter-apk\app-debug.apk"

Write-Host "=========================================="
Write-Host " Tusk.ai - Local Debug APK Build Workflow"
Write-Host " Workspace: $workspaceRoot"
Write-Host "=========================================="

# 1. Ensure artifacts directory exists
if (-not (Test-Path $artifactsDir)) {
    New-Item -ItemType Directory -Path $artifactsDir -Force | Out-Null
    Write-Host "[1/4] Created artifacts directory: $artifactsDir"
} else {
    Write-Host "[1/4] Artifacts directory verified: $artifactsDir"
}

# 2. Check Flutter presence
if (-not (Get-Command flutter -ErrorAction SilentlyContinue)) {
    Write-Error "Flutter is not available in PATH. Please verify your environment."
    exit 1
}

# 3. Build APK
Write-Host "[2/4] Building Android debug APK via Flutter..."
Push-Location $appDir
try {
    flutter build apk --debug
    $exitCode = $LASTEXITCODE
} finally {
    Pop-Location
}

if ($exitCode -ne 0) {
    Write-Error "flutter build apk --debug failed with exit code $exitCode."
    exit $exitCode
}
Write-Host "[3/4] Build succeeded with exit code 0."

# 4. Copy and verify output
if (-not (Test-Path $buildApk)) {
    Write-Error "Expected build output not found at: $buildApk"
    exit 1
}

Copy-Item -Path $buildApk -Destination $targetApk -Force

if (Test-Path $targetApk) {
    $apkItem = Get-Item $targetApk
    $apkBytes = $apkItem.Length
    if ($apkBytes -gt 0) {
        $sizeMb = [math]::Round($apkBytes / 1MB, 2)
        Write-Host "[4/4] Output successfully verified!"
        Write-Host "------------------------------------------"
        Write-Host "Verified Artifact : $targetApk"
        Write-Host "File Size         : $sizeMb MB ($apkBytes bytes)"
        Write-Host "Build Status      : READY FOR LOCAL INSTALL"
        Write-Host "------------------------------------------"
    } else {
        Write-Error "Artifact was created but has 0 bytes: $targetApk"
        exit 1
    }
} else {
    Write-Error "Failed to copy APK to destination: $targetApk"
    exit 1
}
