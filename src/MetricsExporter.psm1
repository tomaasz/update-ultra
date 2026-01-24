# MetricsExporter.psm1
# Moduł do eksportu metryk aktualizacji do systemów monitoringu

<#
.SYNOPSIS
Moduł do eksportu metryk z aktualizacji do InfluxDB, Prometheus i custom endpoints.

.DESCRIPTION
MetricsExporter umożliwia wysyłanie metryk aktualizacji do:
- InfluxDB (Line Protocol)
- Prometheus Pushgateway
- Custom HTTP endpoints (JSON/plain text)

Metryki obejmują:
- Czas wykonania per sekcja
- Liczba zaktualizowanych/failed pakietów
- Status sekcji (success/fail)
- Całkowity czas aktualizacji

.NOTES
Author: update-ultra team
Version: 5.2.0
Requires: PowerShell 5.1+
#>

#Requires -Version 5.1

<#
.SYNOPSIS
Eksportuje metryki do InfluxDB.

.DESCRIPTION
Wysyła metryki w formacie InfluxDB Line Protocol.

.PARAMETER SummaryData
Hashtable lub PSCustomObject z danymi summary.

.PARAMETER InfluxDbUrl
URL InfluxDB API (np. "http://localhost:8086").

.PARAMETER Database
Nazwa bazy danych InfluxDB.

.PARAMETER Measurement
Nazwa measurement (domyślnie: "update_ultra").

.PARAMETER Username
Username do autoryzacji (opcjonalnie).

.PARAMETER Password
Password do autoryzacji (opcjonalnie).

.PARAMETER Tags
Dodatkowe tagi do metryk (hashtable).

.EXAMPLE
Export-MetricsToInfluxDB -SummaryData $summary `
    -InfluxDbUrl "http://localhost:8086" -Database "updates"

.EXAMPLE
$tags = @{ Environment = "production"; Host = $env:COMPUTERNAME }
Export-MetricsToInfluxDB -SummaryData $summary `
    -InfluxDbUrl "http://influx.example.com:8086" `
    -Database "metrics" -Tags $tags `
    -Username "admin" -Password "secret"

.OUTPUTS
PSCustomObject - Wynik eksportu (Success, Response).
#>
function Export-MetricsToInfluxDB {
    [CmdletBinding()]
    [OutputType([PSCustomObject])]
    param(
        [Parameter(Mandatory, ValueFromPipeline)]
        [ValidateNotNull()]
        $SummaryData,

        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string]$InfluxDbUrl,

        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string]$Database,

        [Parameter()]
        [string]$Measurement = "update_ultra",

        [Parameter()]
        [string]$Username,

        [Parameter()]
        [string]$Password,

        [Parameter()]
        [hashtable]$Tags = @{}
    )

    begin {
        Write-Verbose "Starting InfluxDB metrics export..."
    }

    process {
        try {
            # Konwertuj dane
            if ($SummaryData -is [PSCustomObject]) {
                $data = Convert-PSObjectToHashtable -InputObject $SummaryData
            } else {
                $data = $SummaryData
            }

            # Generuj Line Protocol
            $lineProtocol = Build-InfluxDBLineProtocol -Data $data -Measurement $Measurement -Tags $Tags

            # Buduj URL
            $writeUrl = "$($InfluxDbUrl.TrimEnd('/'))/write?db=$Database"

            # Przygotuj headers
            $headers = @{
                "Content-Type" = "text/plain; charset=utf-8"
            }

            # Basic Auth jeśli podano credentials
            if ($Username -and $Password) {
                $base64Auth = [Convert]::ToBase64String([Text.Encoding]::ASCII.GetBytes("${Username}:${Password}"))
                $headers["Authorization"] = "Basic $base64Auth"
            }

            # Wyślij do InfluxDB
            $response = Invoke-RestMethod -Uri $writeUrl -Method Post -Body $lineProtocol -Headers $headers -ErrorAction Stop

            Write-Verbose "Metrics exported to InfluxDB successfully"

            return [PSCustomObject]@{
                Success = $true
                Backend = "InfluxDB"
                Url = $writeUrl
                MetricsCount = ($lineProtocol -split "`n").Count
                Response = $response
            }
        }
        catch {
            Write-Error "Failed to export metrics to InfluxDB: $($_.Exception.Message)"
            return [PSCustomObject]@{
                Success = $false
                Backend = "InfluxDB"
                Error = $_.Exception.Message
            }
        }
    }
}

<#
.SYNOPSIS
Eksportuje metryki do Prometheus Pushgateway.

.DESCRIPTION
Wysyła metryki w formacie Prometheus text format.

.PARAMETER SummaryData
Hashtable lub PSCustomObject z danymi summary.

.PARAMETER PushgatewayUrl
URL Prometheus Pushgateway (np. "http://localhost:9091").

.PARAMETER Job
Nazwa job (domyślnie: "update_ultra").

.PARAMETER Instance
Nazwa instance (domyślnie: hostname).

.PARAMETER Labels
Dodatkowe labels do metryk (hashtable).

.EXAMPLE
Export-MetricsToPrometheus -SummaryData $summary `
    -PushgatewayUrl "http://localhost:9091"

.EXAMPLE
Export-MetricsToPrometheus -SummaryData $summary `
    -PushgatewayUrl "http://pushgateway.example.com:9091" `
    -Job "windows_updates" -Instance $env:COMPUTERNAME

.OUTPUTS
PSCustomObject - Wynik eksportu.
#>
function Export-MetricsToPrometheus {
    [CmdletBinding()]
    [OutputType([PSCustomObject])]
    param(
        [Parameter(Mandatory, ValueFromPipeline)]
        [ValidateNotNull()]
        $SummaryData,

        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string]$PushgatewayUrl,

        [Parameter()]
        [string]$Job = "update_ultra",

        [Parameter()]
        [string]$Instance = $env:COMPUTERNAME,

        [Parameter()]
        [hashtable]$Labels = @{}
    )

    begin {
        Write-Verbose "Starting Prometheus Pushgateway metrics export..."
    }

    process {
        try {
            # Konwertuj dane
            if ($SummaryData -is [PSCustomObject]) {
                $data = Convert-PSObjectToHashtable -InputObject $SummaryData
            } else {
                $data = $SummaryData
            }

            # Generuj Prometheus format
            $prometheusFormat = Build-PrometheusFormat -Data $data -Labels $Labels

            # Buduj URL
            $pushUrl = "$($PushgatewayUrl.TrimEnd('/'))/metrics/job/$Job/instance/$Instance"

            # Przygotuj headers
            $headers = @{
                "Content-Type" = "text/plain; charset=utf-8"
            }

            # Wyślij do Pushgateway
            $response = Invoke-RestMethod -Uri $pushUrl -Method Post -Body $prometheusFormat -Headers $headers -ErrorAction Stop

            Write-Verbose "Metrics pushed to Prometheus Pushgateway successfully"

            return [PSCustomObject]@{
                Success = $true
                Backend = "Prometheus"
                Url = $pushUrl
                MetricsCount = ($prometheusFormat -split "`n").Count
                Response = $response
            }
        }
        catch {
            Write-Error "Failed to export metrics to Prometheus: $($_.Exception.Message)"
            return [PSCustomObject]@{
                Success = $false
                Backend = "Prometheus"
                Error = $_.Exception.Message
            }
        }
    }
}

<#
.SYNOPSIS
Eksportuje metryki do custom HTTP endpoint.

.DESCRIPTION
Wysyła metryki w formacie JSON lub plain text do custom endpoint.

.PARAMETER SummaryData
Hashtable lub PSCustomObject z danymi summary.

.PARAMETER Endpoint
URL custom endpoint.

.PARAMETER Format
Format danych: "JSON" lub "PlainText" (domyślnie: "JSON").

.PARAMETER Method
HTTP method (domyślnie: "POST").

.PARAMETER Headers
Custom HTTP headers (hashtable).

.EXAMPLE
Export-MetricsToCustomEndpoint -SummaryData $summary `
    -Endpoint "https://api.example.com/metrics"

.EXAMPLE
$headers = @{ "Authorization" = "Bearer token123" }
Export-MetricsToCustomEndpoint -SummaryData $summary `
    -Endpoint "https://metrics.example.com/push" `
    -Format "JSON" -Headers $headers

.OUTPUTS
PSCustomObject - Wynik eksportu.
#>
function Export-MetricsToCustomEndpoint {
    [CmdletBinding()]
    [OutputType([PSCustomObject])]
    param(
        [Parameter(Mandatory, ValueFromPipeline)]
        [ValidateNotNull()]
        $SummaryData,

        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string]$Endpoint,

        [Parameter()]
        [ValidateSet('JSON', 'PlainText')]
        [string]$Format = 'JSON',

        [Parameter()]
        [ValidateSet('POST', 'PUT')]
        [string]$Method = 'POST',

        [Parameter()]
        [hashtable]$Headers = @{}
    )

    begin {
        Write-Verbose "Starting custom endpoint metrics export..."
    }

    process {
        try {
            # Konwertuj dane
            if ($SummaryData -is [PSCustomObject]) {
                $data = Convert-PSObjectToHashtable -InputObject $SummaryData
            } else {
                $data = $SummaryData
            }

            # Przygotuj body
            $body = $null
            $contentType = $null

            if ($Format -eq 'JSON') {
                $metricsObject = Build-MetricsObject -Data $data
                $body = $metricsObject | ConvertTo-Json -Depth 10
                $contentType = "application/json; charset=utf-8"
            }
            else {
                # PlainText format
                $body = Build-PlainTextMetrics -Data $data
                $contentType = "text/plain; charset=utf-8"
            }

            # Przygotuj headers
            $requestHeaders = @{
                "Content-Type" = $contentType
            }

            # Dodaj custom headers
            foreach ($key in $Headers.Keys) {
                $requestHeaders[$key] = $Headers[$key]
            }

            # Wyślij request
            $response = Invoke-RestMethod -Uri $Endpoint -Method $Method -Body $body -Headers $requestHeaders -ErrorAction Stop

            Write-Verbose "Metrics sent to custom endpoint successfully"

            return [PSCustomObject]@{
                Success = $true
                Backend = "CustomEndpoint"
                Url = $Endpoint
                Format = $Format
                Response = $response
            }
        }
        catch {
            Write-Error "Failed to export metrics to custom endpoint: $($_.Exception.Message)"
            return [PSCustomObject]@{
                Success = $false
                Backend = "CustomEndpoint"
                Error = $_.Exception.Message
            }
        }
    }
}

<#
.SYNOPSIS
Buduje Line Protocol dla InfluxDB.

.PARAMETER Data
Hashtable z danymi summary.

.PARAMETER Measurement
Nazwa measurement.

.PARAMETER Tags
Dodatkowe tagi.

.OUTPUTS
String - InfluxDB Line Protocol.
#>
function Build-InfluxDBLineProtocol {
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory)]
        [hashtable]$Data,

        [string]$Measurement,
        [hashtable]$Tags
    )

    $lines = @()
    $timestamp = [DateTimeOffset]::UtcNow.ToUnixTimeSeconds()

    # Base tags
    $baseTags = "host=$env:COMPUTERNAME"
    foreach ($key in $Tags.Keys) {
        $baseTags += ",$key=$($Tags[$key])"
    }

    # Overall metrics
    $totalDuration = 0.0
    $totalUpdated = 0
    $totalFailed = 0

    foreach ($result in $Data.Results) {
        $section = $result.Name
        $status = $result.Status
        $duration = if ($result.DurationS) { [double]$result.DurationS } else { 0.0 }
        $updated = if ($result.Counts) { [int]$result.Counts.Updated } else { 0 }
        $failed = if ($result.Counts) { [int]$result.Counts.Failed } else { 0 }

        $totalDuration += $duration
        $totalUpdated += $updated
        $totalFailed += $failed

        # Per-section metrics
        $sectionTags = "$baseTags,section=$section"
        $lines += "$Measurement,$sectionTags duration_seconds=$duration,packages_updated=$updated,packages_failed=$failed,status_ok=$(if ($status -eq 'OK') {1} else {0}),status_fail=$(if ($status -eq 'FAIL') {1} else {0}) $timestamp"
    }

    # Overall metrics
    $lines += "$Measurement,$baseTags total_duration_seconds=$totalDuration,total_packages_updated=$totalUpdated,total_packages_failed=$totalFailed $timestamp"

    return ($lines -join "`n")
}

<#
.SYNOPSIS
Buduje format Prometheus.

.PARAMETER Data
Hashtable z danymi summary.

.PARAMETER Labels
Dodatkowe labels.

.OUTPUTS
String - Prometheus text format.
#>
function Build-PrometheusFormat {
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory)]
        [hashtable]$Data,

        [hashtable]$Labels
    )

    $lines = @()

    # Base labels
    $baseLabels = "host=`"$env:COMPUTERNAME`""
    foreach ($key in $Labels.Keys) {
        $baseLabels += ",$key=`"$($Labels[$key])`""
    }

    # Overall metrics
    $totalDuration = 0.0
    $totalUpdated = 0
    $totalFailed = 0

    # HELP comments
    $lines += "# HELP update_ultra_duration_seconds Duration of update in seconds"
    $lines += "# TYPE update_ultra_duration_seconds gauge"

    $lines += "# HELP update_ultra_packages_updated_total Total packages updated"
    $lines += "# TYPE update_ultra_packages_updated_total counter"

    $lines += "# HELP update_ultra_packages_failed_total Total packages failed"
    $lines += "# TYPE update_ultra_packages_failed_total counter"

    $lines += "# HELP update_ultra_status_success Status of section (1=success, 0=fail)"
    $lines += "# TYPE update_ultra_status_success gauge"

    foreach ($result in $Data.Results) {
        $section = $result.Name
        $status = $result.Status
        $duration = if ($result.DurationS) { [double]$result.DurationS } else { 0.0 }
        $updated = if ($result.Counts) { [int]$result.Counts.Updated } else { 0 }
        $failed = if ($result.Counts) { [int]$result.Counts.Failed } else { 0 }

        $totalDuration += $duration
        $totalUpdated += $updated
        $totalFailed += $failed

        # Per-section metrics
        $sectionLabels = "$baseLabels,section=`"$section`""
        $lines += "update_ultra_duration_seconds{$sectionLabels} $duration"
        $lines += "update_ultra_packages_updated_total{$sectionLabels} $updated"
        $lines += "update_ultra_packages_failed_total{$sectionLabels} $failed"
        $lines += "update_ultra_status_success{$sectionLabels} $(if ($status -eq 'OK') {1} else {0})"
    }

    # Overall metrics (section="total")
    $totalLabels = "$baseLabels,section=`"total`""
    $lines += "update_ultra_duration_seconds{$totalLabels} $totalDuration"
    $lines += "update_ultra_packages_updated_total{$totalLabels} $totalUpdated"
    $lines += "update_ultra_packages_failed_total{$totalLabels} $totalFailed"

    return ($lines -join "`n")
}

<#
.SYNOPSIS
Buduje obiekt metryk dla JSON export.

.PARAMETER Data
Hashtable z danymi summary.

.OUTPUTS
PSCustomObject - Obiekt metryk.
#>
function Build-MetricsObject {
    [CmdletBinding()]
    [OutputType([PSCustomObject])]
    param(
        [Parameter(Mandatory)]
        [hashtable]$Data
    )

    $metrics = [ordered]@{
        Timestamp = (Get-Date).ToString("o")
        Host = $env:COMPUTERNAME
        TotalDuration = 0.0
        TotalPackagesUpdated = 0
        TotalPackagesFailed = 0
        Sections = @()
    }

    foreach ($result in $Data.Results) {
        $duration = if ($result.DurationS) { [double]$result.DurationS } else { 0.0 }
        $updated = if ($result.Counts) { [int]$result.Counts.Updated } else { 0 }
        $failed = if ($result.Counts) { [int]$result.Counts.Failed } else { 0 }

        $metrics.TotalDuration += $duration
        $metrics.TotalPackagesUpdated += $updated
        $metrics.TotalPackagesFailed += $failed

        $metrics.Sections += [ordered]@{
            Name = $result.Name
            Status = $result.Status
            DurationSeconds = $duration
            PackagesUpdated = $updated
            PackagesFailed = $failed
        }
    }

    return [PSCustomObject]$metrics
}

<#
.SYNOPSIS
Buduje plain text metryki.

.PARAMETER Data
Hashtable z danymi summary.

.OUTPUTS
String - Plain text metrics.
#>
function Build-PlainTextMetrics {
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory)]
        [hashtable]$Data
    )

    $lines = @()
    $lines += "=== Update-Ultra Metrics ==="
    $lines += "Timestamp: $(Get-Date -Format 'o')"
    $lines += "Host: $env:COMPUTERNAME"
    $lines += ""

    $totalDuration = 0.0
    $totalUpdated = 0
    $totalFailed = 0

    foreach ($result in $Data.Results) {
        $duration = if ($result.DurationS) { [double]$result.DurationS } else { 0.0 }
        $updated = if ($result.Counts) { [int]$result.Counts.Updated } else { 0 }
        $failed = if ($result.Counts) { [int]$result.Counts.Failed } else { 0 }

        $totalDuration += $duration
        $totalUpdated += $updated
        $totalFailed += $failed

        $lines += "[$($result.Name)] Status=$($result.Status), Duration=$([math]::Round($duration, 2))s, Updated=$updated, Failed=$failed"
    }

    $lines += ""
    $lines += "=== Totals ==="
    $lines += "Total Duration: $([math]::Round($totalDuration, 2))s"
    $lines += "Total Packages Updated: $totalUpdated"
    $lines += "Total Packages Failed: $totalFailed"

    return ($lines -join "`n")
}

<#
.SYNOPSIS
Konwertuje PSCustomObject do hashtable.

.PARAMETER InputObject
Obiekt do konwersji.

.OUTPUTS
Hashtable lub input object.
#>
function Convert-PSObjectToHashtable {
    [CmdletBinding()]
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
    'Export-MetricsToInfluxDB',
    'Export-MetricsToPrometheus',
    'Export-MetricsToCustomEndpoint'
)
