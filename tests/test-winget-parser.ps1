
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

$scriptPath = Join-Path $PSScriptRoot "../src/Update-WingetAll.ps1"
$scriptContent = Get-Content -Path $scriptPath -Raw

# Extract functions using improved regex that handles multi-line functions
$functionsToTest = @("Parse-WingetUpgradeList", "Get-WingetExplicitTargetIds", "As-Array", "SafeCount")

foreach ($funcName in $functionsToTest) {
    # Match function block: function Name { ... }
    # Use a more robust approach: find the function start, then count braces
    $pattern = "function\s+$funcName\s*\{"
    $startMatch = [regex]::Match($scriptContent, $pattern)

    if ($startMatch.Success) {
        $startPos = $startMatch.Index
        $braceCount = 0
        $inFunction = $false
        $functionText = ""

        for ($i = $startPos; $i -lt $scriptContent.Length; $i++) {
            $char = $scriptContent[$i]
            $functionText += $char

            if ($char -eq '{') { $braceCount++; $inFunction = $true }
            if ($char -eq '}') { $braceCount--; }

            if ($inFunction -and $braceCount -eq 0) {
                break
            }
        }

        Invoke-Expression $functionText
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

Write-Host "`n=== Testing Get-WingetExplicitTargetIds with progress lines ==="

# Simulates real winget output with download progress after the table
$explicitWithProgress = @(
    "Name       Id                      Version  Available Source",
    "------------------------------------------------------------",
    "Okular     KDE.Okular              25.12.0  25.12.1   winget",
    "Oh My Posh JanDeDobbeleer.OhMyPosh 28.9.0.0 28.10.0   winget",
    "3 upgrades available.",
    "",
    "The following packages have an upgrade available, but require explicit targeting for upgrade:",
    "Name    Id              Version  Available Source",
    "-------------------------------------------------",
    "Discord Discord.Discord 1.0.9210 1.0.9219  winget",
    "",
    "(1/2) Found Okular [KDE.Okular] Version 25.12.1",
    "This application is licensed to you by its owner.",
    "Downloading https://cdn.kde.org/ci-builds/graphics/okular/release-25.12/windows/okular-release_25.12-7068-windows-cl-msvc2022-x86_64.exe",
    "  ▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒  1024 KB /  152 MB",
    "  ███████▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒  38.0 MB /  152 MB",
    "  ████████████████▒▒▒▒▒▒▒▒▒▒▒▒▒▒  83.0 MB /  152 MB",
    "  ▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒  2%",
    "  ██▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒  9%",
    "  ██████████████████████████████  100%"
)

try {
    $ids = Get-WingetExplicitTargetIds -Lines $explicitWithProgress

    Assert-True ($ids -is [Array]) "Result should be an array"
    Assert-Equal $ids.Count 1 "Should find only 1 ID (Discord.Discord), not progress lines"
    Assert-True ($ids -contains "Discord.Discord") "Should contain Discord.Discord"
    Assert-True ($ids -notcontains "1024") "Should NOT contain '1024' from progress"
    Assert-True ($ids -notcontains "2%") "Should NOT contain '2%' from progress"
    Assert-True ($ids -notcontains "38.0") "Should NOT contain '38.0' from progress"

} catch {
    Write-Host "[FAIL] Exception during Get-WingetExplicitTargetIds with progress: $_" -ForegroundColor Red
    $failed++
}

Write-Host "`n=== Summary ==="
Write-Host "Passed: $passed"
Write-Host "Failed: $failed"

if ($failed -gt 0) { exit 1 } else { exit 0 }
