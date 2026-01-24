# ComparisonEngine.psm1
# Moduł do porównywania wyników aktualizacji między uruchomieniami

<#
.SYNOPSIS
Moduł do porównywania wyników aktualizacji i analizy trendów.

.DESCRIPTION
ComparisonEngine umożliwia:
- Porównywanie dwóch summary JSON (diff pakietów, metryk)
- Analizę trendów z ostatnich N uruchomień
- Generowanie raportów zmian
- Wykrywanie anomalii (wzrost czasu wykonania, częstość błędów)

.NOTES
Author: update-ultra team
Version: 5.2.0
Requires: PowerShell 5.1+
#>

#Requires -Version 5.1

# Module state
$script:HistoryDir = Join-Path $env:APPDATA "update-ultra\history"

<#
.SYNOPSIS
Inicjalizuje moduł ComparisonEngine.

.DESCRIPTION
Tworzy katalog history jeśli nie istnieje.

.EXAMPLE
Initialize-ComparisonEngine

.NOTES
Funkcja pomocnicza, wywoływana automatycznie przy imporcie modułu.
#>
function Initialize-ComparisonEngine {
    [CmdletBinding()]
    param()

    if (-not (Test-Path $script:HistoryDir)) {
        New-Item -ItemType Directory -Path $script:HistoryDir -Force | Out-Null
        Write-Verbose "Created history directory: $script:HistoryDir"
    }

    Write-Verbose "ComparisonEngine module initialized"
}

<#
.SYNOPSIS
Porównuje dwa summary JSON.

.DESCRIPTION
Porównuje wyniki dwóch uruchomień aktualizacji i zwraca diff zawierający:
- Zmienione sekcje (status, duration, package counts)
- Diff pakietów (added/removed/updated)
- Zmiany metryk

.PARAMETER Summary1
Pierwszy summary (starszy) - hashtable lub PSCustomObject.

.PARAMETER Summary2
Drugi summary (nowszy) - hashtable lub PSCustomObject.

.PARAMETER IncludePackageDiff
Czy dołączyć szczegółowy diff pakietów (domyślnie: $true).

.EXAMPLE
$old = Get-Content "summary-old.json" | ConvertFrom-Json
$new = Get-Content "summary-new.json" | ConvertFrom-Json
$diff = Compare-UpdateRuns -Summary1 $old -Summary2 $new

.EXAMPLE
Compare-UpdateRuns -Summary1 $oldHashtable -Summary2 $newHashtable -IncludePackageDiff $false

.OUTPUTS
PSCustomObject - Diff object.
#>
function Compare-UpdateRuns {
    [CmdletBinding()]
    [OutputType([PSCustomObject])]
    param(
        [Parameter(Mandatory)]
        [ValidateNotNull()]
        $Summary1,

        [Parameter(Mandatory)]
        [ValidateNotNull()]
        $Summary2,

        [Parameter()]
        [bool]$IncludePackageDiff = $true
    )

    begin {
        Write-Verbose "Comparing two update runs..."
    }

    process {
        # Konwertuj do hashtable
        $data1 = if ($Summary1 -is [PSCustomObject]) {
            Convert-PSObjectToHashtable -InputObject $Summary1
        } else { $Summary1 }

        $data2 = if ($Summary2 -is [PSCustomObject]) {
            Convert-PSObjectToHashtable -InputObject $Summary2
        } else { $Summary2 }

        # Build diff
        $diff = [ordered]@{
            Timestamp1 = $data1.Timestamp
            Timestamp2 = $data2.Timestamp
            SectionsDiff = @()
            MetricsDiff = @{}
            PackagesDiff = @{}
        }

        # Compare metrics
        $metrics1 = Get-OverallMetrics -Data $data1
        $metrics2 = Get-OverallMetrics -Data $data2

        $diff.MetricsDiff = [ordered]@{
            TotalDuration = @{
                Before = $metrics1.TotalDuration
                After = $metrics2.TotalDuration
                Change = $metrics2.TotalDuration - $metrics1.TotalDuration
                PercentChange = if ($metrics1.TotalDuration -gt 0) {
                    [math]::Round((($metrics2.TotalDuration - $metrics1.TotalDuration) / $metrics1.TotalDuration) * 100, 2)
                } else { 0 }
            }
            TotalPackagesUpdated = @{
                Before = $metrics1.TotalPackagesUpdated
                After = $metrics2.TotalPackagesUpdated
                Change = $metrics2.TotalPackagesUpdated - $metrics1.TotalPackagesUpdated
            }
            TotalPackagesFailed = @{
                Before = $metrics1.TotalPackagesFailed
                After = $metrics2.TotalPackagesFailed
                Change = $metrics2.TotalPackagesFailed - $metrics1.TotalPackagesFailed
            }
        }

        # Compare sections
        $sectionsMap1 = @{}
        foreach ($result in $data1.Results) {
            $sectionsMap1[$result.Name] = $result
        }

        $sectionsMap2 = @{}
        foreach ($result in $data2.Results) {
            $sectionsMap2[$result.Name] = $result
        }

        # Find all section names
        $allSections = @($sectionsMap1.Keys) + @($sectionsMap2.Keys) | Select-Object -Unique

        foreach ($sectionName in $allSections) {
            $section1 = $sectionsMap1[$sectionName]
            $section2 = $sectionsMap2[$sectionName]

            $sectionDiff = [ordered]@{
                Name = $sectionName
                StatusChanged = $false
                DurationChanged = $false
            }

            # Section added/removed
            if (-not $section1) {
                $sectionDiff.Change = "Added"
                $sectionDiff.StatusBefore = $null
                $sectionDiff.StatusAfter = $section2.Status
                $sectionDiff.StatusChanged = $true
            }
            elseif (-not $section2) {
                $sectionDiff.Change = "Removed"
                $sectionDiff.StatusBefore = $section1.Status
                $sectionDiff.StatusAfter = $null
                $sectionDiff.StatusChanged = $true
            }
            else {
                # Both exist - compare
                $sectionDiff.Change = "Modified"
                $sectionDiff.StatusBefore = $section1.Status
                $sectionDiff.StatusAfter = $section2.Status
                $sectionDiff.StatusChanged = ($section1.Status -ne $section2.Status)

                $duration1 = if ($section1.DurationS) { [double]$section1.DurationS } else { 0.0 }
                $duration2 = if ($section2.DurationS) { [double]$section2.DurationS } else { 0.0 }

                $sectionDiff.DurationBefore = $duration1
                $sectionDiff.DurationAfter = $duration2
                $sectionDiff.DurationChange = $duration2 - $duration1
                $sectionDiff.DurationChanged = ([math]::Abs($duration2 - $duration1) > 0.1)

                # Package counts
                $updated1 = if ($section1.Counts) { [int]$section1.Counts.Updated } else { 0 }
                $updated2 = if ($section2.Counts) { [int]$section2.Counts.Updated } else { 0 }
                $failed1 = if ($section1.Counts) { [int]$section1.Counts.Failed } else { 0 }
                $failed2 = if ($section2.Counts) { [int]$section2.Counts.Failed } else { 0 }

                $sectionDiff.PackagesUpdatedBefore = $updated1
                $sectionDiff.PackagesUpdatedAfter = $updated2
                $sectionDiff.PackagesUpdatedChange = $updated2 - $updated1

                $sectionDiff.PackagesFailedBefore = $failed1
                $sectionDiff.PackagesFailedAfter = $failed2
                $sectionDiff.PackagesFailedChange = $failed2 - $failed1

                # Package diff
                if ($IncludePackageDiff) {
                    $pkgDiff = Compare-PackageLists -Packages1 $section1.Packages -Packages2 $section2.Packages
                    $diff.PackagesDiff[$sectionName] = $pkgDiff
                }
            }

            $diff.SectionsDiff += [PSCustomObject]$sectionDiff
        }

        return [PSCustomObject]$diff
    }
}

<#
.SYNOPSIS
Analizuje trendy z ostatnich N uruchomień.

.DESCRIPTION
Analizuje historię uruchomień i zwraca:
- Średnie czasy wykonania per sekcja
- Trendy liczby pakietów (wzrost/spadek)
- Częstość błędów
- Anomalie (outliers)

.PARAMETER HistoryPath
Ścieżka do katalogu z plikami summary JSON (domyślnie: %APPDATA%\update-ultra\history).

.PARAMETER Last
Liczba ostatnich uruchomień do analizy (domyślnie: 10).

.PARAMETER IncludeAnomalies
Czy wykrywać anomalie (domyślnie: $true).

.EXAMPLE
Get-UpdateTrends -Last 20

.EXAMPLE
Get-UpdateTrends -HistoryPath "C:\Logs\updates" -Last 30 -IncludeAnomalies $true

.OUTPUTS
PSCustomObject - Obiekt z trendami.
#>
function Get-UpdateTrends {
    [CmdletBinding()]
    [OutputType([PSCustomObject])]
    param(
        [Parameter()]
        [string]$HistoryPath = $script:HistoryDir,

        [Parameter()]
        [ValidateRange(2, 100)]
        [int]$Last = 10,

        [Parameter()]
        [bool]$IncludeAnomalies = $true
    )

    begin {
        Write-Verbose "Analyzing update trends from last $Last runs..."
    }

    process {
        # Znajdź pliki summary JSON
        if (-not (Test-Path $HistoryPath)) {
            Write-Warning "History directory not found: $HistoryPath"
            return $null
        }

        $summaryFiles = Get-ChildItem -Path $HistoryPath -Filter "*_summary.json" -ErrorAction SilentlyContinue |
            Sort-Object LastWriteTime -Descending |
            Select-Object -First $Last

        if ($summaryFiles.Count -lt 2) {
            Write-Warning "Not enough history data (found $($summaryFiles.Count) files, need at least 2)"
            return $null
        }

        Write-Verbose "Found $($summaryFiles.Count) summary files for analysis"

        # Załaduj dane
        $summaries = @()
        foreach ($file in $summaryFiles) {
            try {
                $content = Get-Content $file.FullName -Raw | ConvertFrom-Json
                $data = Convert-PSObjectToHashtable -InputObject $content
                $summaries += $data
            }
            catch {
                Write-Warning "Failed to load $($file.Name): $($_.Exception.Message)"
            }
        }

        if ($summaries.Count -lt 2) {
            Write-Warning "Not enough valid summary data"
            return $null
        }

        # Analiza trendów
        $trends = [ordered]@{
            AnalyzedRuns = $summaries.Count
            DateRange = @{
                From = $summaries[-1].Timestamp
                To = $summaries[0].Timestamp
            }
            Sections = @{}
            OverallTrends = @{}
        }

        # Collect per-section data
        $sectionData = @{}

        foreach ($summary in $summaries) {
            foreach ($result in $summary.Results) {
                $sectionName = $result.Name

                if (-not $sectionData.ContainsKey($sectionName)) {
                    $sectionData[$sectionName] = @{
                        Durations = @()
                        PackagesUpdated = @()
                        PackagesFailed = @()
                        Statuses = @()
                    }
                }

                $duration = if ($result.DurationS) { [double]$result.DurationS } else { 0.0 }
                $updated = if ($result.Counts) { [int]$result.Counts.Updated } else { 0 }
                $failed = if ($result.Counts) { [int]$result.Counts.Failed } else { 0 }

                $sectionData[$sectionName].Durations += $duration
                $sectionData[$sectionName].PackagesUpdated += $updated
                $sectionData[$sectionName].PackagesFailed += $failed
                $sectionData[$sectionName].Statuses += $result.Status
            }
        }

        # Calculate trends per section
        foreach ($sectionName in $sectionData.Keys) {
            $data = $sectionData[$sectionName]

            $avgDuration = ($data.Durations | Measure-Object -Average).Average
            $minDuration = ($data.Durations | Measure-Object -Minimum).Minimum
            $maxDuration = ($data.Durations | Measure-Object -Maximum).Maximum

            $avgUpdated = ($data.PackagesUpdated | Measure-Object -Average).Average
            $avgFailed = ($data.PackagesFailed | Measure-Object -Average).Average

            $successCount = ($data.Statuses | Where-Object { $_ -eq 'OK' }).Count
            $failCount = ($data.Statuses | Where-Object { $_ -eq 'FAIL' }).Count
            $skipCount = ($data.Statuses | Where-Object { $_ -eq 'SKIP' }).Count

            $successRate = if ($data.Statuses.Count -gt 0) {
                [math]::Round(($successCount / $data.Statuses.Count) * 100, 2)
            } else { 0 }

            $trends.Sections[$sectionName] = [ordered]@{
                AverageDuration = [math]::Round($avgDuration, 2)
                MinDuration = [math]::Round($minDuration, 2)
                MaxDuration = [math]::Round($maxDuration, 2)
                AveragePackagesUpdated = [math]::Round($avgUpdated, 2)
                AveragePackagesFailed = [math]::Round($avgFailed, 2)
                SuccessRate = $successRate
                SuccessCount = $successCount
                FailCount = $failCount
                SkipCount = $skipCount
                Trend = Get-TrendDirection -Values $data.Durations
            }

            # Anomalies
            if ($IncludeAnomalies) {
                $anomalies = Find-Anomalies -Values $data.Durations -Threshold 2.0
                if ($anomalies.Count -gt 0) {
                    $trends.Sections[$sectionName].Anomalies = $anomalies
                }
            }
        }

        # Overall trends
        $totalDurations = @()
        $totalUpdated = @()
        $totalFailed = @()

        foreach ($summary in $summaries) {
            $metrics = Get-OverallMetrics -Data $summary
            $totalDurations += $metrics.TotalDuration
            $totalUpdated += $metrics.TotalPackagesUpdated
            $totalFailed += $metrics.TotalPackagesFailed
        }

        $trends.OverallTrends = [ordered]@{
            AverageTotalDuration = [math]::Round(($totalDurations | Measure-Object -Average).Average, 2)
            MinTotalDuration = [math]::Round(($totalDurations | Measure-Object -Minimum).Minimum, 2)
            MaxTotalDuration = [math]::Round(($totalDurations | Measure-Object -Maximum).Maximum, 2)
            AverageTotalUpdated = [math]::Round(($totalUpdated | Measure-Object -Average).Average, 2)
            AverageTotalFailed = [math]::Round(($totalFailed | Measure-Object -Average).Average, 2)
            TotalDurationTrend = Get-TrendDirection -Values $totalDurations
        }

        return [PSCustomObject]$trends
    }
}

<#
.SYNOPSIS
Wyświetla raport zmian między dwoma uruchomieniami.

.DESCRIPTION
Generuje czytelny raport diff w formacie tekstowym.

.PARAMETER DiffObject
Obiekt diff z Compare-UpdateRuns.

.PARAMETER OutputFormat
Format output: "Text" lub "Markdown" (domyślnie: "Text").

.EXAMPLE
$diff = Compare-UpdateRuns -Summary1 $old -Summary2 $new
Show-ChangeReport -DiffObject $diff

.EXAMPLE
Show-ChangeReport -DiffObject $diff -OutputFormat "Markdown" | Out-File report.md

.OUTPUTS
String - Formatted change report.
#>
function Show-ChangeReport {
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory, ValueFromPipeline)]
        [ValidateNotNull()]
        [PSCustomObject]$DiffObject,

        [Parameter()]
        [ValidateSet('Text', 'Markdown')]
        [string]$OutputFormat = 'Text'
    )

    process {
        $report = @()

        if ($OutputFormat -eq 'Markdown') {
            $report += "# Update Comparison Report"
            $report += ""
            $report += "**Period:** $($DiffObject.Timestamp1) → $($DiffObject.Timestamp2)"
            $report += ""

            # Metrics
            $report += "## Overall Metrics Changes"
            $report += ""
            $report += "| Metric | Before | After | Change |"
            $report += "|--------|--------|-------|--------|"

            $durationChange = $DiffObject.MetricsDiff.TotalDuration.Change
            $durationChangeStr = if ($durationChange -gt 0) { "+$durationChange" } else { "$durationChange" }
            $report += "| Total Duration (s) | $($DiffObject.MetricsDiff.TotalDuration.Before) | $($DiffObject.MetricsDiff.TotalDuration.After) | $durationChangeStr ($($DiffObject.MetricsDiff.TotalDuration.PercentChange)%) |"

            $updatedChange = $DiffObject.MetricsDiff.TotalPackagesUpdated.Change
            $updatedChangeStr = if ($updatedChange -gt 0) { "+$updatedChange" } else { "$updatedChange" }
            $report += "| Packages Updated | $($DiffObject.MetricsDiff.TotalPackagesUpdated.Before) | $($DiffObject.MetricsDiff.TotalPackagesUpdated.After) | $updatedChangeStr |"

            $failedChange = $DiffObject.MetricsDiff.TotalPackagesFailed.Change
            $failedChangeStr = if ($failedChange -gt 0) { "+$failedChange" } else { "$failedChange" }
            $report += "| Packages Failed | $($DiffObject.MetricsDiff.TotalPackagesFailed.Before) | $($DiffObject.MetricsDiff.TotalPackagesFailed.After) | $failedChangeStr |"

            $report += ""

            # Sections
            $report += "## Section Changes"
            $report += ""

            foreach ($sectionDiff in $DiffObject.SectionsDiff) {
                if ($sectionDiff.StatusChanged -or $sectionDiff.DurationChanged) {
                    $report += "### $($sectionDiff.Name)"
                    $report += ""

                    if ($sectionDiff.Change -eq "Added") {
                        $report += "- **Status:** Added (new section)"
                    }
                    elseif ($sectionDiff.Change -eq "Removed") {
                        $report += "- **Status:** Removed"
                    }
                    else {
                        if ($sectionDiff.StatusChanged) {
                            $report += "- **Status changed:** $($sectionDiff.StatusBefore) → $($sectionDiff.StatusAfter)"
                        }
                        if ($sectionDiff.DurationChanged) {
                            $durationChange = [math]::Round($sectionDiff.DurationChange, 2)
                            $durationChangeStr = if ($durationChange -gt 0) { "+$durationChange" } else { "$durationChange" }
                            $report += "- **Duration changed:** $($sectionDiff.DurationBefore)s → $($sectionDiff.DurationAfter)s ($durationChangeStr s)"
                        }
                        if ($sectionDiff.PackagesUpdatedChange -ne 0) {
                            $report += "- **Packages updated changed:** $($sectionDiff.PackagesUpdatedBefore) → $($sectionDiff.PackagesUpdatedAfter)"
                        }
                        if ($sectionDiff.PackagesFailedChange -ne 0) {
                            $report += "- **Packages failed changed:** $($sectionDiff.PackagesFailedBefore) → $($sectionDiff.PackagesFailedAfter)"
                        }
                    }

                    $report += ""
                }
            }
        }
        else {
            # Text format
            $report += "=== Update Comparison Report ==="
            $report += "Period: $($DiffObject.Timestamp1) → $($DiffObject.Timestamp2)"
            $report += ""
            $report += "Overall Metrics Changes:"
            $report += "  Total Duration: $($DiffObject.MetricsDiff.TotalDuration.Before)s → $($DiffObject.MetricsDiff.TotalDuration.After)s ($(if ($DiffObject.MetricsDiff.TotalDuration.Change -gt 0) {'+' + $DiffObject.MetricsDiff.TotalDuration.Change} else {$DiffObject.MetricsDiff.TotalDuration.Change})s, $($DiffObject.MetricsDiff.TotalDuration.PercentChange)%)"
            $report += "  Packages Updated: $($DiffObject.MetricsDiff.TotalPackagesUpdated.Before) → $($DiffObject.MetricsDiff.TotalPackagesUpdated.After) ($(if ($DiffObject.MetricsDiff.TotalPackagesUpdated.Change -gt 0) {'+' + $DiffObject.MetricsDiff.TotalPackagesUpdated.Change} else {$DiffObject.MetricsDiff.TotalPackagesUpdated.Change}))"
            $report += "  Packages Failed: $($DiffObject.MetricsDiff.TotalPackagesFailed.Before) → $($DiffObject.MetricsDiff.TotalPackagesFailed.After) ($(if ($DiffObject.MetricsDiff.TotalPackagesFailed.Change -gt 0) {'+' + $DiffObject.MetricsDiff.TotalPackagesFailed.Change} else {$DiffObject.MetricsDiff.TotalPackagesFailed.Change}))"
            $report += ""
            $report += "Section Changes:"

            foreach ($sectionDiff in $DiffObject.SectionsDiff) {
                if ($sectionDiff.StatusChanged -or $sectionDiff.DurationChanged) {
                    $report += "  [$($sectionDiff.Name)]"

                    if ($sectionDiff.Change -eq "Added") {
                        $report += "    Status: Added (new section)"
                    }
                    elseif ($sectionDiff.Change -eq "Removed") {
                        $report += "    Status: Removed"
                    }
                    else {
                        if ($sectionDiff.StatusChanged) {
                            $report += "    Status changed: $($sectionDiff.StatusBefore) → $($sectionDiff.StatusAfter)"
                        }
                        if ($sectionDiff.DurationChanged) {
                            $durationChange = [math]::Round($sectionDiff.DurationChange, 2)
                            $durationChangeStr = if ($durationChange -gt 0) { "+$durationChange" } else { "$durationChange" }
                            $report += "    Duration changed: $($sectionDiff.DurationBefore)s → $($sectionDiff.DurationAfter)s ($durationChangeStr s)"
                        }
                    }

                    $report += ""
                }
            }
        }

        return ($report -join "`n")
    }
}

# ========== Helper Functions ==========

<#
.SYNOPSIS
Oblicza overall metrics z summary data.
#>
function Get-OverallMetrics {
    [CmdletBinding()]
    param([hashtable]$Data)

    $metrics = @{
        TotalDuration = 0.0
        TotalPackagesUpdated = 0
        TotalPackagesFailed = 0
    }

    foreach ($result in $Data.Results) {
        if ($result.DurationS) {
            $metrics.TotalDuration += [double]$result.DurationS
        }
        if ($result.Counts) {
            $metrics.TotalPackagesUpdated += [int]$result.Counts.Updated
            $metrics.TotalPackagesFailed += [int]$result.Counts.Failed
        }
    }

    return $metrics
}

<#
.SYNOPSIS
Porównuje dwie listy pakietów.
#>
function Compare-PackageLists {
    [CmdletBinding()]
    param($Packages1, $Packages2)

    $diff = @{
        Added = @()
        Removed = @()
        Updated = @()
    }

    if (-not $Packages1) { $Packages1 = @() }
    if (-not $Packages2) { $Packages2 = @() }

    # Build maps
    $map1 = @{}
    foreach ($pkg in $Packages1) {
        $map1[$pkg.Name] = $pkg
    }

    $map2 = @{}
    foreach ($pkg in $Packages2) {
        $map2[$pkg.Name] = $pkg
    }

    # Find Added
    foreach ($name in $map2.Keys) {
        if (-not $map1.ContainsKey($name)) {
            $diff.Added += $name
        }
    }

    # Find Removed
    foreach ($name in $map1.Keys) {
        if (-not $map2.ContainsKey($name)) {
            $diff.Removed += $name
        }
    }

    # Find Updated (version changed)
    foreach ($name in $map1.Keys) {
        if ($map2.ContainsKey($name)) {
            $pkg1 = $map1[$name]
            $pkg2 = $map2[$name]

            if ($pkg1.VersionAfter -ne $pkg2.VersionAfter) {
                $diff.Updated += @{
                    Name = $name
                    VersionBefore = $pkg1.VersionAfter
                    VersionAfter = $pkg2.VersionAfter
                }
            }
        }
    }

    return $diff
}

<#
.SYNOPSIS
Określa kierunek trendu (rosnący/spadający/stabilny).
#>
function Get-TrendDirection {
    [CmdletBinding()]
    param([array]$Values)

    if ($Values.Count -lt 3) { return "Insufficient data" }

    # Simple linear regression slope
    $n = $Values.Count
    $x = 1..$n
    $y = $Values

    $sumX = ($x | Measure-Object -Sum).Sum
    $sumY = ($y | Measure-Object -Sum).Sum
    $sumXY = 0
    $sumX2 = 0

    for ($i = 0; $i -lt $n; $i++) {
        $sumXY += $x[$i] * $y[$i]
        $sumX2 += $x[$i] * $x[$i]
    }

    $slope = ($n * $sumXY - $sumX * $sumY) / ($n * $sumX2 - $sumX * $sumX)

    if ($slope -gt 0.05) { return "Increasing" }
    elseif ($slope -lt -0.05) { return "Decreasing" }
    else { return "Stable" }
}

<#
.SYNOPSIS
Wykrywa anomalie (outliers) w serii wartości.
#>
function Find-Anomalies {
    [CmdletBinding()]
    param(
        [array]$Values,
        [double]$Threshold = 2.0
    )

    if ($Values.Count -lt 3) { return @() }

    $mean = ($Values | Measure-Object -Average).Average
    $stdDev = [math]::Sqrt((($Values | ForEach-Object { ($_ - $mean) * ($_ - $mean) }) | Measure-Object -Average).Average)

    $anomalies = @()

    for ($i = 0; $i -lt $Values.Count; $i++) {
        $zScore = if ($stdDev -gt 0) { ($Values[$i] - $mean) / $stdDev } else { 0 }

        if ([math]::Abs($zScore) -gt $Threshold) {
            $anomalies += @{
                Index = $i
                Value = $Values[$i]
                ZScore = [math]::Round($zScore, 2)
            }
        }
    }

    return $anomalies
}

<#
.SYNOPSIS
Konwertuje PSCustomObject do hashtable.
#>
function Convert-PSObjectToHashtable {
    [CmdletBinding()]
    param($InputObject)

    if ($null -eq $InputObject) { return $null }

    if ($InputObject -is [System.Collections.IDictionary]) {
        $hash = @{}
        foreach ($key in $InputObject.Keys) {
            $hash[$key] = Convert-PSObjectToHashtable $InputObject[$key]
        }
        return $hash
    }

    if ($InputObject -is [System.Collections.IEnumerable] -and $InputObject -isnot [string]) {
        $collection = @()
        foreach ($item in $InputObject) {
            $collection += Convert-PSObjectToHashtable $item
        }
        return $collection
    }

    if ($InputObject -is [psobject]) {
        $hash = @{}
        foreach ($property in $InputObject.PSObject.Properties) {
            $hash[$property.Name] = Convert-PSObjectToHashtable $property.Value
        }
        return $hash
    }

    return $InputObject
}

# Initialize on module load
Initialize-ComparisonEngine

# Export public functions
Export-ModuleMember -Function @(
    'Initialize-ComparisonEngine',
    'Compare-UpdateRuns',
    'Get-UpdateTrends',
    'Show-ChangeReport'
)
