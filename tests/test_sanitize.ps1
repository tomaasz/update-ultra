
<#
.SYNOPSIS
    Tests for Sanitize-FileName helper logic.
#>

# Mock/Extract the function from source
$scriptPath = Join-Path $PSScriptRoot "../src/Update-WingetAll.ps1"
$scriptContent = Get-Content -Path $scriptPath -Raw

if ($scriptContent -match "(?ms)function\s+Sanitize-FileName\s*\{.*?\n\}") {
    Invoke-Expression $Matches[0]
} else {
    Write-Error "Could not extract Sanitize-FileName from script."
    exit 1
}

$testCases = @(
    @{ Input = "NormalName"; Expected = "NormalName" }
    @{ Input = "Name With Space"; Expected = "Name_With_Space" }
    @{ Input = "Name/With/Slash"; Expected = "Name_With_Slash" }
    @{ Input = "1024 KB /"; Expected = "1024_KB" }
    @{ Input = "Funny:Name*"; Expected = "Funny_Name" }
    @{ Input = "   LeadingTrailing   "; Expected = "_LeadingTrailing" }
    @{ Input = "Multiple   Spaces"; Expected = "Multiple_Spaces" }
    @{ Input = "EndDot."; Expected = "EndDot" }
    @{ Input = "CON"; Expected = "_CON" }
    @{ Input = "lpt1"; Expected = "_lpt1" }
    @{ Input = "NUL"; Expected = "_NUL" }
    @{ Input = "A" * 150; Match = "^A{120}_[0-9A-F]+$" }
)

$failures = 0
foreach ($case in $testCases) {
    $result = Sanitize-FileName -Name $case.Input
    if ($case.Match) {
        if ($result -match $case.Match) {
            # Pass
        } else {
            Write-Error "FAIL: Input='$($case.Input)' Expected pattern='$($case.Match)' Got='$result'"
            $failures++
        }
    } elseif ($result -ne $case.Expected) {
        Write-Error "FAIL: Input='$($case.Input)' Expected='$($case.Expected)' Got='$result'"
        $failures++
    }
}

if ($failures -eq 0) {
    Write-Host "All Sanitize-FileName tests passed."
} else {
    exit 1
}
