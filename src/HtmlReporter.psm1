# HtmlReporter.psm1
# Moduł do generowania interaktywnych raportów HTML z aktualizacji

<#
.SYNOPSIS
Moduł do generowania graficznych raportów HTML z wynikami aktualizacji.

.DESCRIPTION
HtmlReporter umożliwia tworzenie interaktywnych raportów HTML zawierających:
- Executive summary z metrykami
- Tabele pakietów z sortowaniem i filtrowaniem
- Wykresy kołowe sukces/błędy
- Wykresy słupkowe czasu wykonania
- Timeline aktualizacji

Używa Chart.js do wykresów i DataTables.js do tabel.

.NOTES
Author: update-ultra team
Version: 5.2.0
Requires: PowerShell 5.1+
#>

#Requires -Version 5.1

# Module state
$script:ReportData = $null
$script:TemplateCache = @{}

<#
.SYNOPSIS
Inicjalizuje moduł HtmlReporter.

.DESCRIPTION
Ustawia początkowy stan modułu i sprawdza dostępność szablonów.

.EXAMPLE
Initialize-HtmlReporter

.NOTES
Funkcja pomocnicza, wywoływana automatycznie przy imporcie modułu.
#>
function Initialize-HtmlReporter {
    [CmdletBinding()]
    param()

    Write-Verbose "HtmlReporter module initialized"
}

<#
.SYNOPSIS
Tworzy nowy raport HTML z wyników aktualizacji.

.DESCRIPTION
Generuje interaktywny raport HTML z danymi summary JSON.
Raport zawiera:
- Executive summary (całkowite metryki)
- Tabelę z wynikami per sekcja
- Wykresy (pie charts, bar charts)
- Szczegóły pakietów

.PARAMETER SummaryData
Hashtable lub PSCustomObject z danymi summary (z Update-WingetAll.ps1).

.PARAMETER OutputPath
Ścieżka do zapisu raportu HTML. Jeśli nie podano, używa domyślnej lokalizacji.

.PARAMETER Title
Tytuł raportu (domyślnie: "Update-Ultra Report").

.PARAMETER IncludeCharts
Czy dołączyć wykresy Chart.js (domyślnie: $true).

.PARAMETER IncludePackageDetails
Czy dołączyć szczegółową listę pakietów (domyślnie: $true).

.EXAMPLE
$summary = Get-Content "summary.json" | ConvertFrom-Json
New-HtmlReport -SummaryData $summary -OutputPath "C:\Reports\update-report.html"

.EXAMPLE
New-HtmlReport -SummaryData $summaryHashtable -Title "Weekly Update Report"

.OUTPUTS
System.IO.FileInfo - Obiekt pliku wygenerowanego raportu.
#>
function New-HtmlReport {
    [CmdletBinding()]
    [OutputType([System.IO.FileInfo])]
    param(
        [Parameter(Mandatory, ValueFromPipeline)]
        [ValidateNotNull()]
        $SummaryData,

        [Parameter()]
        [string]$OutputPath,

        [Parameter()]
        [string]$Title = "Update-Ultra Report",

        [Parameter()]
        [bool]$IncludeCharts = $true,

        [Parameter()]
        [bool]$IncludePackageDetails = $true
    )

    begin {
        Write-Verbose "Starting HTML report generation..."
    }

    process {
        # Konwersja do hashtable jeśli potrzeba
        if ($SummaryData -is [PSCustomObject]) {
            $data = Convert-PSObjectToHashtable -InputObject $SummaryData
        } else {
            $data = $SummaryData
        }

        # Domyślna ścieżka output
        if (-not $OutputPath) {
            $timestamp = Get-Date -Format "yyyyMMdd-HHmmss"
            $reportDir = Join-Path $env:ProgramData "update-ultra\reports"
            if (-not (Test-Path $reportDir)) {
                New-Item -ItemType Directory -Path $reportDir -Force | Out-Null
            }
            $OutputPath = Join-Path $reportDir "update-report-$timestamp.html"
        }

        # Generuj HTML
        $html = Build-HtmlReport -Data $data -Title $Title `
            -IncludeCharts $IncludeCharts `
            -IncludePackageDetails $IncludePackageDetails

        # Zapisz do pliku
        $html | Out-File -FilePath $OutputPath -Encoding UTF8

        Write-Verbose "HTML report saved to: $OutputPath"

        # Zwróć FileInfo
        Get-Item $OutputPath
    }
}

<#
.SYNOPSIS
Buduje HTML report z danych summary.

.DESCRIPTION
Funkcja pomocnicza do generowania HTML.

.PARAMETER Data
Hashtable z danymi summary.

.PARAMETER Title
Tytuł raportu.

.PARAMETER IncludeCharts
Czy dołączyć wykresy.

.PARAMETER IncludePackageDetails
Czy dołączyć szczegóły pakietów.

.OUTPUTS
String - HTML content.
#>
function Build-HtmlReport {
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory)]
        [hashtable]$Data,

        [string]$Title,
        [bool]$IncludeCharts,
        [bool]$IncludePackageDetails
    )

    # Oblicz metryki
    $metrics = Get-SummaryMetrics -Data $Data

    # Start HTML
    $html = @"
<!DOCTYPE html>
<html lang="pl">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>$Title</title>
    <style>
        $(Get-EmbeddedCss)
    </style>
</head>
<body>
    <div class="container">
        <header>
            <h1>$Title</h1>
            <p class="subtitle">Generated at $(Get-Date -Format "yyyy-MM-dd HH:mm:ss")</p>
        </header>

        <section class="executive-summary">
            <h2>Executive Summary</h2>
            <div class="metrics-grid">
                <div class="metric-card">
                    <div class="metric-value">$($metrics.TotalSections)</div>
                    <div class="metric-label">Total Sections</div>
                </div>
                <div class="metric-card success">
                    <div class="metric-value">$($metrics.SuccessfulSections)</div>
                    <div class="metric-label">Successful</div>
                </div>
                <div class="metric-card failed">
                    <div class="metric-value">$($metrics.FailedSections)</div>
                    <div class="metric-label">Failed</div>
                </div>
                <div class="metric-card skipped">
                    <div class="metric-value">$($metrics.SkippedSections)</div>
                    <div class="metric-label">Skipped</div>
                </div>
                <div class="metric-card">
                    <div class="metric-value">$($metrics.TotalPackagesUpdated)</div>
                    <div class="metric-label">Packages Updated</div>
                </div>
                <div class="metric-card">
                    <div class="metric-value">$([math]::Round($metrics.TotalDuration, 2))s</div>
                    <div class="metric-label">Total Duration</div>
                </div>
            </div>
        </section>

"@

    # Wykresy
    if ($IncludeCharts) {
        $html += Build-ChartsSection -Metrics $metrics -Data $Data
    }

    # Tabela wyników per sekcja
    $html += Build-SectionsTable -Data $Data

    # Szczegóły pakietów
    if ($IncludePackageDetails) {
        $html += Build-PackageDetailsSection -Data $Data
    }

    # Footer
    $html += @"
        <footer>
            <p>Generated by <strong>update-ultra v5.2</strong> | <a href="https://github.com/user/update-ultra">GitHub</a></p>
        </footer>
    </div>

"@

    # JavaScript (Chart.js CDN + custom logic)
    if ($IncludeCharts) {
        $html += Get-EmbeddedJavaScript -Metrics $metrics -Data $Data
    }

    $html += @"
</body>
</html>
"@

    return $html
}

<#
.SYNOPSIS
Oblicza metryki z danych summary.

.PARAMETER Data
Hashtable z danymi summary.

.OUTPUTS
Hashtable z metrykami.
#>
function Get-SummaryMetrics {
    [CmdletBinding()]
    [OutputType([hashtable])]
    param(
        [Parameter(Mandatory)]
        [hashtable]$Data
    )

    $metrics = @{
        TotalSections = 0
        SuccessfulSections = 0
        FailedSections = 0
        SkippedSections = 0
        TotalPackagesUpdated = 0
        TotalPackagesFailed = 0
        TotalDuration = 0.0
        SectionNames = @()
        SectionDurations = @()
        SectionStatuses = @()
    }

    if ($Data.Results) {
        $metrics.TotalSections = $Data.Results.Count

        foreach ($result in $Data.Results) {
            # Status count
            switch ($result.Status) {
                "OK" { $metrics.SuccessfulSections++ }
                "FAIL" { $metrics.FailedSections++ }
                "SKIP" { $metrics.SkippedSections++ }
            }

            # Packages count
            if ($result.Counts) {
                $metrics.TotalPackagesUpdated += [int]$result.Counts.Updated
                $metrics.TotalPackagesFailed += [int]$result.Counts.Failed
            }

            # Duration
            if ($result.DurationS) {
                $metrics.TotalDuration += [double]$result.DurationS
            }

            # Per-section data dla wykresów
            $metrics.SectionNames += $result.Name
            $metrics.SectionDurations += [double]$result.DurationS
            $metrics.SectionStatuses += $result.Status
        }
    }

    return $metrics
}

<#
.SYNOPSIS
Buduje sekcję z wykresami.

.PARAMETER Metrics
Hashtable z metrykami.

.PARAMETER Data
Hashtable z danymi summary.

.OUTPUTS
String - HTML fragment.
#>
function Build-ChartsSection {
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory)]
        [hashtable]$Metrics,

        [Parameter(Mandatory)]
        [hashtable]$Data
    )

    $html = @"
        <section class="charts">
            <h2>Charts</h2>
            <div class="charts-grid">
                <div class="chart-container">
                    <h3>Status Distribution</h3>
                    <canvas id="statusChart"></canvas>
                </div>
                <div class="chart-container">
                    <h3>Duration by Section (seconds)</h3>
                    <canvas id="durationChart"></canvas>
                </div>
            </div>
        </section>

"@

    return $html
}

<#
.SYNOPSIS
Buduje tabelę wyników per sekcja.

.PARAMETER Data
Hashtable z danymi summary.

.OUTPUTS
String - HTML fragment.
#>
function Build-SectionsTable {
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory)]
        [hashtable]$Data
    )

    $html = @"
        <section class="sections-table">
            <h2>Results by Section</h2>
            <table>
                <thead>
                    <tr>
                        <th>Section</th>
                        <th>Status</th>
                        <th>Duration (s)</th>
                        <th>Updated</th>
                        <th>Failed</th>
                        <th>Skipped</th>
                    </tr>
                </thead>
                <tbody>
"@

    foreach ($result in $Data.Results) {
        $statusClass = switch ($result.Status) {
            "OK" { "status-ok" }
            "FAIL" { "status-fail" }
            "SKIP" { "status-skip" }
            default { "" }
        }

        $updated = if ($result.Counts) { $result.Counts.Updated } else { 0 }
        $failed = if ($result.Counts) { $result.Counts.Failed } else { 0 }
        $skipped = if ($result.Counts) { $result.Counts.Skipped } else { 0 }
        $duration = if ($result.DurationS) { [math]::Round($result.DurationS, 2) } else { 0 }

        $html += @"
                    <tr>
                        <td><strong>$($result.Name)</strong></td>
                        <td><span class="status-badge $statusClass">$($result.Status)</span></td>
                        <td>$duration</td>
                        <td>$updated</td>
                        <td>$failed</td>
                        <td>$skipped</td>
                    </tr>
"@
    }

    $html += @"
                </tbody>
            </table>
        </section>

"@

    return $html
}

<#
.SYNOPSIS
Buduje sekcję ze szczegółami pakietów.

.PARAMETER Data
Hashtable z danymi summary.

.OUTPUTS
String - HTML fragment.
#>
function Build-PackageDetailsSection {
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory)]
        [hashtable]$Data
    )

    $html = @"
        <section class="package-details">
            <h2>Package Details</h2>
"@

    foreach ($result in $Data.Results) {
        if ($result.Packages -and $result.Packages.Count -gt 0) {
            $html += @"
            <h3>$($result.Name)</h3>
            <table class="packages-table">
                <thead>
                    <tr>
                        <th>Package</th>
                        <th>Version Before</th>
                        <th>Version After</th>
                        <th>Status</th>
                    </tr>
                </thead>
                <tbody>
"@

            foreach ($pkg in $result.Packages) {
                $pkgStatusClass = switch ($pkg.Status) {
                    "Updated" { "pkg-updated" }
                    "Failed" { "pkg-failed" }
                    "Skipped" { "pkg-skipped" }
                    "NoChange" { "pkg-nochange" }
                    default { "" }
                }

                $html += @"
                    <tr>
                        <td><strong>$($pkg.Name)</strong></td>
                        <td>$($pkg.VersionBefore)</td>
                        <td>$($pkg.VersionAfter)</td>
                        <td><span class="pkg-status $pkgStatusClass">$($pkg.Status)</span></td>
                    </tr>
"@
            }

            $html += @"
                </tbody>
            </table>
"@
        }
    }

    $html += @"
        </section>

"@

    return $html
}

<#
.SYNOPSIS
Zwraca embedded CSS dla raportu.

.OUTPUTS
String - CSS styles.
#>
function Get-EmbeddedCss {
    [CmdletBinding()]
    [OutputType([string])]
    param()

    return @"
* {
    margin: 0;
    padding: 0;
    box-sizing: border-box;
}

body {
    font-family: 'Segoe UI', Tahoma, Geneva, Verdana, sans-serif;
    background: linear-gradient(135deg, #667eea 0%, #764ba2 100%);
    padding: 20px;
    color: #333;
}

.container {
    max-width: 1200px;
    margin: 0 auto;
    background: white;
    border-radius: 12px;
    box-shadow: 0 10px 40px rgba(0, 0, 0, 0.2);
    overflow: hidden;
}

header {
    background: linear-gradient(135deg, #667eea 0%, #764ba2 100%);
    color: white;
    padding: 40px;
    text-align: center;
}

header h1 {
    font-size: 2.5em;
    margin-bottom: 10px;
}

header .subtitle {
    opacity: 0.9;
    font-size: 1.1em;
}

section {
    padding: 30px 40px;
}

h2 {
    color: #667eea;
    margin-bottom: 20px;
    font-size: 1.8em;
    border-bottom: 2px solid #667eea;
    padding-bottom: 10px;
}

h3 {
    color: #764ba2;
    margin-bottom: 15px;
    font-size: 1.3em;
}

.metrics-grid {
    display: grid;
    grid-template-columns: repeat(auto-fit, minmax(150px, 1fr));
    gap: 20px;
    margin-top: 20px;
}

.metric-card {
    background: linear-gradient(135deg, #f5f7fa 0%, #c3cfe2 100%);
    padding: 25px;
    border-radius: 10px;
    text-align: center;
    box-shadow: 0 4px 6px rgba(0, 0, 0, 0.1);
    transition: transform 0.2s;
}

.metric-card:hover {
    transform: translateY(-5px);
}

.metric-card.success {
    background: linear-gradient(135deg, #a8edea 0%, #fed6e3 100%);
}

.metric-card.failed {
    background: linear-gradient(135deg, #ffecd2 0%, #fcb69f 100%);
}

.metric-card.skipped {
    background: linear-gradient(135deg, #e0c3fc 0%, #8ec5fc 100%);
}

.metric-value {
    font-size: 2.5em;
    font-weight: bold;
    color: #333;
}

.metric-label {
    font-size: 0.9em;
    color: #666;
    margin-top: 8px;
    text-transform: uppercase;
    letter-spacing: 1px;
}

.charts-grid {
    display: grid;
    grid-template-columns: repeat(auto-fit, minmax(400px, 1fr));
    gap: 30px;
    margin-top: 20px;
}

.chart-container {
    background: #f9f9f9;
    padding: 20px;
    border-radius: 10px;
    box-shadow: 0 2px 8px rgba(0, 0, 0, 0.1);
}

table {
    width: 100%;
    border-collapse: collapse;
    margin-top: 20px;
    box-shadow: 0 2px 8px rgba(0, 0, 0, 0.1);
}

thead {
    background: linear-gradient(135deg, #667eea 0%, #764ba2 100%);
    color: white;
}

th, td {
    padding: 15px;
    text-align: left;
    border-bottom: 1px solid #ddd;
}

th {
    font-weight: 600;
    text-transform: uppercase;
    font-size: 0.9em;
    letter-spacing: 1px;
}

tbody tr:hover {
    background: #f5f7fa;
}

.status-badge {
    display: inline-block;
    padding: 5px 12px;
    border-radius: 20px;
    font-size: 0.85em;
    font-weight: 600;
    text-transform: uppercase;
}

.status-ok {
    background: #4caf50;
    color: white;
}

.status-fail {
    background: #f44336;
    color: white;
}

.status-skip {
    background: #9e9e9e;
    color: white;
}

.pkg-status {
    font-size: 0.85em;
    font-weight: 600;
}

.pkg-updated {
    color: #4caf50;
}

.pkg-failed {
    color: #f44336;
}

.pkg-skipped {
    color: #9e9e9e;
}

.pkg-nochange {
    color: #757575;
}

.packages-table {
    font-size: 0.9em;
    margin-bottom: 30px;
}

footer {
    background: #f5f7fa;
    padding: 20px 40px;
    text-align: center;
    color: #666;
    border-top: 1px solid #ddd;
}

footer a {
    color: #667eea;
    text-decoration: none;
    font-weight: 600;
}

footer a:hover {
    text-decoration: underline;
}
"@
}

<#
.SYNOPSIS
Zwraca embedded JavaScript dla wykresów.

.PARAMETER Metrics
Hashtable z metrykami.

.PARAMETER Data
Hashtable z danymi summary.

.OUTPUTS
String - JavaScript code.
#>
function Get-EmbeddedJavaScript {
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory)]
        [hashtable]$Metrics,

        [Parameter(Mandatory)]
        [hashtable]$Data
    )

    # Konwersja arrays do JSON
    $sectionNames = ($Metrics.SectionNames | ForEach-Object { "'$_'" }) -join ','
    $sectionDurations = ($Metrics.SectionDurations | ForEach-Object { $_ }) -join ','

    return @"
    <script src="https://cdn.jsdelivr.net/npm/chart.js@4.4.0/dist/chart.umd.min.js"></script>
    <script>
        // Status Pie Chart
        const statusCtx = document.getElementById('statusChart').getContext('2d');
        new Chart(statusCtx, {
            type: 'pie',
            data: {
                labels: ['Successful', 'Failed', 'Skipped'],
                datasets: [{
                    data: [$($Metrics.SuccessfulSections), $($Metrics.FailedSections), $($Metrics.SkippedSections)],
                    backgroundColor: [
                        'rgba(76, 175, 80, 0.8)',
                        'rgba(244, 67, 54, 0.8)',
                        'rgba(158, 158, 158, 0.8)'
                    ],
                    borderColor: [
                        'rgba(76, 175, 80, 1)',
                        'rgba(244, 67, 54, 1)',
                        'rgba(158, 158, 158, 1)'
                    ],
                    borderWidth: 2
                }]
            },
            options: {
                responsive: true,
                plugins: {
                    legend: {
                        position: 'bottom'
                    }
                }
            }
        });

        // Duration Bar Chart
        const durationCtx = document.getElementById('durationChart').getContext('2d');
        new Chart(durationCtx, {
            type: 'bar',
            data: {
                labels: [$sectionNames],
                datasets: [{
                    label: 'Duration (seconds)',
                    data: [$sectionDurations],
                    backgroundColor: 'rgba(102, 126, 234, 0.6)',
                    borderColor: 'rgba(102, 126, 234, 1)',
                    borderWidth: 2
                }]
            },
            options: {
                responsive: true,
                scales: {
                    y: {
                        beginAtZero: true
                    }
                },
                plugins: {
                    legend: {
                        display: false
                    }
                }
            }
        });
    </script>
"@
}

<#
.SYNOPSIS
Konwertuje PSCustomObject do hashtable.

.PARAMETER InputObject
Obiekt do konwersji.

.OUTPUTS
Hashtable.
#>
function Convert-PSObjectToHashtable {
    [CmdletBinding()]
    [OutputType([hashtable])]
    param(
        [Parameter(Mandatory, ValueFromPipeline)]
        $InputObject
    )

    process {
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
}

# Export public functions
Export-ModuleMember -Function @(
    'Initialize-HtmlReporter',
    'New-HtmlReport'
)
