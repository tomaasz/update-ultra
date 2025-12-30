# test_log_reporting.ps1
# Standalone test for Resolve-ExistingLogOrNote logic.
# Usage: pwsh -NoProfile -File .\tests\test_log_reporting.ps1

$ErrorActionPreference = "Stop"
$global:TestFailed = $false

function Assert-Equal {
    param($Actual, $Expected, $Message)
    if ($Actual -eq $Expected) {
        Write-Host "[+] PASS: $Message" -ForegroundColor Green
    } else {
        Write-Host "[-] FAIL: $Message" -ForegroundColor Red
        Write-Host "    Expected: '$Expected'" -ForegroundColor Yellow
        Write-Host "    Actual:   '$Actual'" -ForegroundColor Yellow
        $global:TestFailed = $true
    }
}

# --- Function Under Test (Duplicated from src/Update-WingetAll.ps1) ---
function Resolve-ExistingLogOrNote {
    param([string]$Path)
    if ([string]::IsNullOrWhiteSpace($Path)) { return "(no log path)" }
    if (Test-Path -LiteralPath $Path) {
        return $Path
    }
    return "(log not created – winget exited before log was written)"
}
# ----------------------------------------------------------------------

Write-Host "Running tests for Resolve-ExistingLogOrNote..."

# Test 1: File Exists
$tempFile = [System.IO.Path]::GetTempFileName()
try {
    $result = Resolve-ExistingLogOrNote -Path $tempFile
    Assert-Equal -Actual $result -Expected $tempFile -Message "File exists -> should return path"
} finally {
    if (Test-Path $tempFile) { Remove-Item $tempFile -Force }
}

# Test 2: File Does Not Exist
$missingFile = Join-Path ([System.IO.Path]::GetTempPath()) "missing_$(Get-Random).log"
if (Test-Path $missingFile) { Remove-Item $missingFile -Force }
$resultMissing = Resolve-ExistingLogOrNote -Path $missingFile
Assert-Equal -Actual $resultMissing -Expected "(log not created – winget exited before log was written)" -Message "File missing -> should return note"

# Test 3: Empty Path
$resultEmpty = Resolve-ExistingLogOrNote -Path ""
Assert-Equal -Actual $resultEmpty -Expected "(no log path)" -Message "Empty path -> should return (no log path)"

# Test 4: Null Path
$resultNull = Resolve-ExistingLogOrNote -Path $null
Assert-Equal -Actual $resultNull -Expected "(no log path)" -Message "Null path -> should return (no log path)"

Write-Host ""
if ($global:TestFailed) {
    Write-Host "TESTS FAILED" -ForegroundColor Red
    exit 1
} else {
    Write-Host "ALL TESTS PASSED" -ForegroundColor Green
    exit 0
}
