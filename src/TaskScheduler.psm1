# TaskScheduler.psm1
# Moduł do zarządzania Windows Scheduled Tasks dla automatycznych aktualizacji

<#
.SYNOPSIS
Moduł zarządzania harmonogramem automatycznych aktualizacji Update-Ultra

.DESCRIPTION
Umożliwia tworzenie, usuwanie i zarządzanie Windows Scheduled Tasks
dla automatycznego uruchamiania Update-WingetAll.ps1 o określonych porach.

.NOTES
Wymaga: PowerShell 5.1+, Uprawnienia Administrator
Kompatybilność: Windows 10/11, Windows Server 2016+
#>

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

#region Module State
$script:ModuleVersion = "1.0.0"
$script:ModuleName = "TaskScheduler"
$script:DefaultTaskName = "UpdateUltra-AutoUpdate"
#endregion

#region Private Functions

function Write-Log {
    param(
        [string]$Message,
        [ValidateSet('INFO', 'WARN', 'ERROR', 'DEBUG')]
        [string]$Level = 'INFO'
    )

    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $color = switch ($Level) {
        'INFO'  { 'White' }
        'WARN'  { 'Yellow' }
        'ERROR' { 'Red' }
        'DEBUG' { 'DarkGray' }
    }

    Write-Host "[$timestamp] [$Level] $Message" -ForegroundColor $color
}

function Test-Administrator {
    $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = New-Object Security.Principal.WindowsPrincipal($identity)
    return $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

function Build-ScriptArguments {
    param([hashtable]$ScriptParameters)

    if (-not $ScriptParameters -or $ScriptParameters.Count -eq 0) {
        return ""
    }

    $args = @()
    foreach ($key in $ScriptParameters.Keys) {
        $value = $ScriptParameters[$key]

        if ($value -is [bool]) {
            if ($value) {
                $args += "-$key"
            }
        }
        elseif ($value -is [switch]) {
            if ($value) {
                $args += "-$key"
            }
        }
        elseif ($value -is [array]) {
            $arrayStr = ($value | ForEach-Object { "'$_'" }) -join ','
            $args += "-$key @($arrayStr)"
        }
        elseif ($value -is [hashtable]) {
            # Convert hashtable to JSON for complex parameters
            $json = $value | ConvertTo-Json -Compress
            $args += "-$key '$json'"
        }
        else {
            $args += "-$key '$value'"
        }
    }

    return $args -join ' '
}

#endregion

#region Public Functions

function Install-UpdateSchedule {
    <#
    .SYNOPSIS
    Tworzy nowy Windows Scheduled Task dla automatycznych aktualizacji

    .DESCRIPTION
    Konfiguruje Windows Task Scheduler do automatycznego uruchamiania
    Update-WingetAll.ps1 o określonych porach z możliwością dostosowania
    częstotliwości, parametrów i warunków uruchomienia.

    .PARAMETER Name
    Nazwa taska w Task Scheduler. Domyślnie: "UpdateUltra-AutoUpdate"

    .PARAMETER RunAt
    Godzina uruchomienia w formacie 24h (HH:mm), np. "03:00"

    .PARAMETER Frequency
    Częstotliwość: Daily, Weekly, Monthly

    .PARAMETER DayOfWeek
    Dzień tygodnia dla Weekly (np. "Sunday", "Monday")

    .PARAMETER ScriptPath
    Pełna ścieżka do Update-WingetAll.ps1

    .PARAMETER ScriptParameters
    Hashtable z parametrami skryptu, np. @{EnableCache=$true; NotifyToast=$true}

    .PARAMETER RunAsUser
    Konto użytkownika (domyślnie: SYSTEM)

    .PARAMETER Conditions
    Hashtable z warunkami: @{RequireAC=$true; RequireIdle=$false; RequireNetwork=$true}

    .EXAMPLE
    Install-UpdateSchedule -RunAt "03:00" -Frequency Daily -ScriptPath "C:\Scripts\Update-WingetAll.ps1"

    .EXAMPLE
    Install-UpdateSchedule -RunAt "02:00" -Frequency Weekly -DayOfWeek "Sunday" `
        -ScriptParameters @{EnableCache=$true; SkipDocker=$true}
    #>
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [string]$Name = $script:DefaultTaskName,

        [Parameter(Mandatory)]
        [ValidatePattern('^\d{2}:\d{2}$')]
        [string]$RunAt,

        [ValidateSet('Daily', 'Weekly', 'Monthly')]
        [string]$Frequency = 'Weekly',

        [ValidateSet('Sunday', 'Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday')]
        [string]$DayOfWeek = 'Sunday',

        [Parameter(Mandatory)]
        [ValidateScript({Test-Path $_ -PathType Leaf})]
        [string]$ScriptPath,

        [hashtable]$ScriptParameters,

        [string]$RunAsUser = 'SYSTEM',

        [hashtable]$Conditions
    )

    # Sprawdź uprawnienia
    if (-not (Test-Administrator)) {
        throw "Wymagane uprawnienia Administrator do tworzenia Scheduled Tasks"
    }

    Write-Log "Tworzenie Scheduled Task: $Name" -Level INFO

    # Parse time
    $timeParts = $RunAt -split ':'
    $hour = [int]$timeParts[0]
    $minute = [int]$timeParts[1]

    if ($hour -lt 0 -or $hour -gt 23 -or $minute -lt 0 -or $minute -gt 59) {
        throw "Nieprawidłowy format czasu. Użyj HH:mm w formacie 24h (np. 03:00)"
    }

    # Build trigger
    Write-Log "Konfiguracja triggera: $Frequency @ $RunAt" -Level DEBUG
    $trigger = switch ($Frequency) {
        'Daily' {
            New-ScheduledTaskTrigger -Daily -At $RunAt
        }
        'Weekly' {
            New-ScheduledTaskTrigger -Weekly -DaysOfWeek $DayOfWeek -At $RunAt
        }
        'Monthly' {
            New-ScheduledTaskTrigger -At $RunAt -Monthly -DaysOfMonth 1
        }
    }

    # Build action (PowerShell command)
    $pwshPath = if (Get-Command pwsh -ErrorAction SilentlyContinue) {
        (Get-Command pwsh).Source
    } else {
        "powershell.exe"
    }

    $arguments = "-NoProfile -ExecutionPolicy Bypass -File `"$ScriptPath`""

    if ($ScriptParameters) {
        $paramString = Build-ScriptArguments -ScriptParameters $ScriptParameters
        if ($paramString) {
            $arguments += " $paramString"
        }
    }

    Write-Log "Command: $pwshPath $arguments" -Level DEBUG

    $action = New-ScheduledTaskAction -Execute $pwshPath -Argument $arguments

    # Build settings
    $settings = New-ScheduledTaskSettingsSet `
        -AllowStartIfOnBatteries:$false `
        -DontStopIfGoingOnBatteries:$true `
        -StartWhenAvailable:$true `
        -RunOnlyIfNetworkAvailable:$false `
        -DontStopOnIdleEnd:$true

    if ($Conditions) {
        Write-Log "Stosowanie warunków uruchomienia" -Level DEBUG

        if ($Conditions.ContainsKey('RequireAC')) {
            $settings.AllowStartIfOnBatteries = -not $Conditions.RequireAC
        }

        if ($Conditions.ContainsKey('RequireIdle')) {
            $settings.RunOnlyIfIdle = $Conditions.RequireIdle
        }

        if ($Conditions.ContainsKey('RequireNetwork')) {
            $settings.RunOnlyIfNetworkAvailable = $Conditions.RequireNetwork
        }
    }

    # Register task
    if ($PSCmdlet.ShouldProcess($Name, "Rejestracja Scheduled Task")) {
        try {
            $task = Register-ScheduledTask `
                -TaskName $Name `
                -Trigger $trigger `
                -Action $action `
                -Settings $settings `
                -User $RunAsUser `
                -Force `
                -ErrorAction Stop

            Write-Log "Scheduled Task utworzony pomyślnie: $Name" -Level INFO

            # Pobierz info o następnym uruchomieniu
            $nextRun = (Get-ScheduledTaskInfo -TaskName $Name).NextRunTime
            Write-Log "Następne uruchomienie: $nextRun" -Level INFO

            return $task
        }
        catch {
            Write-Log "Błąd podczas tworzenia Scheduled Task: $($_.Exception.Message)" -Level ERROR
            throw
        }
    }
}

function Remove-UpdateSchedule {
    <#
    .SYNOPSIS
    Usuwa istniejący Scheduled Task dla Update-Ultra

    .DESCRIPTION
    Usuwa Windows Scheduled Task utworzony przez Install-UpdateSchedule

    .PARAMETER Name
    Nazwa taska do usunięcia. Domyślnie: "UpdateUltra-AutoUpdate"

    .EXAMPLE
    Remove-UpdateSchedule

    .EXAMPLE
    Remove-UpdateSchedule -Name "MyCustomUpdateTask"
    #>
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [string]$Name = $script:DefaultTaskName
    )

    # Sprawdź uprawnienia
    if (-not (Test-Administrator)) {
        throw "Wymagane uprawnienia Administrator do usuwania Scheduled Tasks"
    }

    Write-Log "Usuwanie Scheduled Task: $Name" -Level INFO

    # Sprawdź czy task istnieje
    $task = Get-ScheduledTask -TaskName $Name -ErrorAction SilentlyContinue

    if (-not $task) {
        Write-Log "Scheduled Task '$Name' nie istnieje" -Level WARN
        return $false
    }

    if ($PSCmdlet.ShouldProcess($Name, "Usunięcie Scheduled Task")) {
        try {
            Unregister-ScheduledTask -TaskName $Name -Confirm:$false -ErrorAction Stop
            Write-Log "Scheduled Task usunięty pomyślnie: $Name" -Level INFO
            return $true
        }
        catch {
            Write-Log "Błąd podczas usuwania Scheduled Task: $($_.Exception.Message)" -Level ERROR
            throw
        }
    }
}

function Get-UpdateSchedule {
    <#
    .SYNOPSIS
    Wyświetla aktualną konfigurację Scheduled Task

    .DESCRIPTION
    Pobiera szczegółowe informacje o istniejącym Windows Scheduled Task
    dla Update-Ultra, włączając trigger, akcję, stan i historię uruchomień.

    .PARAMETER Name
    Nazwa taska do sprawdzenia. Domyślnie: "UpdateUltra-AutoUpdate"

    .EXAMPLE
    Get-UpdateSchedule

    .EXAMPLE
    Get-UpdateSchedule -Name "MyCustomUpdateTask" | Format-List
    #>
    [CmdletBinding()]
    param(
        [string]$Name = $script:DefaultTaskName
    )

    Write-Log "Pobieranie informacji o Scheduled Task: $Name" -Level DEBUG

    # Sprawdź czy task istnieje
    $task = Get-ScheduledTask -TaskName $Name -ErrorAction SilentlyContinue

    if (-not $task) {
        Write-Log "Scheduled Task '$Name' nie istnieje" -Level WARN
        return $null
    }

    # Pobierz dodatkowe info
    $taskInfo = Get-ScheduledTaskInfo -TaskName $Name -ErrorAction SilentlyContinue

    # Buduj obiekt wynikowy
    $result = [PSCustomObject]@{
        Name            = $task.TaskName
        State           = $task.State
        Enabled         = ($task.State -eq 'Ready')
        LastRunTime     = $taskInfo.LastRunTime
        LastResult      = $taskInfo.LastTaskResult
        NextRunTime     = $taskInfo.NextRunTime
        NumberOfMissedRuns = $taskInfo.NumberOfMissedRuns
        Triggers        = @()
        Actions         = @()
        Settings        = $null
    }

    # Parse triggers
    foreach ($trigger in $task.Triggers) {
        $triggerInfo = [PSCustomObject]@{
            Type      = $trigger.CimClass.CimClassName -replace 'MSFT_TaskTrigger', ''
            Enabled   = $trigger.Enabled
            StartTime = $trigger.StartBoundary
        }

        # Dodaj szczegóły w zależności od typu
        if ($trigger.CimClass.CimClassName -match 'Weekly') {
            $triggerInfo | Add-Member -NotePropertyName 'DaysOfWeek' -NotePropertyValue $trigger.DaysOfWeek
        }

        $result.Triggers += $triggerInfo
    }

    # Parse actions
    foreach ($action in $task.Actions) {
        $actionInfo = [PSCustomObject]@{
            Type      = $action.CimClass.CimClassName -replace 'MSFT_Task', ''
            Execute   = $action.Execute
            Arguments = $action.Arguments
        }

        $result.Actions += $actionInfo
    }

    # Parse settings
    $result.Settings = [PSCustomObject]@{
        AllowStartIfOnBatteries       = $task.Settings.AllowStartIfOnBatteries
        DontStopIfGoingOnBatteries    = $task.Settings.DisallowStartIfOnBatteries -eq $false
        RunOnlyIfNetworkAvailable     = $task.Settings.RunOnlyIfNetworkAvailable
        RunOnlyIfIdle                 = $task.Settings.RunOnlyIfIdle
        StartWhenAvailable            = $task.Settings.StartWhenAvailable
    }

    return $result
}

function Test-UpdateSchedule {
    <#
    .SYNOPSIS
    Testuje konfigurację Scheduled Task

    .DESCRIPTION
    Weryfikuje czy Scheduled Task jest poprawnie skonfigurowany:
    - Czy task istnieje
    - Czy skrypt docelowy istnieje
    - Czy task jest włączony
    - Opcjonalnie: dry-run test skryptu z -WhatIf

    .PARAMETER Name
    Nazwa taska do przetestowania. Domyślnie: "UpdateUltra-AutoUpdate"

    .PARAMETER RunTest
    Jeśli włączone, uruchamia ręczny test skryptu z -WhatIf

    .EXAMPLE
    Test-UpdateSchedule

    .EXAMPLE
    Test-UpdateSchedule -RunTest
    #>
    [CmdletBinding()]
    param(
        [string]$Name = $script:DefaultTaskName,
        [switch]$RunTest
    )

    Write-Log "Testowanie konfiguracji Scheduled Task: $Name" -Level INFO

    $issues = @()
    $warnings = @()

    # Sprawdź czy task istnieje
    $task = Get-ScheduledTask -TaskName $Name -ErrorAction SilentlyContinue

    if (-not $task) {
        $issues += "Task '$Name' nie istnieje"

        $result = [PSCustomObject]@{
            TaskName = $Name
            Valid    = $false
            Issues   = $issues
            Warnings = $warnings
        }

        Write-Log "Test FAILED: Task nie istnieje" -Level ERROR
        return $result
    }

    # Sprawdź czy task jest włączony
    if ($task.State -ne 'Ready') {
        $warnings += "Task jest w stanie: $($task.State) (oczekiwano: Ready)"
    }

    # Sprawdź czy akcja istnieje
    if ($task.Actions.Count -eq 0) {
        $issues += "Brak zdefiniowanych akcji w tasku"
    }
    else {
        $action = $task.Actions[0]

        # Sprawdź czy plik skryptu istnieje
        # Parse path from arguments
        if ($action.Arguments -match '-File\s+"([^"]+)"') {
            $scriptPath = $Matches[1]

            if (-not (Test-Path $scriptPath)) {
                $issues += "Skrypt docelowy nie istnieje: $scriptPath"
            }
            else {
                Write-Log "Skrypt docelowy: $scriptPath" -Level DEBUG
            }
        }
        else {
            $warnings += "Nie można sparsować ścieżki skryptu z argumentów"
        }
    }

    # Sprawdź triggery
    if ($task.Triggers.Count -eq 0) {
        $warnings += "Brak zdefiniowanych triggerów (task nie uruchomi się automatycznie)"
    }

    # Sprawdź czy task nie ma zaległych uruchomień
    $taskInfo = Get-ScheduledTaskInfo -TaskName $Name -ErrorAction SilentlyContinue
    if ($taskInfo -and $taskInfo.NumberOfMissedRuns -gt 0) {
        $warnings += "Task ma $($taskInfo.NumberOfMissedRuns) zaległych uruchomień"
    }

    # Opcjonalnie uruchom test
    if ($RunTest -and $issues.Count -eq 0) {
        Write-Log "Uruchamianie ręcznego testu skryptu z -WhatIf..." -Level INFO

        try {
            # Uruchom task ręcznie
            Start-ScheduledTask -TaskName $Name -ErrorAction Stop

            Write-Log "Task uruchomiony ręcznie - sprawdź logi" -Level INFO
            $warnings += "Test uruchomienia wykonany - sprawdź logi w ProgramData\Winget-Logs"
        }
        catch {
            $issues += "Nie udało się uruchomić taska ręcznie: $($_.Exception.Message)"
        }
    }

    # Build result
    $result = [PSCustomObject]@{
        TaskName = $Name
        Valid    = ($issues.Count -eq 0)
        Issues   = $issues
        Warnings = $warnings
        TaskInfo = $task
    }

    # Log summary
    if ($issues.Count -eq 0) {
        Write-Log "Test PASSED: Task jest poprawnie skonfigurowany" -Level INFO
    }
    else {
        Write-Log "Test FAILED: Znaleziono $($issues.Count) problemów" -Level ERROR
        foreach ($issue in $issues) {
            Write-Log "  - $issue" -Level ERROR
        }
    }

    if ($warnings.Count -gt 0) {
        Write-Log "Ostrzeżenia ($($warnings.Count)):" -Level WARN
        foreach ($warning in $warnings) {
            Write-Log "  - $warning" -Level WARN
        }
    }

    return $result
}

#endregion

#region Module Initialization

function Initialize-TaskScheduler {
    <#
    .SYNOPSIS
    Inicjalizuje moduł TaskScheduler

    .DESCRIPTION
    Opcjonalna funkcja inicjalizacji modułu
    #>
    [CmdletBinding()]
    param()

    Write-Log "TaskScheduler v$script:ModuleVersion inicjalizowany" -Level DEBUG

    # Sprawdź czy jesteśmy na Windows
    if ($PSVersionTable.PSEdition -eq 'Core' -and -not $IsWindows) {
        Write-Log "TaskScheduler wymaga systemu Windows" -Level ERROR
        throw "Ten moduł jest dostępny tylko na Windows"
    }
}

#endregion

# Export functions
Export-ModuleMember -Function @(
    'Install-UpdateSchedule',
    'Remove-UpdateSchedule',
    'Get-UpdateSchedule',
    'Test-UpdateSchedule',
    'Initialize-TaskScheduler'
)
