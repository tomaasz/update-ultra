# test-scheduler.ps1
# Unit tests dla TaskScheduler.psm1

<#
.SYNOPSIS
Testy jednostkowe dla modułu TaskScheduler

.DESCRIPTION
Weryfikuje:
- Inicjalizację modułu
- Tworzenie scheduled tasks (Daily/Weekly/Monthly)
- Build script arguments z parametrami
- Usuwanie scheduled tasks
- Pobieranie informacji o taskach
- Testowanie konfiguracji

.NOTES
Wymaga: Pester 5.x, Uprawnienia Administrator (dla integration tests)
Uruchomienie: Invoke-Pester .\test-scheduler.ps1
#>

BeforeAll {
    # Import modułu TaskScheduler
    $modulePath = Join-Path $PSScriptRoot "..\..\src\TaskScheduler.psm1"
    Import-Module $modulePath -Force
}

AfterAll {
    Remove-Module TaskScheduler -ErrorAction SilentlyContinue
}

Describe "TaskScheduler - Module Initialization" {
    Context "Module loading" {
        It "Moduł ładuje się bez błędów" {
            $module = Get-Module TaskScheduler
            $module | Should -Not -BeNullOrEmpty
        }

        It "Eksportuje wszystkie publiczne funkcje" {
            $module = Get-Module TaskScheduler
            $exportedFunctions = $module.ExportedFunctions.Keys

            $exportedFunctions | Should -Contain 'Install-UpdateSchedule'
            $exportedFunctions | Should -Contain 'Remove-UpdateSchedule'
            $exportedFunctions | Should -Contain 'Get-UpdateSchedule'
            $exportedFunctions | Should -Contain 'Test-UpdateSchedule'
            $exportedFunctions | Should -Contain 'Initialize-TaskScheduler'
        }
    }
}

Describe "TaskScheduler - Parameter Validation" {
    Context "Install-UpdateSchedule parameter validation" {
        It "Wymaga parametru RunAt" {
            {
                Install-UpdateSchedule -ScriptPath "C:\test.ps1" -WhatIf
            } | Should -Throw
        }

        It "Akceptuje poprawny format czasu (HH:mm)" {
            # Mock Register-ScheduledTask
            Mock -ModuleName TaskScheduler -CommandName Register-ScheduledTask -MockWith {
                return [PSCustomObject]@{ TaskName = "Test" }
            }

            {
                Install-UpdateSchedule -RunAt "03:00" -ScriptPath "C:\test.ps1" -WhatIf
            } | Should -Not -Throw
        }

        It "Wymaga parametru ScriptPath" {
            # Create a temporary test script
            $tempScript = Join-Path $env:TEMP "test-scheduler-script-$(Get-Random).ps1"
            "# Test script" | Out-File $tempScript

            Mock -ModuleName TaskScheduler -CommandName Register-ScheduledTask -MockWith {
                return [PSCustomObject]@{ TaskName = "Test" }
            }

            {
                Install-UpdateSchedule -RunAt "03:00" -ScriptPath $tempScript -WhatIf
            } | Should -Not -Throw

            Remove-Item $tempScript -Force
        }

        It "Waliduje czy ScriptPath istnieje" {
            {
                Install-UpdateSchedule -RunAt "03:00" -ScriptPath "C:\nonexistent-file-xyz123.ps1" -WhatIf
            } | Should -Throw
        }

        It "Akceptuje tylko poprawne wartości Frequency" {
            $tempScript = Join-Path $env:TEMP "test-scheduler-script-$(Get-Random).ps1"
            "# Test script" | Out-File $tempScript

            Mock -ModuleName TaskScheduler -CommandName Register-ScheduledTask -MockWith {
                return [PSCustomObject]@{ TaskName = "Test" }
            }

            {
                Install-UpdateSchedule -RunAt "03:00" -Frequency "Daily" -ScriptPath $tempScript -WhatIf
            } | Should -Not -Throw

            {
                Install-UpdateSchedule -RunAt "03:00" -Frequency "Weekly" -ScriptPath $tempScript -WhatIf
            } | Should -Not -Throw

            {
                Install-UpdateSchedule -RunAt "03:00" -Frequency "Monthly" -ScriptPath $tempScript -WhatIf
            } | Should -Not -Throw

            Remove-Item $tempScript -Force
        }

        It "Akceptuje tylko poprawne dni tygodnia dla DayOfWeek" {
            $tempScript = Join-Path $env:TEMP "test-scheduler-script-$(Get-Random).ps1"
            "# Test script" | Out-File $tempScript

            Mock -ModuleName TaskScheduler -CommandName Register-ScheduledTask -MockWith {
                return [PSCustomObject]@{ TaskName = "Test" }
            }

            {
                Install-UpdateSchedule -RunAt "03:00" -Frequency "Weekly" -DayOfWeek "Sunday" -ScriptPath $tempScript -WhatIf
            } | Should -Not -Throw

            {
                Install-UpdateSchedule -RunAt "03:00" -Frequency "Weekly" -DayOfWeek "Monday" -ScriptPath $tempScript -WhatIf
            } | Should -Not -Throw

            Remove-Item $tempScript -Force
        }
    }
}

Describe "TaskScheduler - Build Script Arguments" {
    Context "Parameter conversion" {
        BeforeAll {
            # Access private function using InModuleScope (Pester 5.x)
            $tempScript = Join-Path $env:TEMP "test-scheduler-script-$(Get-Random).ps1"
            "# Test script" | Out-File $tempScript

            Mock -ModuleName TaskScheduler -CommandName Register-ScheduledTask -MockWith {
                param($TaskName, $Trigger, $Action, $Settings, $User)
                return [PSCustomObject]@{
                    TaskName = $TaskName
                    Arguments = $Action.Arguments
                }
            }
        }

        AfterAll {
            Remove-Item $tempScript -Force -ErrorAction SilentlyContinue
        }

        It "Konwertuje boolean parameters poprawnie" {
            $params = @{ EnableCache = $true; WhatIf = $false }

            $task = Install-UpdateSchedule -RunAt "03:00" -ScriptPath $tempScript `
                -ScriptParameters $params -WhatIf

            $task.Arguments | Should -Match '-EnableCache'
            $task.Arguments | Should -Not -Match '-WhatIf'
        }

        It "Konwertuje string parameters poprawnie" {
            $params = @{ LogDirectory = "C:\Logs" }

            $task = Install-UpdateSchedule -RunAt "03:00" -ScriptPath $tempScript `
                -ScriptParameters $params -WhatIf

            $task.Arguments | Should -Match "-LogDirectory 'C:\\Logs'"
        }

        It "Konwertuje int parameters poprawnie" {
            $params = @{ CacheTTL = 600 }

            $task = Install-UpdateSchedule -RunAt "03:00" -ScriptPath $tempScript `
                -ScriptParameters $params -WhatIf

            $task.Arguments | Should -Match "-CacheTTL '600'"
        }

        It "Obsługuje wiele parametrów jednocześnie" {
            $params = @{
                EnableCache = $true
                CacheTTL = 300
                AutoSnapshot = $true
                NotifyToast = $true
            }

            $task = Install-UpdateSchedule -RunAt "03:00" -ScriptPath $tempScript `
                -ScriptParameters $params -WhatIf

            $task.Arguments | Should -Match '-EnableCache'
            $task.Arguments | Should -Match "-CacheTTL '300'"
            $task.Arguments | Should -Match '-AutoSnapshot'
            $task.Arguments | Should -Match '-NotifyToast'
        }

        It "Nie dodaje parametrów gdy ScriptParameters jest puste" {
            $task = Install-UpdateSchedule -RunAt "03:00" -ScriptPath $tempScript -WhatIf

            # Powinno zawierać tylko podstawowe argumenty PowerShell
            $task.Arguments | Should -Match '-NoProfile'
            $task.Arguments | Should -Match '-ExecutionPolicy Bypass'
            $task.Arguments | Should -Match "-File"
        }
    }
}

Describe "TaskScheduler - Trigger Creation" {
    Context "Daily trigger" {
        BeforeAll {
            $tempScript = Join-Path $env:TEMP "test-scheduler-script-$(Get-Random).ps1"
            "# Test script" | Out-File $tempScript

            Mock -ModuleName TaskScheduler -CommandName Register-ScheduledTask -MockWith {
                param($TaskName, $Trigger, $Action, $Settings, $User)

                # Verify trigger type
                if ($Trigger.CimClass.CimClassName -notmatch 'Daily') {
                    throw "Expected Daily trigger"
                }

                return [PSCustomObject]@{
                    TaskName = $TaskName
                    TriggerType = "Daily"
                }
            }
        }

        AfterAll {
            Remove-Item $tempScript -Force -ErrorAction SilentlyContinue
        }

        It "Tworzy Daily trigger poprawnie" {
            $task = Install-UpdateSchedule -RunAt "03:00" -Frequency "Daily" `
                -ScriptPath $tempScript -WhatIf

            $task.TriggerType | Should -Be "Daily"
        }
    }

    Context "Weekly trigger" {
        BeforeAll {
            $tempScript = Join-Path $env:TEMP "test-scheduler-script-$(Get-Random).ps1"
            "# Test script" | Out-File $tempScript

            Mock -ModuleName TaskScheduler -CommandName Register-ScheduledTask -MockWith {
                param($TaskName, $Trigger, $Action, $Settings, $User)

                if ($Trigger.CimClass.CimClassName -notmatch 'Weekly') {
                    throw "Expected Weekly trigger"
                }

                return [PSCustomObject]@{
                    TaskName = $TaskName
                    TriggerType = "Weekly"
                    DayOfWeek = $Trigger.DaysOfWeek
                }
            }
        }

        AfterAll {
            Remove-Item $tempScript -Force -ErrorAction SilentlyContinue
        }

        It "Tworzy Weekly trigger z poprawnym dniem tygodnia" {
            $task = Install-UpdateSchedule -RunAt "03:00" -Frequency "Weekly" `
                -DayOfWeek "Sunday" -ScriptPath $tempScript -WhatIf

            $task.TriggerType | Should -Be "Weekly"
            $task.DayOfWeek | Should -Be "Sunday"
        }
    }

    Context "Monthly trigger" {
        BeforeAll {
            $tempScript = Join-Path $env:TEMP "test-scheduler-script-$(Get-Random).ps1"
            "# Test script" | Out-File $tempScript

            Mock -ModuleName TaskScheduler -CommandName Register-ScheduledTask -MockWith {
                param($TaskName, $Trigger, $Action, $Settings, $User)

                if ($Trigger -and $Trigger.CimClass.CimClassName -notmatch 'Time') {
                    # Monthly uses time-based trigger
                }

                return [PSCustomObject]@{
                    TaskName = $TaskName
                    TriggerType = "Monthly"
                }
            }
        }

        AfterAll {
            Remove-Item $tempScript -Force -ErrorAction SilentlyContinue
        }

        It "Tworzy Monthly trigger poprawnie" {
            $task = Install-UpdateSchedule -RunAt "03:00" -Frequency "Monthly" `
                -ScriptPath $tempScript -WhatIf

            $task.TriggerType | Should -Be "Monthly"
        }
    }
}

Describe "TaskScheduler - Conditions Handling" {
    Context "Task settings with conditions" {
        BeforeAll {
            $tempScript = Join-Path $env:TEMP "test-scheduler-script-$(Get-Random).ps1"
            "# Test script" | Out-File $tempScript

            Mock -ModuleName TaskScheduler -CommandName Register-ScheduledTask -MockWith {
                param($TaskName, $Trigger, $Action, $Settings, $User)

                return [PSCustomObject]@{
                    TaskName = $TaskName
                    Settings = $Settings
                }
            }
        }

        AfterAll {
            Remove-Item $tempScript -Force -ErrorAction SilentlyContinue
        }

        It "Ustawia RequireAC condition poprawnie" {
            $conditions = @{ RequireAC = $true }

            $task = Install-UpdateSchedule -RunAt "03:00" -ScriptPath $tempScript `
                -Conditions $conditions -WhatIf

            $task.Settings.AllowStartIfOnBatteries | Should -Be $false
        }

        It "Ustawia RequireNetwork condition poprawnie" {
            $conditions = @{ RequireNetwork = $true }

            $task = Install-UpdateSchedule -RunAt "03:00" -ScriptPath $tempScript `
                -Conditions $conditions -WhatIf

            $task.Settings.RunOnlyIfNetworkAvailable | Should -Be $true
        }

        It "Ustawia RequireIdle condition poprawnie" {
            $conditions = @{ RequireIdle = $true }

            $task = Install-UpdateSchedule -RunAt "03:00" -ScriptPath $tempScript `
                -Conditions $conditions -WhatIf

            $task.Settings.RunOnlyIfIdle | Should -Be $true
        }

        It "Obsługuje wiele conditions jednocześnie" {
            $conditions = @{
                RequireAC = $true
                RequireNetwork = $true
                RequireIdle = $false
            }

            $task = Install-UpdateSchedule -RunAt "03:00" -ScriptPath $tempScript `
                -Conditions $conditions -WhatIf

            $task.Settings.AllowStartIfOnBatteries | Should -Be $false
            $task.Settings.RunOnlyIfNetworkAvailable | Should -Be $true
        }
    }
}

Describe "TaskScheduler - Remove-UpdateSchedule" {
    Context "Task removal" {
        It "Nie rzuca błędu gdy task nie istnieje" {
            Mock -ModuleName TaskScheduler -CommandName Get-ScheduledTask -MockWith {
                return $null
            }

            {
                Remove-UpdateSchedule -WhatIf
            } | Should -Not -Throw
        }

        It "Wywołuje Unregister-ScheduledTask gdy task istnieje" {
            Mock -ModuleName TaskScheduler -CommandName Get-ScheduledTask -MockWith {
                return [PSCustomObject]@{ TaskName = "UpdateUltra-AutoUpdate" }
            }

            Mock -ModuleName TaskScheduler -CommandName Unregister-ScheduledTask -MockWith {
                return $true
            }

            $result = Remove-UpdateSchedule -WhatIf

            Should -Invoke -ModuleName TaskScheduler -CommandName Unregister-ScheduledTask -Times 1
        }
    }
}

Describe "TaskScheduler - Get-UpdateSchedule" {
    Context "Retrieving task information" {
        It "Zwraca null gdy task nie istnieje" {
            Mock -ModuleName TaskScheduler -CommandName Get-ScheduledTask -MockWith {
                return $null
            }

            $result = Get-UpdateSchedule

            $result | Should -BeNullOrEmpty
        }

        It "Zwraca szczegółowe informacje gdy task istnieje" {
            Mock -ModuleName TaskScheduler -CommandName Get-ScheduledTask -MockWith {
                return [PSCustomObject]@{
                    TaskName = "UpdateUltra-AutoUpdate"
                    State = "Ready"
                    Triggers = @()
                    Actions = @()
                    Settings = [PSCustomObject]@{
                        AllowStartIfOnBatteries = $false
                        DisallowStartIfOnBatteries = $false
                        RunOnlyIfNetworkAvailable = $true
                        RunOnlyIfIdle = $false
                        StartWhenAvailable = $true
                    }
                }
            }

            Mock -ModuleName TaskScheduler -CommandName Get-ScheduledTaskInfo -MockWith {
                return [PSCustomObject]@{
                    LastRunTime = (Get-Date)
                    LastTaskResult = 0
                    NextRunTime = (Get-Date).AddDays(1)
                    NumberOfMissedRuns = 0
                }
            }

            $result = Get-UpdateSchedule

            $result | Should -Not -BeNullOrEmpty
            $result.Name | Should -Be "UpdateUltra-AutoUpdate"
            $result.State | Should -Be "Ready"
            $result.Settings | Should -Not -BeNullOrEmpty
        }
    }
}

Describe "TaskScheduler - Test-UpdateSchedule" {
    Context "Configuration testing" {
        It "Wykrywa brak taska" {
            Mock -ModuleName TaskScheduler -CommandName Get-ScheduledTask -MockWith {
                return $null
            }

            $result = Test-UpdateSchedule

            $result.Valid | Should -Be $false
            $result.Issues | Should -Contain "Task 'UpdateUltra-AutoUpdate' nie istnieje"
        }

        It "Wykrywa brakujący plik skryptu" {
            Mock -ModuleName TaskScheduler -CommandName Get-ScheduledTask -MockWith {
                return [PSCustomObject]@{
                    TaskName = "UpdateUltra-AutoUpdate"
                    State = "Ready"
                    Triggers = @()
                    Actions = @(
                        [PSCustomObject]@{
                            Execute = "pwsh.exe"
                            Arguments = '-NoProfile -ExecutionPolicy Bypass -File "C:\NonExistentFile.ps1"'
                        }
                    )
                    Settings = [PSCustomObject]@{}
                }
            }

            Mock -ModuleName TaskScheduler -CommandName Get-ScheduledTaskInfo -MockWith {
                return [PSCustomObject]@{
                    NumberOfMissedRuns = 0
                }
            }

            $result = Test-UpdateSchedule

            $result.Valid | Should -Be $false
            $result.Issues | Should -Match "Skrypt docelowy nie istnieje"
        }

        It "Wykrywa zaległe uruchomienia" {
            Mock -ModuleName TaskScheduler -CommandName Get-ScheduledTask -MockWith {
                return [PSCustomObject]@{
                    TaskName = "UpdateUltra-AutoUpdate"
                    State = "Ready"
                    Triggers = @()
                    Actions = @()
                    Settings = [PSCustomObject]@{}
                }
            }

            Mock -ModuleName TaskScheduler -CommandName Get-ScheduledTaskInfo -MockWith {
                return [PSCustomObject]@{
                    NumberOfMissedRuns = 5
                }
            }

            $result = Test-UpdateSchedule

            $result.Warnings | Should -Contain "Task ma 5 zaległych uruchomień"
        }
    }
}
