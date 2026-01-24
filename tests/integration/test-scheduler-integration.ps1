# test-scheduler-integration.ps1
# Integration tests dla TaskScheduler.psm1

<#
.SYNOPSIS
Testy integracyjne dla modułu TaskScheduler

.DESCRIPTION
Weryfikuje:
- Pełny cykl Install → Get → Test → Remove
- Rzeczywiste tworzenie scheduled tasks w Windows
- Wykonywanie scheduled tasks
- Czytanie i walidacja konfiguracji
- Cleanup po testach

.NOTES
Wymaga:
- Pester 5.x
- Uprawnienia Administrator (do tworzenia scheduled tasks)
- Windows Task Scheduler włączony
Uruchomienie: Invoke-Pester .\test-scheduler-integration.ps1
#>

BeforeAll {
    # Import modułu TaskScheduler
    $modulePath = Join-Path $PSScriptRoot "..\..\src\TaskScheduler.psm1"
    Import-Module $modulePath -Force

    # Sprawdź uprawnienia Administrator
    $isAdmin = ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)

    if (-not $isAdmin) {
        throw "Integration tests wymagają uprawnień Administrator do tworzenia scheduled tasks"
    }

    # Utwórz tymczasowy skrypt testowy
    $script:TestScriptPath = Join-Path $env:TEMP "update-ultra-test-script-$(Get-Random).ps1"
    @'
# Test script for TaskScheduler integration tests
param(
    [switch]$EnableCache,
    [int]$CacheTTL = 300,
    [switch]$NotifyToast,
    [string]$LogPath
)

Write-Host "Test script executed at $(Get-Date)"
Write-Host "EnableCache: $EnableCache"
Write-Host "CacheTTL: $CacheTTL"
Write-Host "NotifyToast: $NotifyToast"
Write-Host "LogPath: $LogPath"

# Write execution marker
$markerPath = Join-Path $env:TEMP "update-ultra-test-marker.txt"
"Executed at $(Get-Date)" | Out-File $markerPath

exit 0
'@ | Out-File $script:TestScriptPath -Encoding UTF8

    # Nazwa taska dla testów
    $script:TestTaskName = "UpdateUltra-IntegrationTest-$(Get-Random)"
}

AfterAll {
    # Cleanup: usuń test script
    if (Test-Path $script:TestScriptPath) {
        Remove-Item $script:TestScriptPath -Force -ErrorAction SilentlyContinue
    }

    # Cleanup: usuń test task jeśli istnieje
    $task = Get-ScheduledTask -TaskName $script:TestTaskName -ErrorAction SilentlyContinue
    if ($task) {
        Unregister-ScheduledTask -TaskName $script:TestTaskName -Confirm:$false -ErrorAction SilentlyContinue
    }

    # Cleanup: usuń execution marker
    $markerPath = Join-Path $env:TEMP "update-ultra-test-marker.txt"
    if (Test-Path $markerPath) {
        Remove-Item $markerPath -Force -ErrorAction SilentlyContinue
    }

    Remove-Module TaskScheduler -ErrorAction SilentlyContinue
}

Describe "TaskScheduler Integration Tests" {
    Context "Full lifecycle - Daily task" {
        It "Install-UpdateSchedule tworzy rzeczywisty scheduled task" {
            $installParams = @{
                Name = $script:TestTaskName
                RunAt = "03:00"
                Frequency = "Daily"
                ScriptPath = $script:TestScriptPath
                ScriptParameters = @{
                    EnableCache = $true
                    CacheTTL = 600
                }
            }

            $task = Install-UpdateSchedule @installParams

            $task | Should -Not -BeNullOrEmpty
            $task.TaskName | Should -Be $script:TestTaskName
        }

        It "Get-UpdateSchedule zwraca konfigurację utworzonego taska" {
            $schedule = Get-UpdateSchedule -Name $script:TestTaskName

            $schedule | Should -Not -BeNullOrEmpty
            $schedule.Name | Should -Be $script:TestTaskName
            $schedule.State | Should -Match "Ready|Running|Disabled"
            $schedule.Triggers | Should -Not -BeNullOrEmpty
            $schedule.Actions | Should -Not -BeNullOrEmpty
        }

        It "Test-UpdateSchedule waliduje poprawnie skonfigurowany task" {
            $validation = Test-UpdateSchedule -Name $script:TestTaskName

            $validation | Should -Not -BeNullOrEmpty
            $validation.Valid | Should -Be $true
            $validation.Issues | Should -BeNullOrEmpty
        }

        It "Scheduled task zawiera poprawne parametry skryptu" {
            $task = Get-ScheduledTask -TaskName $script:TestTaskName
            $action = $task.Actions[0]

            $action.Arguments | Should -Match "-EnableCache"
            $action.Arguments | Should -Match "-CacheTTL '600'"
        }

        It "Remove-UpdateSchedule usuwa task" {
            $result = Remove-UpdateSchedule -Name $script:TestTaskName

            $result | Should -Be $true

            # Sprawdź czy task nie istnieje
            $task = Get-ScheduledTask -TaskName $script:TestTaskName -ErrorAction SilentlyContinue
            $task | Should -BeNullOrEmpty
        }
    }

    Context "Full lifecycle - Weekly task" {
        BeforeAll {
            $script:WeeklyTaskName = "UpdateUltra-WeeklyTest-$(Get-Random)"
        }

        AfterAll {
            # Cleanup
            $task = Get-ScheduledTask -TaskName $script:WeeklyTaskName -ErrorAction SilentlyContinue
            if ($task) {
                Unregister-ScheduledTask -TaskName $script:WeeklyTaskName -Confirm:$false -ErrorAction SilentlyContinue
            }
        }

        It "Tworzy Weekly task z poprawnym dniem tygodnia" {
            $task = Install-UpdateSchedule -Name $script:WeeklyTaskName `
                -RunAt "04:00" -Frequency "Weekly" -DayOfWeek "Sunday" `
                -ScriptPath $script:TestScriptPath

            $task | Should -Not -BeNullOrEmpty

            # Sprawdź trigger
            $realTask = Get-ScheduledTask -TaskName $script:WeeklyTaskName
            $trigger = $realTask.Triggers[0]
            $trigger.DaysOfWeek | Should -Be "Sunday"
        }

        It "Get-UpdateSchedule zwraca informacje o Weekly task" {
            $schedule = Get-UpdateSchedule -Name $script:WeeklyTaskName

            $schedule.Name | Should -Be $script:WeeklyTaskName
            $schedule.Triggers[0].CimClass.CimClassName | Should -Match "Weekly"
        }
    }

    Context "Full lifecycle - Monthly task" {
        BeforeAll {
            $script:MonthlyTaskName = "UpdateUltra-MonthlyTest-$(Get-Random)"
        }

        AfterAll {
            # Cleanup
            $task = Get-ScheduledTask -TaskName $script:MonthlyTaskName -ErrorAction SilentlyContinue
            if ($task) {
                Unregister-ScheduledTask -TaskName $script:MonthlyTaskName -Confirm:$false -ErrorAction SilentlyContinue
            }
        }

        It "Tworzy Monthly task poprawnie" {
            $task = Install-UpdateSchedule -Name $script:MonthlyTaskName `
                -RunAt "02:00" -Frequency "Monthly" `
                -ScriptPath $script:TestScriptPath

            $task | Should -Not -BeNullOrEmpty

            $realTask = Get-ScheduledTask -TaskName $script:MonthlyTaskName
            $realTask | Should -Not -BeNullOrEmpty
        }
    }

    Context "Task conditions" {
        BeforeAll {
            $script:ConditionsTaskName = "UpdateUltra-ConditionsTest-$(Get-Random)"
        }

        AfterAll {
            # Cleanup
            $task = Get-ScheduledTask -TaskName $script:ConditionsTaskName -ErrorAction SilentlyContinue
            if ($task) {
                Unregister-ScheduledTask -TaskName $script:ConditionsTaskName -Confirm:$false -ErrorAction SilentlyContinue
            }
        }

        It "Ustawia task conditions poprawnie" {
            $conditions = @{
                RequireAC = $true
                RequireNetwork = $true
                RequireIdle = $false
            }

            $task = Install-UpdateSchedule -Name $script:ConditionsTaskName `
                -RunAt "03:30" -ScriptPath $script:TestScriptPath `
                -Conditions $conditions

            $realTask = Get-ScheduledTask -TaskName $script:ConditionsTaskName
            $settings = $realTask.Settings

            $settings.DisallowStartIfOnBatteries | Should -Be $true
            $settings.RunOnlyIfNetworkAvailable | Should -Be $true
            $settings.RunOnlyIfIdle | Should -Be $false
        }
    }

    Context "Task execution" {
        BeforeAll {
            $script:ExecutionTaskName = "UpdateUltra-ExecutionTest-$(Get-Random)"

            # Usuń marker jeśli istnieje
            $markerPath = Join-Path $env:TEMP "update-ultra-test-marker.txt"
            if (Test-Path $markerPath) {
                Remove-Item $markerPath -Force
            }
        }

        AfterAll {
            # Cleanup
            $task = Get-ScheduledTask -TaskName $script:ExecutionTaskName -ErrorAction SilentlyContinue
            if ($task) {
                Unregister-ScheduledTask -TaskName $script:ExecutionTaskName -Confirm:$false -ErrorAction SilentlyContinue
            }
        }

        It "Task można uruchomić ręcznie" -Skip {
            # UWAGA: Test oznaczony jako -Skip ponieważ wymaga interakcji lub długiego czekania
            # Można odblokować dla manual testing

            $task = Install-UpdateSchedule -Name $script:ExecutionTaskName `
                -RunAt "03:00" -ScriptPath $script:TestScriptPath

            # Uruchom task ręcznie
            Start-ScheduledTask -TaskName $script:ExecutionTaskName

            # Czekaj na zakończenie (timeout 30s)
            $timeout = 30
            $elapsed = 0
            while ($elapsed -lt $timeout) {
                $taskInfo = Get-ScheduledTaskInfo -TaskName $script:ExecutionTaskName
                if ($taskInfo.LastRunTime -gt (Get-Date).AddMinutes(-1)) {
                    break
                }
                Start-Sleep -Seconds 1
                $elapsed++
            }

            # Sprawdź czy skrypt został wykonany
            $markerPath = Join-Path $env:TEMP "update-ultra-test-marker.txt"
            Test-Path $markerPath | Should -Be $true
        }
    }

    Context "Error handling" {
        It "Test-UpdateSchedule wykrywa brak skryptu" {
            $badTaskName = "UpdateUltra-BadScriptTest-$(Get-Random)"

            # Utwórz task z nieistniejącym skryptem
            $nonExistentScript = "C:\NonExistent\Script-$(Get-Random).ps1"

            # Install powinno rzucić błąd (ValidateScript)
            {
                Install-UpdateSchedule -Name $badTaskName `
                    -RunAt "03:00" -ScriptPath $nonExistentScript
            } | Should -Throw
        }

        It "Get-UpdateSchedule zwraca null dla nieistniejącego taska" {
            $result = Get-UpdateSchedule -Name "NonExistent-Task-$(Get-Random)"
            $result | Should -BeNullOrEmpty
        }

        It "Remove-UpdateSchedule nie rzuca błędu dla nieistniejącego taska" {
            {
                Remove-UpdateSchedule -Name "NonExistent-Task-$(Get-Random)"
            } | Should -Not -Throw
        }

        It "Test-UpdateSchedule wykrywa uszkodzoną konfigurację" {
            $corruptedTaskName = "UpdateUltra-CorruptedTest-$(Get-Random)"

            # Utwórz task
            Install-UpdateSchedule -Name $corruptedTaskName `
                -RunAt "03:00" -ScriptPath $script:TestScriptPath

            # Zmodyfikuj task (usuń action)
            $task = Get-ScheduledTask -TaskName $corruptedTaskName
            $task.Actions.Clear()
            Set-ScheduledTask -InputObject $task | Out-Null

            # Test powinien wykryć problem
            $validation = Test-UpdateSchedule -Name $corruptedTaskName

            $validation.Valid | Should -Be $false
            $validation.Issues.Count | Should -BeGreaterThan 0

            # Cleanup
            Unregister-ScheduledTask -TaskName $corruptedTaskName -Confirm:$false -ErrorAction SilentlyContinue
        }
    }

    Context "Multiple parameters handling" {
        BeforeAll {
            $script:MultiParamTaskName = "UpdateUltra-MultiParamTest-$(Get-Random)"
        }

        AfterAll {
            # Cleanup
            $task = Get-ScheduledTask -TaskName $script:MultiParamTaskName -ErrorAction SilentlyContinue
            if ($task) {
                Unregister-ScheduledTask -TaskName $script:MultiParamTaskName -Confirm:$false -ErrorAction SilentlyContinue
            }
        }

        It "Przekazuje wiele różnych typów parametrów" {
            $params = @{
                EnableCache = $true
                CacheTTL = 1200
                NotifyToast = $true
                LogPath = "C:\Logs\test.log"
            }

            $task = Install-UpdateSchedule -Name $script:MultiParamTaskName `
                -RunAt "05:00" -ScriptPath $script:TestScriptPath `
                -ScriptParameters $params

            $realTask = Get-ScheduledTask -TaskName $script:MultiParamTaskName
            $action = $realTask.Actions[0]

            # Sprawdź wszystkie parametry w arguments
            $action.Arguments | Should -Match "-EnableCache"
            $action.Arguments | Should -Match "-CacheTTL '1200'"
            $action.Arguments | Should -Match "-NotifyToast"
            $action.Arguments | Should -Match "-LogPath 'C:\\Logs\\test.log'"
        }
    }
}
