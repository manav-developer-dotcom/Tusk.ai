# Tusk.ai Local Network Firewall Configuration Script
# Requires Administrator privileges to configure Windows Defender Firewall.

if (-not ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    Write-Host "Elevation required. Requesting Administrator prompt..."
    Start-Process powershell -Verb RunAs -ArgumentList "-NoProfile -ExecutionPolicy Bypass -File `"$PSCommandPath`""
    exit
}

Write-Host "=========================================="
Write-Host " Tusk.ai - Firewall Configuration"
Write-Host "=========================================="

# 1. Unblock/disable any blocking rules on python.exe or node.exe
Get-NetFirewallRule | Where-Object { ($_.DisplayName -like "*python*" -or $_.DisplayName -like "*node*") -and $_.Action -eq "Block" } | ForEach-Object {
    Write-Host "Disabling blocking rule: $($_.DisplayName) ($($_.Name))"
    Set-NetFirewallRule -Name $_.Name -Enabled False
}

# 2. Add an explicit allow rule for TCP Port 8000 on Any network profile
$existingRule = Get-NetFirewallRule -DisplayName "Tusk.ai Backend Port 8000" -ErrorAction SilentlyContinue
if (-not $existingRule) {
    New-NetFirewallRule -DisplayName "Tusk.ai Backend Port 8000" -Direction Inbound -LocalPort 8000 -Protocol TCP -Action Allow -Profile Any | Out-Null
    Write-Host "Added inbound allow rule: Tusk.ai Backend Port 8000 (TCP)"
} else {
    Set-NetFirewallRule -DisplayName "Tusk.ai Backend Port 8000" -Action Allow -Enabled True -Profile Any | Out-Null
    Write-Host "Updated existing rule: Tusk.ai Backend Port 8000"
}

Write-Host "Firewall configured successfully! Physical devices on your Wi-Fi network can now reach port 8000."
