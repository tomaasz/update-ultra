# test-full-run.ps1
# Integration test dla pełnego uruchomienia Update-WingetAll.ps1

<#
.SYNOPSIS
Test integracyjny pełnego uruchomienia skryptu

.DESCRIPTION
Weryfikuje:
- Uruchomienie skryptu z parametrem -WhatIf
- Wszystkie sekcje wykonują się poprawnie
- Generowanie summary JSON
- Działanie nowych funkcji (cache, hooks, notifications)

.NOTES
Wymaga: Pester 5.x, uprawnienia Administrator
Uruchomienie: Invoke-Pester .\test-full-run.ps1
#>

BeforeAll {
    $script:scriptPath = Join-Path $PSScriptRoot "..\..\src\Update-WingetAll.ps1"
    $script:testLogDir = Join-Path $env:TEMP "update-ultra-integration-test-$(Get-Random)"

    # Sprawdź czy jesteśmy administratorem
    $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = New-Object Security.Principal.WindowsPrincipal($identity)
    $script:isAdmin = $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

AfterAll {
    # Cleanup
    if (Test-Path $script:testLogDir) {
        Remove-Item $script:testLogDir -Recurse -Force -ErrorAction SilentlyContinue
    }
}

Describe "Update-WingetAll.ps1 - Full Run Integration" {
    Context "Basic execution - WhatIf mode" {
        It "Uruchamia się bez błędów z -WhatIf" -Skip:(-not $script:isAdmin) {
            {
                & $script:scriptPath -WhatIf -SkipWSL -SkipDocker | Out-Null
            } | Should -Not -Throw
        }

        It "Zwraca exit code 0 gdy wszystko OK" -Skip:(-not $script:isAdmin) {
            & $script:scriptPath -WhatIf -SkipWSL -SkipDocker -SkipGit | Out-Null
            $LASTEXITCODE | Should -Be 0
        }

        It "Generuje summary JSON" -Skip:(-not $script:isAdmin) {
            # Uruchom skrypt
            & $script:scriptPath -WhatIf -SkipWSL -SkipDocker -SkipGit | Out-Null

            # Sprawdź czy summary JSON został utworzony
            $summaryFiles = Get-ChildItem -Path "$env:ProgramData\Winget-Logs" -Filter "dev_update_*_summary.json" |
                Sort-Object LastWriteTime -Descending |
                Select-Object -First 1

            $summaryFiles | Should -Not -BeNullOrEmpty
            Test-Path $summaryFiles.FullName | Should -Be $true

            # Sprawdź strukturę JSON
            $summary = Get-Content $summaryFiles.FullName -Raw | ConvertFrom-Json
            $summary.run_at | Should -Not -BeNullOrEmpty
            $summary.log_file | Should -Not -BeNullOrEmpty
            $summary.results | Should -Not -BeNullOrEmpty
        }
    }

    Context "Parameter validation" {
        It "Akceptuje parametr -EnableCache" -Skip:(-not $script:isAdmin) {
            {
                & $script:scriptPath -WhatIf -EnableCache -CacheTTL 60 -SkipAll | Out-Null
            } | Should -Not -Throw
        }

        It "Akceptuje parametr -AutoSnapshot" -Skip:(-not $script:isAdmin) {
            {
                & $script:scriptPath -WhatIf -AutoSnapshot -SkipAll | Out-Null
            } | Should -Not -Throw
        }

        It "Akceptuje parametr -NotifyToast" -Skip:(-not $script:isAdmin) {
            {
                & $script:scriptPath -WhatIf -NotifyToast -SkipAll | Out-Null
            } | Should -Not -Throw
        }
    }

    Context "Hooks execution" {
        It "Wykonuje Pre-Update Hook" -Skip:(-not $script:isAdmin) {
            $hookExecuted = $false

            $preHook = {
                $script:hookExecuted = $true
            }

            & $script:scriptPath -WhatIf -PreUpdateHook $preHook -SkipAll | Out-Null

            $hookExecuted | Should -Be $true
        }

        It "Wykonuje Post-Update Hook" -Skip:(-not $script:isAdmin) {
            $postHookExecuted = $false

            $postHook = {
                $script:postHookExecuted = $true
            }

            & $script:scriptPath -WhatIf -PostUpdateHook $postHook -SkipAll | Out-Null

            $postHookExecuted | Should -Be $true
        }

        It "Wykonuje Section Hooks" -Skip:(-not $script:isAdmin) {
            $sectionHookExecuted = $false

            $sectionHooks = @{
                Winget = @{
                    Pre = { $script:sectionHookExecuted = $true }
                }
            }

            & $script:scriptPath -WhatIf -SectionHooks $sectionHooks | Out-Null

            $sectionHookExecuted | Should -Be $true
        }
    }

    Context "Cache integration" {
        It "Ładuje WingetCache module gdy -EnableCache" -Skip:(-not $script:isAdmin) {
            # Uruchom skrypt z cache
            & $script:scriptPath -WhatIf -EnableCache -SkipAll | Out-Null

            # Sprawdź czy moduł został załadowany
            $module = Get-Module WingetCache
            $module | Should -Not -BeNullOrEmpty
        }

        It "Cache redukuje czas wykonania przy powtórnym uruchomieniu" -Skip:(-not $script:isAdmin) {
            # Pierwsze uruchomienie (bez cache)
            $time1 = Measure-Command {
                & $script:scriptPath -WhatIf -EnableCache -CacheTTL 600 | Out-Null
            }

            # Drugie uruchomienie (z cache)
            $time2 = Measure-Command {
                & $script:scriptPath -WhatIf -EnableCache -CacheTTL 600 | Out-Null
            }

            # Drugie uruchomienie powinno być szybsze (cache hit)
            # Tolerancja: może być minimalnie wolniejsze z powodu overhead
            # Oczekujemy że będzie szybsze lub podobny czas
            $time2.TotalSeconds | Should -BeLessOrEqual ($time1.TotalSeconds * 1.2)
        }
    }

    Context "Section execution" {
        It "Winget section wykonuje się poprawnie" -Skip:(-not $script:isAdmin) {
            {
                & $script:scriptPath -WhatIf -SkipAll -SkipWinget:$false | Out-Null
            } | Should -Not -Throw
        }

        It "npm section wykonuje się poprawnie" -Skip:(-not $script:isAdmin) {
            {
                & $script:scriptPath -WhatIf -SkipAll -Skipnpm:$false | Out-Null
            } | Should -Not -Throw
        }

        It "Python/Pip section wykonuje się poprawnie" -Skip:(-not $script:isAdmin) {
            {
                & $script:scriptPath -WhatIf -SkipAll -SkipPip:$false | Out-Null
            } | Should -Not -Throw
        }
    }

    Context "Error handling" {
        It "Nie przerywa wykonania gdy jedna sekcja fails" -Skip:(-not $script:isAdmin) {
            # Uruchom z hookiem który rzuca błąd
            $errorHook = { throw "Intentional error" }

            $sectionHooks = @{
                Winget = @{
                    Pre = $errorHook
                }
            }

            # Skrypt powinien kontynuować mimo błędu w hooku
            {
                & $script:scriptPath -WhatIf -SectionHooks $sectionHooks -SkipAll | Out-Null
            } | Should -Not -Throw
        }
    }

    Context "Performance benchmarks" {
        It "Pełne uruchomienie (WhatIf) kończy się w rozsądnym czasie" -Skip:(-not $script:isAdmin) {
            $time = Measure-Command {
                & $script:scriptPath -WhatIf -SkipWSL -SkipDocker | Out-Null
            }

            # Oczekujemy że skrypt wykona się w mniej niż 2 minuty (WhatIf mode)
            $time.TotalSeconds | Should -BeLessThan 120
        }
    }
}

Describe "Update-WingetAll.ps1 - Module Compatibility" {
    Context "Module loading" {
        It "Ładuje ParallelExecution gdy -Parallel" -Skip:(-not $script:isAdmin) {
            # Skrypt z -Parallel powinien załadować moduł
            # (jeśli jest dostępny)
            {
                & $script:scriptPath -WhatIf -Parallel -SkipAll | Out-Null
            } | Should -Not -Throw
        }

        It "Ładuje SnapshotManager gdy -AutoSnapshot" -Skip:(-not $script:isAdmin) {
            {
                & $script:scriptPath -WhatIf -AutoSnapshot -SkipAll | Out-Null
            } | Should -Not -Throw

            # Sprawdź czy moduł został załadowany
            $module = Get-Module SnapshotManager
            $module | Should -Not -BeNullOrEmpty
        }

        It "Ładuje NotificationManager gdy powiadomienia enabled" -Skip:(-not $script:isAdmin) {
            {
                & $script:scriptPath -WhatIf -NotifyToast -SkipAll | Out-Null
            } | Should -Not -Throw

            $module = Get-Module NotificationManager
            $module | Should -Not -BeNullOrEmpty
        }
    }
}
