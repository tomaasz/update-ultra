# NotificationManager.psm1
# System powiadomień dla update-ultra - obsługa toast, email, webhook

<#
.SYNOPSIS
Moduł powiadomień dla update-ultra

.DESCRIPTION
Zapewnia powiadomienia przez różne kanały:
- Windows Toast Notifications (wymaga BurntToast)
- Email (SMTP)
- Webhook (HTTP POST do Slack, Discord, Teams, etc.)

Graceful degradation - brak BurntToast nie blokuje pozostałych funkcji.

.NOTES
Version: 1.0
Author: update-ultra team
Created: 2025-01-23
Dependencies:
- BurntToast (opcjonalne, dla toast notifications)
- System.Net.Mail (wbudowane w .NET)
#>

# =============================================================================
# MODULE INITIALIZATION
# =============================================================================

$script:ModuleConfig = @{
    Version = "1.0"
    Initialized = $false
    BurntToastAvailable = $false
}

# =============================================================================
# PRIVATE FUNCTIONS
# =============================================================================

<#
.SYNOPSIS
Sprawdza dostępność modułu BurntToast

.DESCRIPTION
Próbuje zaimportować BurntToast i zapisuje wynik w konfiguracji modułu.
#>
function Test-BurntToastAvailability {
    [CmdletBinding()]
    param()

    try {
        # Sprawdź czy moduł jest zainstalowany
        $btModule = Get-Module -ListAvailable -Name BurntToast -ErrorAction SilentlyContinue

        if ($btModule) {
            Import-Module BurntToast -ErrorAction Stop
            $script:ModuleConfig.BurntToastAvailable = $true
            Write-Verbose "BurntToast module available"
            return $true
        }
        else {
            Write-Verbose "BurntToast module not installed"
            return $false
        }
    }
    catch {
        Write-Verbose "Failed to import BurntToast: $($_.Exception.Message)"
        return $false
    }
}

<#
.SYNOPSIS
Formatuje podsumowanie wyników jako tekst

.DESCRIPTION
Konwertuje wyniki aktualizacji na czytelny tekst dla powiadomień.

.PARAMETER Results
Tablica obiektów StepResult z Update-WingetAll.ps1

.PARAMETER Format
Format wyjściowy: Plain, Markdown, HTML

.EXAMPLE
$text = Format-ResultSummary -Results $Results -Format Plain
#>
function Format-ResultSummary {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [object[]]$Results,

        [ValidateSet('Plain', 'Markdown', 'HTML')]
        [string]$Format = 'Plain'
    )

    $totalUpdated = ($Results | ForEach-Object { $_.Counts.Updated } | Measure-Object -Sum).Sum
    $totalFailed = ($Results | ForEach-Object { $_.Counts.Failed } | Measure-Object -Sum).Sum
    $totalSkipped = ($Results.Status -eq 'SKIP').Count
    $totalOK = ($Results.Status -eq 'OK').Count
    $totalFail = ($Results.Status -eq 'FAIL').Count

    switch ($Format) {
        'Plain' {
            $text = "Update-Ultra - Podsumowanie Aktualizacji`n`n"
            $text += "Zaktualizowano pakietów: $totalUpdated`n"
            $text += "Błędów: $totalFailed`n"
            $text += "Sekcji OK: $totalOK`n"
            $text += "Sekcji FAIL: $totalFail`n"
            $text += "Pominięto sekcji: $totalSkipped`n`n"

            $text += "Szczegóły:`n"
            foreach ($r in $Results) {
                if ($r.Status -ne 'SKIP') {
                    $text += "  [$($r.Status)] $($r.Name): $($r.Counts.Updated) updated, $($r.Counts.Failed) failed`n"
                }
            }

            return $text
        }

        'Markdown' {
            $text = "## Update-Ultra - Podsumowanie Aktualizacji`n`n"
            $text += "**Zaktualizowano pakietów:** $totalUpdated  `n"
            $text += "**Błędów:** $totalFailed  `n"
            $text += "**Sekcji OK:** $totalOK  `n"
            $text += "**Sekcji FAIL:** $totalFail  `n"
            $text += "**Pominięto sekcji:** $totalSkipped  `n`n"

            $text += "### Szczegóły`n`n"
            foreach ($r in $Results) {
                if ($r.Status -ne 'SKIP') {
                    $emoji = if ($r.Status -eq 'OK') { ':white_check_mark:' } else { ':x:' }
                    $text += "- $emoji **$($r.Name):** $($r.Counts.Updated) updated, $($r.Counts.Failed) failed`n"
                }
            }

            return $text
        }

        'HTML' {
            $statusColor = if ($totalFailed -eq 0) { '#28a745' } else { '#dc3545' }

            $text = @"
<div style='font-family: Arial, sans-serif;'>
<h2 style='color: $statusColor;'>Update-Ultra - Podsumowanie Aktualizacji</h2>
<table style='border-collapse: collapse; width: 100%;'>
<tr><td style='padding: 5px;'><strong>Zaktualizowano pakietów:</strong></td><td style='padding: 5px;'>$totalUpdated</td></tr>
<tr><td style='padding: 5px;'><strong>Błędów:</strong></td><td style='padding: 5px;'>$totalFailed</td></tr>
<tr><td style='padding: 5px;'><strong>Sekcji OK:</strong></td><td style='padding: 5px;'>$totalOK</td></tr>
<tr><td style='padding: 5px;'><strong>Sekcji FAIL:</strong></td><td style='padding: 5px;'>$totalFail</td></tr>
<tr><td style='padding: 5px;'><strong>Pominięto sekcji:</strong></td><td style='padding: 5px;'>$totalSkipped</td></tr>
</table>
<h3>Szczegóły</h3>
<ul>
"@
            foreach ($r in $Results) {
                if ($r.Status -ne 'SKIP') {
                    $bullet = if ($r.Status -eq 'OK') { '✓' } else { '✗' }
                    $text += "<li><strong>$bullet $($r.Name):</strong> $($r.Counts.Updated) updated, $($r.Counts.Failed) failed</li>`n"
                }
            }
            $text += "</ul></div>"

            return $text
        }
    }
}

# =============================================================================
# PUBLIC FUNCTIONS
# =============================================================================

<#
.SYNOPSIS
Inicjalizuje moduł powiadomień

.DESCRIPTION
Sprawdza dostępność BurntToast i przygotowuje moduł do użycia.

.EXAMPLE
Initialize-NotificationManager
#>
function Initialize-NotificationManager {
    [CmdletBinding()]
    param()

    if ($script:ModuleConfig.Initialized) {
        Write-Verbose "NotificationManager already initialized"
        return
    }

    Write-Verbose "Initializing NotificationManager..."

    # Sprawdź dostępność BurntToast
    $script:ModuleConfig.BurntToastAvailable = Test-BurntToastAvailability

    if (-not $script:ModuleConfig.BurntToastAvailable) {
        Write-Warning "BurntToast module not available. Toast notifications will be disabled."
        Write-Warning "Install BurntToast: Install-Module -Name BurntToast -Scope CurrentUser"
    }

    $script:ModuleConfig.Initialized = $true
    Write-Verbose "NotificationManager initialized successfully"
}

<#
.SYNOPSIS
Wysyła powiadomienie toast w Windows

.DESCRIPTION
Wyświetla natywne powiadomienie Windows 10/11 toast.
Wymaga modułu BurntToast.

.PARAMETER Title
Tytuł powiadomienia

.PARAMETER Message
Treść powiadomienia

.PARAMETER Results
Opcjonalnie: wyniki aktualizacji do sformatowania

.EXAMPLE
Send-ToastNotification -Title "Aktualizacja ukończona" -Message "15 pakietów zaktualizowano"

.EXAMPLE
Send-ToastNotification -Title "Update-Ultra" -Results $Results

.NOTES
Graceful degradation - jeśli BurntToast nie jest dostępny, wyświetla tylko warning.
#>
function Send-ToastNotification {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Title,

        [string]$Message,

        [object[]]$Results
    )

    # Auto-initialize if needed
    if (-not $script:ModuleConfig.Initialized) {
        Initialize-NotificationManager
    }

    # Sprawdź dostępność BurntToast
    if (-not $script:ModuleConfig.BurntToastAvailable) {
        Write-Warning "Cannot send toast notification: BurntToast module not available"
        return
    }

    try {
        # Jeśli przekazano Results, sformatuj wiadomość
        if ($Results) {
            $totalUpdated = ($Results | ForEach-Object { $_.Counts.Updated } | Measure-Object -Sum).Sum
            $totalFailed = ($Results | ForEach-Object { $_.Counts.Failed } | Measure-Object -Sum).Sum

            if ($totalFailed -eq 0) {
                $Message = "Zaktualizowano $totalUpdated pakietów. Brak błędów."
            }
            else {
                $Message = "Zaktualizowano $totalUpdated pakietów. Błędów: $totalFailed"
            }
        }

        # Wyślij toast przez BurntToast
        New-BurntToastNotification -Text $Title, $Message -AppLogo (Join-Path $PSScriptRoot "..\assets\icon.png") -ErrorAction Stop

        Write-Verbose "Toast notification sent: $Title"
    }
    catch {
        Write-Warning "Failed to send toast notification: $($_.Exception.Message)"
    }
}

<#
.SYNOPSIS
Wysyła powiadomienie email przez SMTP

.DESCRIPTION
Wysyła email z podsumowaniem aktualizacji przez SMTP.

.PARAMETER To
Adres email odbiorcy

.PARAMETER Subject
Temat wiadomości

.PARAMETER Body
Treść wiadomości (opcjonalne jeśli przekazano Results)

.PARAMETER Results
Wyniki aktualizacji do sformatowania jako email

.PARAMETER SmtpServer
Serwer SMTP (np. smtp.gmail.com)

.PARAMETER SmtpPort
Port SMTP (domyślnie 587 dla TLS)

.PARAMETER Username
Nazwa użytkownika SMTP

.PARAMETER Password
Hasło SMTP (jako SecureString lub plain text)

.PARAMETER UseSSL
Użyj SSL/TLS (domyślnie: true)

.PARAMETER From
Adres nadawcy (domyślnie: Username)

.EXAMPLE
$securePass = ConvertTo-SecureString "password" -AsPlainText -Force
Send-EmailNotification -To "admin@example.com" -Subject "Update-Ultra" -Results $Results `
    -SmtpServer "smtp.gmail.com" -Username "user@gmail.com" -Password $securePass

.EXAMPLE
Send-EmailNotification -To "admin@example.com" -Subject "Alert" -Body "Custom message" `
    -SmtpServer "smtp.office365.com" -Username "user@outlook.com" -Password "pass"
#>
function Send-EmailNotification {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$To,

        [Parameter(Mandatory)]
        [string]$Subject,

        [string]$Body,

        [object[]]$Results,

        [Parameter(Mandatory)]
        [string]$SmtpServer,

        [int]$SmtpPort = 587,

        [Parameter(Mandatory)]
        [string]$Username,

        [Parameter(Mandatory)]
        [object]$Password,  # Can be SecureString or plain string

        [bool]$UseSSL = $true,

        [string]$From
    )

    try {
        # Ustaw From jeśli nie podano
        if (-not $From) {
            $From = $Username
        }

        # Sformatuj Body z Results jeśli przekazano
        if ($Results -and -not $Body) {
            $Body = Format-ResultSummary -Results $Results -Format HTML
        }

        # Konwertuj hasło na SecureString jeśli potrzeba
        $securePassword = if ($Password -is [SecureString]) {
            $Password
        }
        else {
            ConvertTo-SecureString $Password -AsPlainText -Force
        }

        # Utwórz credentials
        $credential = New-Object System.Management.Automation.PSCredential($Username, $securePassword)

        # Parametry emaila
        $mailParams = @{
            To         = $To
            From       = $From
            Subject    = $Subject
            Body       = $Body
            BodyAsHtml = $true
            SmtpServer = $SmtpServer
            Port       = $SmtpPort
            UseSsl     = $UseSSL
            Credential = $credential
        }

        # Wyślij email
        Send-MailMessage @mailParams -ErrorAction Stop

        Write-Verbose "Email notification sent to: $To"
        Write-Host "✓ Email wysłany do: $To" -ForegroundColor Green
    }
    catch {
        Write-Warning "Failed to send email notification: $($_.Exception.Message)"
        throw
    }
}

<#
.SYNOPSIS
Wysyła powiadomienie webhook (HTTP POST)

.DESCRIPTION
Wysyła powiadomienie przez webhook do Slack, Discord, Teams lub innego endpoint.

.PARAMETER Url
URL webhook

.PARAMETER Results
Wyniki aktualizacji do wysłania

.PARAMETER CustomPayload
Opcjonalnie: własny payload JSON (zamiast Results)

.PARAMETER WebhookType
Typ webhook: Slack, Discord, Teams, Generic (domyślnie: Generic)

.EXAMPLE
Send-WebhookNotification -Url "https://hooks.slack.com/services/XXX" -Results $Results -WebhookType Slack

.EXAMPLE
Send-WebhookNotification -Url "https://webhook.site/xxx" -CustomPayload '{"status": "ok"}'

.NOTES
Generic webhook wysyła prosty JSON:
{
  "title": "Update-Ultra Results",
  "summary": "...",
  "totalUpdated": 15,
  "totalFailed": 0,
  "results": [...]
}
#>
function Send-WebhookNotification {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Url,

        [object[]]$Results,

        [string]$CustomPayload,

        [ValidateSet('Slack', 'Discord', 'Teams', 'Generic')]
        [string]$WebhookType = 'Generic'
    )

    try {
        $payload = $null

        # Użyj custom payload jeśli podano
        if ($CustomPayload) {
            $payload = $CustomPayload
        }
        # Wygeneruj payload na podstawie Results
        elseif ($Results) {
            $summary = Format-ResultSummary -Results $Results -Format Markdown
            $totalUpdated = ($Results | ForEach-Object { $_.Counts.Updated } | Measure-Object -Sum).Sum
            $totalFailed = ($Results | ForEach-Object { $_.Counts.Failed } | Measure-Object -Sum).Sum

            switch ($WebhookType) {
                'Slack' {
                    $color = if ($totalFailed -eq 0) { 'good' } else { 'danger' }
                    $payload = @{
                        text = "Update-Ultra - Podsumowanie Aktualizacji"
                        attachments = @(
                            @{
                                color = $color
                                text = $summary
                                fields = @(
                                    @{ title = "Zaktualizowano"; value = $totalUpdated; short = $true }
                                    @{ title = "Błędów"; value = $totalFailed; short = $true }
                                )
                            }
                        )
                    } | ConvertTo-Json -Depth 10
                }

                'Discord' {
                    $color = if ($totalFailed -eq 0) { 3066993 } else { 15158332 }  # Green or Red
                    $payload = @{
                        embeds = @(
                            @{
                                title = "Update-Ultra - Podsumowanie Aktualizacji"
                                description = $summary
                                color = $color
                                fields = @(
                                    @{ name = "Zaktualizowano"; value = $totalUpdated; inline = $true }
                                    @{ name = "Błędów"; value = $totalFailed; inline = $true }
                                )
                            }
                        )
                    } | ConvertTo-Json -Depth 10
                }

                'Teams' {
                    $themeColor = if ($totalFailed -eq 0) { '28A745' } else { 'DC3545' }
                    $payload = @{
                        '@type' = 'MessageCard'
                        '@context' = 'https://schema.org/extensions'
                        themeColor = $themeColor
                        title = "Update-Ultra - Podsumowanie Aktualizacji"
                        text = $summary
                        sections = @(
                            @{
                                facts = @(
                                    @{ name = "Zaktualizowano"; value = $totalUpdated }
                                    @{ name = "Błędów"; value = $totalFailed }
                                )
                            }
                        )
                    } | ConvertTo-Json -Depth 10
                }

                'Generic' {
                    $payload = @{
                        title = "Update-Ultra Results"
                        summary = $summary
                        totalUpdated = $totalUpdated
                        totalFailed = $totalFailed
                        timestamp = (Get-Date).ToString('o')
                        results = $Results
                    } | ConvertTo-Json -Depth 10
                }
            }
        }
        else {
            throw "Either Results or CustomPayload must be provided"
        }

        # Wyślij POST request
        $response = Invoke-RestMethod -Uri $Url -Method Post -Body $payload -ContentType 'application/json' -ErrorAction Stop

        Write-Verbose "Webhook notification sent to: $Url"
        Write-Host "✓ Webhook wysłany: $Url" -ForegroundColor Green
    }
    catch {
        Write-Warning "Failed to send webhook notification: $($_.Exception.Message)"
        throw
    }
}

<#
.SYNOPSIS
Wysyła powiadomienia przez wszystkie skonfigurowane kanały

.DESCRIPTION
Wrapper który wysyła powiadomienia przez wszystkie aktywne kanały
na podstawie przekazanych parametrów.

.PARAMETER Results
Wyniki aktualizacji

.PARAMETER Toast
Wyślij toast notification

.PARAMETER Email
Adres email do wysłania powiadomienia

.PARAMETER SmtpServer
Serwer SMTP

.PARAMETER SmtpPort
Port SMTP

.PARAMETER SmtpUsername
Username SMTP

.PARAMETER SmtpPassword
Hasło SMTP

.PARAMETER Webhook
URL webhook

.PARAMETER WebhookType
Typ webhook (Slack, Discord, Teams, Generic)

.EXAMPLE
Send-UpdateNotification -Results $Results -Toast -Email "admin@example.com" `
    -SmtpServer "smtp.gmail.com" -SmtpUsername "user@gmail.com" -SmtpPassword $pass

.EXAMPLE
Send-UpdateNotification -Results $Results -Webhook "https://hooks.slack.com/..." -WebhookType Slack
#>
function Send-UpdateNotification {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [object[]]$Results,

        [switch]$Toast,

        [string]$Email,
        [string]$SmtpServer,
        [int]$SmtpPort = 587,
        [string]$SmtpUsername,
        [object]$SmtpPassword,
        [string]$SmtpFrom,

        [string]$Webhook,
        [string]$WebhookType = 'Generic'
    )

    $sent = @()
    $errors = @()

    # Toast notification
    if ($Toast) {
        try {
            Send-ToastNotification -Title "Update-Ultra" -Results $Results
            $sent += "Toast"
        }
        catch {
            $errors += "Toast: $($_.Exception.Message)"
        }
    }

    # Email notification
    if ($Email -and $SmtpServer -and $SmtpUsername -and $SmtpPassword) {
        try {
            $emailParams = @{
                To         = $Email
                Subject    = "Update-Ultra - Podsumowanie Aktualizacji"
                Results    = $Results
                SmtpServer = $SmtpServer
                SmtpPort   = $SmtpPort
                Username   = $SmtpUsername
                Password   = $SmtpPassword
            }

            if ($SmtpFrom) {
                $emailParams.From = $SmtpFrom
            }

            Send-EmailNotification @emailParams
            $sent += "Email"
        }
        catch {
            $errors += "Email: $($_.Exception.Message)"
        }
    }

    # Webhook notification
    if ($Webhook) {
        try {
            Send-WebhookNotification -Url $Webhook -Results $Results -WebhookType $WebhookType
            $sent += "Webhook"
        }
        catch {
            $errors += "Webhook: $($_.Exception.Message)"
        }
    }

    # Podsumowanie
    if ($sent.Count -gt 0) {
        Write-Host "`n✓ Powiadomienia wysłane: $($sent -join ', ')" -ForegroundColor Green
    }

    if ($errors.Count -gt 0) {
        Write-Warning "`nBłędy podczas wysyłania powiadomień:"
        foreach ($err in $errors) {
            Write-Warning "  $err"
        }
    }
}

<#
.SYNOPSIS
Zwraca status modułu powiadomień

.DESCRIPTION
Zwraca informacje o dostępności BurntToast i stanie inicjalizacji.

.EXAMPLE
Get-NotificationStatus
#>
function Get-NotificationStatus {
    [CmdletBinding()]
    param()

    return [pscustomobject]@{
        ModuleName = "NotificationManager"
        Version = $script:ModuleConfig.Version
        Initialized = $script:ModuleConfig.Initialized
        BurntToastAvailable = $script:ModuleConfig.BurntToastAvailable
    }
}

# =============================================================================
# EXPORT PUBLIC FUNCTIONS
# =============================================================================

Export-ModuleMember -Function `
    Initialize-NotificationManager, `
    Send-ToastNotification, `
    Send-EmailNotification, `
    Send-WebhookNotification, `
    Send-UpdateNotification, `
    Get-NotificationStatus

# =============================================================================
# MODULE AUTO-INITIALIZATION
# =============================================================================

# Auto-inicjalizacja przy imporcie
Initialize-NotificationManager -ErrorAction SilentlyContinue
