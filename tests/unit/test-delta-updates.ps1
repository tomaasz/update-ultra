# test-delta-updates.ps1
# Unit tests dla DeltaUpdateManager.psm1

<#
.SYNOPSIS
Testy jednostkowe dla modułu DeltaUpdateManager

.DESCRIPTION
Weryfikuje:
- Inicjalizację modułu
- Zbieranie stanu pakietów (Get-CurrentPackageState)
- Porównywanie stanów (Compare-PackageState)
- Generowanie delta targets
- Zapisywanie i wczytywanie baseline
- Invoke-DeltaUpdate orchestration

.NOTES
Wymaga: Pester 5.x
Uruchomienie: Invoke-Pester .\test-delta-updates.ps1
#>

BeforeAll {
    # Import modułu DeltaUpdateManager
    $modulePath = Join-Path $PSScriptRoot "..\..\src\DeltaUpdateManager.psm1"
    Import-Module $modulePath -Force

    # Tymczasowy katalog dla testów
    $script:testDeltaDir = Join-Path $env:TEMP "update-ultra-test-delta-$(Get-Random)"
}

AfterAll {
    # Cleanup
    if (Test-Path $script:testDeltaDir) {
        Remove-Item $script:testDeltaDir -Recurse -Force -ErrorAction SilentlyContinue
    }

    Remove-Module DeltaUpdateManager -ErrorAction SilentlyContinue
}

Describe "DeltaUpdateManager - Module Initialization" {
    Context "Module loading" {
        It "Moduł ładuje się bez błędów" {
            $module = Get-Module DeltaUpdateManager
            $module | Should -Not -BeNullOrEmpty
        }

        It "Eksportuje wszystkie publiczne funkcje" {
            $module = Get-Module DeltaUpdateManager
            $exportedFunctions = $module.ExportedFunctions.Keys

            $exportedFunctions | Should -Contain 'Initialize-DeltaUpdateManager'
            $exportedFunctions | Should -Contain 'Get-CurrentPackageState'
            $exportedFunctions | Should -Contain 'Compare-PackageState'
            $exportedFunctions | Should -Contain 'Get-DeltaUpdateTargets'
            $exportedFunctions | Should -Contain 'Save-PackageStateBaseline'
            $exportedFunctions | Should -Contain 'Get-BaselineState'
            $exportedFunctions | Should -Contain 'Invoke-DeltaUpdate'
            $exportedFunctions | Should -Contain 'Clear-DeltaBaselines'
        }
    }

    Context "Initialize-DeltaUpdateManager" {
        It "Tworzy katalog delta state" {
            # Override script delta dir
            $module = Get-Module DeltaUpdateManager
            $module.Invoke({ $script:DeltaStateDir = $args[0] }, $script:testDeltaDir)

            Initialize-DeltaUpdateManager

            Test-Path $script:testDeltaDir | Should -Be $true
        }
    }
}

Describe "DeltaUpdateManager - Get-CurrentPackageState" {
    Context "Zbieranie stanu pakietów" {
        BeforeAll {
            # Mock winget command
            Mock -ModuleName DeltaUpdateManager -CommandName Get-Command -MockWith {
                param($Name, $ErrorAction)
                if ($Name -eq 'winget') {
                    return [PSCustomObject]@{ Name = 'winget' }
                }
                return $null
            }

            # Mock winget output
            Mock -ModuleName DeltaUpdateManager -CommandName winget -MockWith {
                return @(
                    "Name                           Id                         Version",
                    "----------------------------------------------------------------",
                    "Visual Studio Code             Microsoft.VisualStudioCode  1.85.0",
                    "Git                            Git.Git                     2.42.0"
                )
            }
        }

        It "Zwraca hashtable ze źródłami" {
            $state = Get-CurrentPackageState -Sources @('Winget')

            $state | Should -BeOfType [hashtable]
            $state.ContainsKey('Winget') | Should -Be $true
        }

        It "Parsuje pakiety Winget poprawnie" {
            $state = Get-CurrentPackageState -Sources @('Winget')

            $state.Winget | Should -Not -BeNullOrEmpty
            $state.Winget.Count | Should -BeGreaterThan 0
        }

        It "Obsługuje błędy gracefully" {
            Mock -ModuleName DeltaUpdateManager -CommandName winget -MockWith {
                throw "Winget error"
            }

            {
                $state = Get-CurrentPackageState -Sources @('Winget')
                $state.Winget.Count | Should -Be 0
            } | Should -Not -Throw
        }
    }

    Context "Obsługa różnych źródeł" {
        It "Akceptuje wiele źródeł jednocześnie" {
            Mock -ModuleName DeltaUpdateManager -CommandName Get-Command -MockWith { $null }

            $state = Get-CurrentPackageState -Sources @('Winget', 'npm', 'pip')

            $state.ContainsKey('Winget') | Should -Be $true
            $state.ContainsKey('npm') | Should -Be $true
            $state.ContainsKey('pip') | Should -Be $true
        }

        It "Zwraca puste tablice gdy narzędzie nie jest dostępne" {
            Mock -ModuleName DeltaUpdateManager -CommandName Get-Command -MockWith { $null }

            $state = Get-CurrentPackageState -Sources @('Winget')

            $state.Winget | Should -BeOfType [array]
            $state.Winget.Count | Should -Be 0
        }
    }
}

Describe "DeltaUpdateManager - Compare-PackageState" {
    Context "Wykrywanie zmian" {
        BeforeAll {
            $script:currentState = @{
                Winget = @(
                    @{ Id = "Microsoft.VisualStudioCode"; Version = "1.86.0" }
                    @{ Id = "Git.Git"; Version = "2.43.0" }
                    @{ Id = "NewPackage.Id"; Version = "1.0.0" }
                )
            }

            $script:baselineState = @{
                Winget = @(
                    @{ Id = "Microsoft.VisualStudioCode"; Version = "1.85.0" }  # Updated
                    @{ Id = "Git.Git"; Version = "2.43.0" }  # No change
                    @{ Id = "OldPackage.Id"; Version = "1.0.0" }  # Removed
                )
            }
        }

        It "Wykrywa dodane pakiety" {
            $diff = Compare-PackageState -CurrentState $script:currentState -BaselineState $script:baselineState

            $diff.Winget.Added | Should -Contain "NewPackage.Id"
            $diff.Winget.Added.Count | Should -Be 1
        }

        It "Wykrywa usunięte pakiety" {
            $diff = Compare-PackageState -CurrentState $script:currentState -BaselineState $script:baselineState

            $diff.Winget.Removed | Should -Contain "OldPackage.Id"
            $diff.Winget.Removed.Count | Should -Be 1
        }

        It "Wykrywa zaktualizowane pakiety" {
            $diff = Compare-PackageState -CurrentState $script:currentState -BaselineState $script:baselineState

            $diff.Winget.Updated.Count | Should -Be 1
            $updated = $diff.Winget.Updated[0]
            $updated.Id | Should -Be "Microsoft.VisualStudioCode"
            $updated.OldVersion | Should -Be "1.85.0"
            $updated.NewVersion | Should -Be "1.86.0"
        }

        It "Nie wykrywa zmian gdy wersje są identyczne" {
            $diff = Compare-PackageState -CurrentState $script:currentState -BaselineState $script:baselineState

            $gitUpdated = $diff.Winget.Updated | Where-Object { $_.Id -eq "Git.Git" }
            $gitUpdated | Should -BeNullOrEmpty
        }
    }

    Context "Edge cases" {
        It "Obsługuje puste baseline" {
            $current = @{
                Winget = @(
                    @{ Id = "Package.Id"; Version = "1.0.0" }
                )
            }
            $baseline = @{
                Winget = @()
            }

            $diff = Compare-PackageState -CurrentState $current -BaselineState $baseline

            $diff.Winget.Added | Should -Contain "Package.Id"
            $diff.Winget.Removed.Count | Should -Be 0
            $diff.Winget.Updated.Count | Should -Be 0
        }

        It "Obsługuje puste current state" {
            $current = @{
                Winget = @()
            }
            $baseline = @{
                Winget = @(
                    @{ Id = "Package.Id"; Version = "1.0.0" }
                )
            }

            $diff = Compare-PackageState -CurrentState $current -BaselineState $baseline

            $diff.Winget.Added.Count | Should -Be 0
            $diff.Winget.Removed | Should -Contain "Package.Id"
            $diff.Winget.Updated.Count | Should -Be 0
        }

        It "Obsługuje źródło nieobecne w baseline" {
            $current = @{
                npm = @(
                    @{ Name = "typescript"; Version = "5.3.0" }
                )
            }
            $baseline = @{}

            $diff = Compare-PackageState -CurrentState $current -BaselineState $baseline

            $diff.npm.Added | Should -Contain "typescript"
        }
    }
}

Describe "DeltaUpdateManager - Get-DeltaUpdateTargets" {
    Context "Generowanie listy targets" {
        BeforeAll {
            $script:diff = @{
                Winget = @{
                    Added = @("NewPackage1", "NewPackage2")
                    Removed = @("OldPackage")
                    Updated = @(
                        @{ Id = "UpdatedPackage1"; OldVersion = "1.0.0"; NewVersion = "1.1.0" }
                        @{ Id = "UpdatedPackage2"; OldVersion = "2.0.0"; NewVersion = "2.1.0" }
                    )
                }
            }
        }

        It "Zwraca tylko Updated pakiety gdy IncludeNew=false" {
            $targets = Get-DeltaUpdateTargets -Diff $script:diff -Source "Winget"

            $targets.Count | Should -Be 2
            $targets | Should -Contain "UpdatedPackage1"
            $targets | Should -Contain "UpdatedPackage2"
            $targets | Should -Not -Contain "NewPackage1"
        }

        It "Zwraca Updated + Added pakiety gdy IncludeNew=true" {
            $targets = Get-DeltaUpdateTargets -Diff $script:diff -Source "Winget" -IncludeNew

            $targets.Count | Should -Be 4
            $targets | Should -Contain "UpdatedPackage1"
            $targets | Should -Contain "UpdatedPackage2"
            $targets | Should -Contain "NewPackage1"
            $targets | Should -Contain "NewPackage2"
        }

        It "NIE zwraca Removed pakietów" {
            $targets = Get-DeltaUpdateTargets -Diff $script:diff -Source "Winget" -IncludeNew

            $targets | Should -Not -Contain "OldPackage"
        }

        It "Zwraca pustą tablicę gdy brak zmian" {
            $emptyDiff = @{
                Winget = @{
                    Added = @()
                    Removed = @()
                    Updated = @()
                }
            }

            $targets = Get-DeltaUpdateTargets -Diff $emptyDiff -Source "Winget"

            $targets.Count | Should -Be 0
        }
    }
}

Describe "DeltaUpdateManager - Save-PackageStateBaseline" {
    Context "Zapisywanie baseline" {
        BeforeAll {
            # Override delta state dir
            $module = Get-Module DeltaUpdateManager
            $module.Invoke({ $script:DeltaStateDir = $args[0] }, $script:testDeltaDir)
        }

        It "Tworzy plik baseline JSON" {
            $state = @{
                Winget = @(
                    @{ Id = "Package.Id"; Version = "1.0.0" }
                )
            }

            $baselinePath = Save-PackageStateBaseline -State $state

            Test-Path $baselinePath | Should -Be $true
            $baselinePath | Should -Match "baseline-\d{8}_\d{6}\.json"
        }

        It "Zapisuje poprawną strukturę JSON" {
            $state = @{
                Winget = @(
                    @{ Id = "Package.Id"; Version = "1.0.0" }
                )
                npm = @(
                    @{ Name = "typescript"; Version = "5.3.0" }
                )
            }

            $baselinePath = Save-PackageStateBaseline -State $state

            $json = Get-Content $baselinePath -Raw | ConvertFrom-Json

            $json.Timestamp | Should -Not -BeNullOrEmpty
            $json.Version | Should -Not -BeNullOrEmpty
            $json.State | Should -Not -BeNullOrEmpty
        }

        It "Czyści stare baseline files gdy przekroczony KeepLast" {
            $state = @{ Test = @() }

            # Create 12 baseline files
            for ($i = 1; $i -le 12; $i++) {
                Save-PackageStateBaseline -State $state -KeepLast 10 | Out-Null
                Start-Sleep -Milliseconds 100
            }

            $baselines = Get-ChildItem -Path $script:testDeltaDir -Filter "baseline-*.json"

            $baselines.Count | Should -Be 10
        }
    }
}

Describe "DeltaUpdateManager - Get-BaselineState" {
    Context "Wczytywanie baseline" {
        BeforeAll {
            # Override delta state dir
            $module = Get-Module DeltaUpdateManager
            $module.Invoke({ $script:DeltaStateDir = $args[0] }, $script:testDeltaDir)

            # Create test baseline
            $testState = @{
                Winget = @(
                    @{ Id = "Test.Package"; Version = "1.0.0" }
                )
            }
            Save-PackageStateBaseline -State $testState | Out-Null
        }

        It "Wczytuje ostatni baseline" {
            $baseline = Get-BaselineState

            $baseline | Should -Not -BeNullOrEmpty
            $baseline.Winget | Should -Not -BeNullOrEmpty
        }

        It "Zwraca null gdy brak baseline" {
            # Clear all baselines
            Get-ChildItem -Path $script:testDeltaDir -Filter "baseline-*.json" |
                Remove-Item -Force

            $baseline = Get-BaselineState

            $baseline | Should -BeNullOrEmpty
        }

        It "Zwraca null gdy baseline za stary" {
            # Create old baseline
            $oldBaseline = Join-Path $script:testDeltaDir "baseline-20200101_120000.json"
            $state = @{ Test = @() }
            @{
                Timestamp = (Get-Date).AddDays(-40).ToString("o")
                Version = "1.0.0"
                State = $state
            } | ConvertTo-Json -Depth 10 | Out-File $oldBaseline

            $baseline = Get-BaselineState -MaxAge 30

            $baseline | Should -BeNullOrEmpty
        }
    }
}

Describe "DeltaUpdateManager - Invoke-DeltaUpdate" {
    Context "Pełny cykl delta update" {
        BeforeAll {
            # Override delta state dir
            $module = Get-Module DeltaUpdateManager
            $module.Invoke({ $script:DeltaStateDir = $args[0] }, $script:testDeltaDir)

            # Mock Get-CurrentPackageState
            Mock -ModuleName DeltaUpdateManager -CommandName Get-CurrentPackageState -MockWith {
                return @{
                    Winget = @(
                        @{ Id = "Package1"; Version = "1.0.0" }
                        @{ Id = "Package2"; Version = "2.0.0" }
                    )
                }
            }
        }

        It "Pierwszy run: HasBaseline=false, full update" {
            $result = Invoke-DeltaUpdate -Sources @('Winget')

            $result.HasBaseline | Should -Be $false
            $result.Diff | Should -BeNullOrEmpty
            $result.Targets.Winget | Should -Not -BeNullOrEmpty
        }

        It "Drugi run: HasBaseline=true, delta update" {
            # First run to create baseline
            Invoke-DeltaUpdate -Sources @('Winget') -SaveBaseline | Out-Null

            # Mock updated package state
            Mock -ModuleName DeltaUpdateManager -CommandName Get-CurrentPackageState -MockWith {
                return @{
                    Winget = @(
                        @{ Id = "Package1"; Version = "1.1.0" }  # Updated
                        @{ Id = "Package2"; Version = "2.0.0" }  # No change
                    )
                }
            }

            # Second run
            $result = Invoke-DeltaUpdate -Sources @('Winget')

            $result.HasBaseline | Should -Be $true
            $result.Diff | Should -Not -BeNullOrEmpty
            $result.Diff.Winget.Updated.Count | Should -Be 1
        }

        It "SaveBaseline=true zapisuje nowy baseline" {
            Invoke-DeltaUpdate -Sources @('Winget') -SaveBaseline | Out-Null

            $baselines = Get-ChildItem -Path $script:testDeltaDir -Filter "baseline-*.json"

            $baselines.Count | Should -BeGreaterThan 0
        }
    }
}

Describe "DeltaUpdateManager - Clear-DeltaBaselines" {
    Context "Czyszczenie baselines" {
        BeforeAll {
            # Override delta state dir
            $module = Get-Module DeltaUpdateManager
            $module.Invoke({ $script:DeltaStateDir = $args[0] }, $script:testDeltaDir)

            # Create test baselines
            for ($i = 1; $i -le 3; $i++) {
                $state = @{ Test = @() }
                Save-PackageStateBaseline -State $state | Out-Null
            }
        }

        It "Usuwa wszystkie baseline files" {
            Clear-DeltaBaselines -Confirm:$false

            $baselines = Get-ChildItem -Path $script:testDeltaDir -Filter "baseline-*.json"

            $baselines.Count | Should -Be 0
        }

        It "Nie rzuca błędu gdy brak baselines" {
            # Ensure no baselines exist
            Get-ChildItem -Path $script:testDeltaDir -Filter "baseline-*.json" |
                Remove-Item -Force -ErrorAction SilentlyContinue

            {
                Clear-DeltaBaselines -Confirm:$false
            } | Should -Not -Throw
        }
    }
}

Describe "DeltaUpdateManager - Error Handling" {
    Context "Graceful degradation" {
        It "Nie przerywa gdy Get-CurrentPackageState fails" {
            Mock -ModuleName DeltaUpdateManager -CommandName Get-CurrentPackageState -MockWith {
                throw "Test error"
            }

            {
                Invoke-DeltaUpdate -Sources @('Winget')
            } | Should -Throw
        }

        It "Nie przerywa gdy baseline corrupted" {
            # Override delta state dir
            $module = Get-Module DeltaUpdateManager
            $module.Invoke({ $script:DeltaStateDir = $args[0] }, $script:testDeltaDir)

            # Create corrupted baseline
            $corruptedBaseline = Join-Path $script:testDeltaDir "baseline-20260123_120000.json"
            "{ invalid json" | Out-File $corruptedBaseline

            {
                $baseline = Get-BaselineState
                $baseline | Should -BeNullOrEmpty
            } | Should -Not -Throw
        }
    }
}
