# Install-Alias.ps1 - Dodaje alias 'upd' do profilu PowerShell

$scriptPath = Join-Path $PSScriptRoot "src\Update-WingetAll.ps1"

# Funkcja do dodania do profilu
$functionCode = @"

# update-ultra alias
function upd {
    param(
        [switch]`$WhatIf,
        [switch]`$Force,
        [string[]]`$Skip
    )

    `$scriptPath = "$scriptPath"

    # Build arguments
    `$args = @()
    if (`$WhatIf) { `$args += "-WhatIf" }
    if (`$Force) { `$args += "-Force" }
    foreach (`$s in `$Skip) {
        `$args += "-Skip`$s"
    }

    # Check if running as admin
    `$isAdmin = ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)

    if (`$isAdmin) {
        # Already admin, just run
        & `$scriptPath @args
    } else {
        # Restart as admin
        `$argString = (`$args -join " ")
        Start-Process pwsh -Verb RunAs -ArgumentList "-NoExit", "-Command", "& '`$scriptPath' `$argString"
    }
}

"@

Write-Host "Instalacja aliasu 'upd' do profilu PowerShell..." -ForegroundColor Cyan
Write-Host "Profil: $PROFILE" -ForegroundColor Gray

# Create profile if doesn't exist
if (-not (Test-Path $PROFILE)) {
    Write-Host "Tworzę profil PowerShell..." -ForegroundColor Yellow
    New-Item -Path $PROFILE -ItemType File -Force | Out-Null
}

# Check if function already exists
$profileContent = Get-Content $PROFILE -Raw -ErrorAction SilentlyContinue
if ($profileContent -match 'function upd') {
    Write-Host "Funkcja 'upd' już istnieje w profilu!" -ForegroundColor Yellow
    $replace = Read-Host "Czy zastąpić istniejącą funkcję? (T/N)"

    if ($replace -eq 'T' -or $replace -eq 't') {
        # Remove old function
        $profileContent = $profileContent -replace '(?ms)# update-ultra alias.*?^}', ''
        $profileContent | Set-Content $PROFILE
        Write-Host "Usunięto starą wersję." -ForegroundColor Green
    } else {
        Write-Host "Anulowano. Profil nie został zmieniony." -ForegroundColor Red
        return
    }
}

# Add function to profile
Add-Content $PROFILE $functionCode

Write-Host "`n✅ Alias 'upd' został dodany do profilu!" -ForegroundColor Green
Write-Host "`nUżycie:" -ForegroundColor Cyan
Write-Host "  upd                    # Uruchom pełną aktualizację" -ForegroundColor White
Write-Host "  upd -WhatIf            # Podgląd bez zmian" -ForegroundColor White
Write-Host "  upd -Force             # Wymuś aktualizacje" -ForegroundColor White
Write-Host "  upd -Skip Docker,WSL   # Pomiń wybrane sekcje" -ForegroundColor White

Write-Host "`nPrzeładuj profil:" -ForegroundColor Yellow
Write-Host "  . `$PROFILE" -ForegroundColor White
Write-Host "`nlub uruchom nowe okno PowerShell." -ForegroundColor Gray
