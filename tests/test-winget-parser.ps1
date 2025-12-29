
<#
.SYNOPSIS
    Test suite for Winget parser logic in Update-WingetAll.ps1.
    Run with: pwsh -NoProfile -File .\tests\test-winget-parser.ps1
#>

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

# --- Mock / Setup ---
# We need to source the functions from the script.
# Since the script executes code, we need a way to extract functions or prevent execution.
# For this task, we will extract the relevant functions by reading the file.
# This avoids modifying the script just to make it sourceable (though that would be better practice).

$scriptPath = Join-Path $PSScriptRoot "../src/Update-WingetAll.ps1"
$scriptContent = Get-Content -Path $scriptPath -Raw

# Extract functions using regex (simple extraction)
$functionsToTest = @("Parse-WingetUpgradeList", "Get-WingetExplicitTargetIds", "As-Array")

foreach ($funcName in $functionsToTest) {
    # Match function block: function Name { ... }
    # This regex is a bit fragile but works for well-formatted code
    if ($scriptContent -match "(?ms)function\s+$funcName\s*\{.*?\n\}") {
        Invoke-Expression $Matches[0]
    } else {
        Write-Error "Could not extract function $funcName from script."
        exit 1
    }
}

# --- Tests ---

$failed = 0
$passed = 0

function Assert-True ($condition, $msg) {
    if ($condition) {
        Write-Host "[PASS] $msg" -ForegroundColor Green
        $global:passed++
    } else {
        Write-Host "[FAIL] $msg" -ForegroundColor Red
        $global:failed++
    }
}

function Assert-Equal ($actual, $expected, $msg) {
    if ($actual -eq $expected) {
        Write-Host "[PASS] $msg" -ForegroundColor Green
        $global:passed++
    } else {
        Write-Host "[FAIL] $msg. Expected '$expected', got '$actual'" -ForegroundColor Red
        $global:failed++
    }
}

Write-Host "`n=== Testing Parse-WingetUpgradeList ==="

$sampleLines = @(
    "",
    "Name                                              Id                                      Version          Available        Source",
    "--------------------------------------------------------------------------------------------------------------------------------------",
    "Microsoft.AppInstaller                            Microsoft.AppInstaller                  1.21.3183.0      1.22.3183.0      winget",
    "   ", # whitespace line
    "-",   # dash line
    "----------------", # separator line
    "Google.Chrome                                     Google.Chrome                           121.0.6167.140   121.0.6167.161   winget"
)

try {
    $result = Parse-WingetUpgradeList -Lines $sampleLines

    Assert-True ($result -is [Array]) "Result should be an array"
    Assert-Equal $result.Count 2 "Should parse 2 items"

    $item1 = $result[0]
    Assert-Equal $item1.Name "Microsoft.AppInstaller" "Item 1 Name"
    Assert-Equal $item1.Id "Microsoft.AppInstaller" "Item 1 Id"
    Assert-Equal $item1.Version "1.21.3183.0" "Item 1 Version"
    Assert-Equal $item1.Available "1.22.3183.0" "Item 1 Available"
    Assert-Equal $item1.Source "winget" "Item 1 Source"

    $item2 = $result[1]
    Assert-Equal $item2.Name "Google.Chrome" "Item 2 Name"

} catch {
    Write-Host "[FAIL] Exception during Parse-WingetUpgradeList: $_" -ForegroundColor Red
    $failed++
}

Write-Host "`n=== Testing Get-WingetExplicitTargetIds ==="

$explicitLines = @(
    "Name      Id       Version",
    "------    --       -------",
    "SomeApp   App.Id   1.0.0",
    "",
    "The following packages have an upgrade available, but require explicit targeting for reasons",
    "such as pinning a version or skipping an upgrade:",
    "",
    "Name                                              Id                                      Version          Available        Source",
    "--------------------------------------------------------------------------------------------------------------------------------------",
    "Foo Bar                                           Foo.Bar                                 1.0              2.0              winget",
    "Baz                                               Baz.Qux                                 3.0              3.1              winget"
)

try {
    $ids = Get-WingetExplicitTargetIds -Lines $explicitLines
    Assert-True ($ids -is [Array]) "Ids result should be an array"
    # Depending on current implementation, it might extract Foo.Bar and Baz.Qux
    # Let's check what it does.
    # The function looks for "require explicit targeting" and then parses the table.

    Assert-True ($ids -contains "Foo.Bar") "Should contain Foo.Bar"
    Assert-True ($ids -contains "Baz.Qux") "Should contain Baz.Qux"
    Assert-Equal $ids.Count 2 "Should find 2 IDs"

} catch {
    Write-Host "[FAIL] Exception during Get-WingetExplicitTargetIds: $_" -ForegroundColor Red
    $failed++
}

Write-Host "`n=== Summary ==="
Write-Host "Passed: $passed"
Write-Host "Failed: $failed"

if ($failed -gt 0) { exit 1 } else { exit 0 }
