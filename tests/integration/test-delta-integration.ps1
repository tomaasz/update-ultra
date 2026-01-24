# test-delta-integration.ps1
# Integration tests dla DeltaUpdateManager.psm1

<#
.SYNOPSIS
Testy integracyjne dla modułu DeltaUpdateManager

.DESCRIPTION
Weryfikuje:
- Pełny cykl delta update (Initialize → Get → Compare → Update → Save)
- Rzeczywiste operacje na plikach baseline
- Porównanie wydajności delta vs full update
- Różne scenariusze baseline (brak, stary, uszkodzony)
- Cleanup i zarządzanie baseline history

.NOTES
Wymaga: Pester 5.x
Uruchomienie: Invoke-Pester .\test-delta-integration.ps1
#>

BeforeAll {
    # Import modułu DeltaUpdateManager
    $modulePath = Join-Path $PSScriptRoot "..\..\src\DeltaUpdateManager.psm1"
    Import-Module $modulePath -Force

    # Tymczasowy katalog dla testów (nie używamy rzeczywistego %APPDATA%)
    $script:TestDeltaStateDir = Join-Path $env:TEMP "update-ultra-test-delta-$(Get-Random)"

    # Override domyślnej ścieżki delta state (używając InModuleScope)
    InModuleScope DeltaUpdateManager {
        $script:DeltaStateDir = $args[0]
    } -ArgumentList $script:TestDeltaStateDir
}

AfterAll {
    # Cleanup: usuń test directory
    if (Test-Path $script:TestDeltaStateDir) {
        Remove-Item $script:TestDeltaStateDir -Recurse -Force -ErrorAction SilentlyContinue
    }

    Remove-Module DeltaUpdateManager -ErrorAction SilentlyContinue
}

Describe "DeltaUpdateManager Integration Tests" {
    Context "Full delta update cycle - First run (no baseline)" {
        BeforeAll {
            # Czyste środowisko
            if (Test-Path $script:TestDeltaStateDir) {
                Remove-Item $script:TestDeltaStateDir -Recurse -Force
            }

            Initialize-DeltaUpdateManager
        }

        It "Initialize-DeltaUpdateManager tworzy katalog delta state" {
            Test-Path $script:TestDeltaStateDir | Should -Be $true
        }

        It "Get-BaselineState zwraca null gdy brak baseline" {
            $baseline = Get-BaselineState
            $baseline | Should -BeNullOrEmpty
        }

        It "Invoke-DeltaUpdate zwraca HasBaseline=$false przy pierwszym uruchomieniu" {
            # Mock Get-CurrentPackageState (żeby nie wywoływać rzeczywistego winget/npm/pip)
            Mock -ModuleName DeltaUpdateManager -CommandName Get-CurrentPackageState -MockWith {
                return @{
                    Winget = @(
                        @{ Id = "Microsoft.VisualStudioCode"; Version = "1.85.0" }
                        @{ Id = "Git.Git"; Version = "2.43.0" }
                    )
                    npm = @(
                        @{ Name = "typescript"; Version = "5.3.0" }
                    )
                    pip = @(
                        @{ Name = "requests"; Version = "2.31.0" }
                    )
                }
            }

            $result = Invoke-DeltaUpdate -Sources @('Winget', 'npm', 'pip')

            $result.HasBaseline | Should -Be $false
            $result.Message | Should -Match "No baseline|first run"
        }

        It "Save-PackageStateBaseline tworzy pierwszy baseline" {
            $state = @{
                Winget = @(
                    @{ Id = "Microsoft.VisualStudioCode"; Version = "1.85.0" }
                    @{ Id = "Git.Git"; Version = "2.43.0" }
                )
                npm = @(
                    @{ Name = "typescript"; Version = "5.3.0" }
                )
            }

            $baselinePath = Save-PackageStateBaseline -State $state

            Test-Path $baselinePath | Should -Be $true
            $baselinePath | Should -Match "baseline-\d{8}-\d{6}\.json"
        }

        It "Baseline zawiera poprawną strukturę JSON" {
            # Odczytaj zapisany baseline
            $baselines = Get-ChildItem $script:TestDeltaStateDir -Filter "baseline-*.json"
            $baselines.Count | Should -BeGreaterThan 0

            $baseline = Get-Content $baselines[0].FullName -Raw | ConvertFrom-Json

            $baseline.Timestamp | Should -Not -BeNullOrEmpty
            $baseline.Version | Should -Be "1.0"
            $baseline.State | Should -Not -BeNullOrEmpty
            $baseline.State.Winget | Should -Not -BeNullOrEmpty
            $baseline.State.npm | Should -Not -BeNullOrEmpty
        }
    }

    Context "Full delta update cycle - Second run (with baseline)" {
        BeforeAll {
            # Cleanup poprzednich baseline
            if (Test-Path $script:TestDeltaStateDir) {
                Remove-Item $script:TestDeltaStateDir -Recurse -Force
            }
            Initialize-DeltaUpdateManager

            # Utwórz baseline
            $initialState = @{
                Winget = @(
                    @{ Id = "Microsoft.VisualStudioCode"; Version = "1.85.0" }
                    @{ Id = "Git.Git"; Version = "2.43.0" }
                )
                npm = @(
                    @{ Name = "typescript"; Version = "5.3.0" }
                    @{ Name = "eslint"; Version = "8.50.0" }
                )
                pip = @(
                    @{ Name = "requests"; Version = "2.31.0" }
                )
            }

            Save-PackageStateBaseline -State $initialState | Out-Null
        }

        It "Get-BaselineState zwraca zapisany baseline" {
            $baseline = Get-BaselineState

            $baseline | Should -Not -BeNullOrEmpty
            $baseline.State.Winget.Count | Should -Be 2
            $baseline.State.npm.Count | Should -Be 2
            $baseline.State.pip.Count | Should -Be 1
        }

        It "Invoke-DeltaUpdate wykrywa zmiany w pakietach" {
            # Mock Get-CurrentPackageState z nowymi wersjami
            Mock -ModuleName DeltaUpdateManager -CommandName Get-CurrentPackageState -MockWith {
                return @{
                    Winget = @(
                        @{ Id = "Microsoft.VisualStudioCode"; Version = "1.86.0" }  # Updated
                        @{ Id = "Git.Git"; Version = "2.43.0" }  # No change
                        @{ Id = "NewPackage.Id"; Version = "1.0.0" }  # Added
                    )
                    npm = @(
                        @{ Name = "typescript"; Version = "5.3.3" }  # Updated
                        # eslint removed
                    )
                    pip = @(
                        @{ Name = "requests"; Version = "2.31.0" }  # No change
                        @{ Name = "django"; Version = "5.0.0" }  # Added
                    )
                }
            }

            $result = Invoke-DeltaUpdate -Sources @('Winget', 'npm', 'pip')

            $result.HasBaseline | Should -Be $true
            $result.Diff | Should -Not -BeNullOrEmpty
        }

        It "Delta diff wykrywa Added packages" {
            Mock -ModuleName DeltaUpdateManager -CommandName Get-CurrentPackageState -MockWith {
                return @{
                    Winget = @(
                        @{ Id = "Microsoft.VisualStudioCode"; Version = "1.85.0" }
                        @{ Id = "Git.Git"; Version = "2.43.0" }
                        @{ Id = "NewPackage.Id"; Version = "1.0.0" }  # Added
                    )
                    npm = @(
                        @{ Name = "typescript"; Version = "5.3.0" }
                        @{ Name = "eslint"; Version = "8.50.0" }
                        @{ Name = "prettier"; Version = "3.0.0" }  # Added
                    )
                }
            }

            $result = Invoke-DeltaUpdate -Sources @('Winget', 'npm')

            $result.Diff.Winget.Added | Should -Contain "NewPackage.Id"
            $result.Diff.npm.Added | Should -Contain "prettier"
        }

        It "Delta diff wykrywa Removed packages" {
            Mock -ModuleName DeltaUpdateManager -CommandName Get-CurrentPackageState -MockWith {
                return @{
                    Winget = @(
                        @{ Id = "Microsoft.VisualStudioCode"; Version = "1.85.0" }
                        # Git.Git removed
                    )
                    npm = @(
                        @{ Name = "typescript"; Version = "5.3.0" }
                        # eslint removed
                    )
                }
            }

            $result = Invoke-DeltaUpdate -Sources @('Winget', 'npm')

            $result.Diff.Winget.Removed | Should -Contain "Git.Git"
            $result.Diff.npm.Removed | Should -Contain "eslint"
        }

        It "Delta diff wykrywa Updated packages" {
            Mock -ModuleName DeltaUpdateManager -CommandName Get-CurrentPackageState -MockWith {
                return @{
                    Winget = @(
                        @{ Id = "Microsoft.VisualStudioCode"; Version = "1.86.0" }  # Updated
                        @{ Id = "Git.Git"; Version = "2.44.0" }  # Updated
                    )
                    npm = @(
                        @{ Name = "typescript"; Version = "5.4.0" }  # Updated
                        @{ Name = "eslint"; Version = "8.50.0" }  # No change
                    )
                }
            }

            $result = Invoke-DeltaUpdate -Sources @('Winget', 'npm')

            # Updated zawiera obiekty z OldVersion i NewVersion
            $result.Diff.Winget.Updated.Count | Should -Be 2
            $result.Diff.npm.Updated.Count | Should -Be 1

            # Sprawdź strukturę Updated
            $vscodeUpdate = $result.Diff.Winget.Updated | Where-Object { $_.Id -eq "Microsoft.VisualStudioCode" }
            $vscodeUpdate.OldVersion | Should -Be "1.85.0"
            $vscodeUpdate.NewVersion | Should -Be "1.86.0"
        }

        It "Get-DeltaUpdateTargets zwraca tylko Updated packages (IncludeNew=false)" {
            Mock -ModuleName DeltaUpdateManager -CommandName Get-CurrentPackageState -MockWith {
                return @{
                    Winget = @(
                        @{ Id = "Microsoft.VisualStudioCode"; Version = "1.86.0" }  # Updated
                        @{ Id = "Git.Git"; Version = "2.43.0" }  # No change
                        @{ Id = "NewPackage.Id"; Version = "1.0.0" }  # Added
                    )
                }
            }

            $result = Invoke-DeltaUpdate -Sources @('Winget')
            $targets = $result.Targets.Winget

            # Tylko Updated, bez Added
            $targets.Count | Should -Be 1
            $targets | Should -Contain "Microsoft.VisualStudioCode"
            $targets | Should -Not -Contain "NewPackage.Id"
        }

        It "Get-DeltaUpdateTargets zwraca Updated + Added packages (IncludeNew=true)" {
            Mock -ModuleName DeltaUpdateManager -CommandName Get-CurrentPackageState -MockWith {
                return @{
                    Winget = @(
                        @{ Id = "Microsoft.VisualStudioCode"; Version = "1.86.0" }  # Updated
                        @{ Id = "Git.Git"; Version = "2.43.0" }  # No change
                        @{ Id = "NewPackage.Id"; Version = "1.0.0" }  # Added
                    )
                }
            }

            # Użyj InModuleScope żeby wywołać z parametrem IncludeNew
            $targets = InModuleScope DeltaUpdateManager {
                $result = Invoke-DeltaUpdate -Sources @('Winget')
                $diff = $result.Diff
                Get-DeltaUpdateTargets -Diff $diff -Source "Winget" -IncludeNew
            }

            # Updated + Added
            $targets.Count | Should -Be 2
            $targets | Should -Contain "Microsoft.VisualStudioCode"
            $targets | Should -Contain "NewPackage.Id"
        }
    }

    Context "Baseline history management" {
        BeforeAll {
            # Cleanup
            if (Test-Path $script:TestDeltaStateDir) {
                Remove-Item $script:TestDeltaStateDir -Recurse -Force
            }
            Initialize-DeltaUpdateManager
        }

        It "Save-PackageStateBaseline ogranicza liczbę baseline do KeepLast" {
            # Utwórz 15 baseline
            for ($i = 1; $i -le 15; $i++) {
                $state = @{
                    Winget = @(
                        @{ Id = "Test.Package$i"; Version = "1.$i.0" }
                    )
                }

                Save-PackageStateBaseline -State $state -KeepLast 10 | Out-Null
                Start-Sleep -Milliseconds 100  # Zapewnij różne timestampy
            }

            # Powinno być max 10 baseline
            $baselines = Get-ChildItem $script:TestDeltaStateDir -Filter "baseline-*.json"
            $baselines.Count | Should -BeLessOrEqual 10
        }

        It "Clear-DeltaBaselines usuwa wszystkie baseline" {
            # Najpierw utwórz kilka baseline
            for ($i = 1; $i -le 5; $i++) {
                $state = @{ Winget = @(@{ Id = "Test$i"; Version = "1.0" }) }
                Save-PackageStateBaseline -State $state | Out-Null
            }

            # Sprawdź że istnieją
            $beforeCount = (Get-ChildItem $script:TestDeltaStateDir -Filter "baseline-*.json").Count
            $beforeCount | Should -BeGreaterThan 0

            # Wyczyść
            Clear-DeltaBaselines

            # Sprawdź że nie ma baseline
            $afterBaselines = Get-ChildItem $script:TestDeltaStateDir -Filter "baseline-*.json" -ErrorAction SilentlyContinue
            $afterBaselines | Should -BeNullOrEmpty
        }
    }

    Context "Baseline age validation" {
        BeforeAll {
            # Cleanup
            if (Test-Path $script:TestDeltaStateDir) {
                Remove-Item $script:TestDeltaStateDir -Recurse -Force
            }
            Initialize-DeltaUpdateManager

            # Utwórz stary baseline (modyfikując timestamp w JSON)
            $state = @{
                Winget = @(
                    @{ Id = "Test.Package"; Version = "1.0.0" }
                )
            }

            $baselinePath = Save-PackageStateBaseline -State $state

            # Odczytaj i zmień timestamp na 60 dni temu
            $baselineJson = Get-Content $baselinePath -Raw | ConvertFrom-Json
            $baselineJson.Timestamp = (Get-Date).AddDays(-60).ToString("o")
            $baselineJson | ConvertTo-Json -Depth 10 | Out-File $baselinePath -Encoding UTF8
        }

        It "Get-BaselineState zwraca ostrzeżenie dla starego baseline" {
            $baseline = Get-BaselineState -MaxAgeDays 30 -WarningAction SilentlyContinue

            # Baseline jest zwracany mimo że stary
            $baseline | Should -Not -BeNullOrEmpty

            # Ale powinno być warning (możemy sprawdzić przez WarningVariable)
            $warnings = @()
            Get-BaselineState -MaxAgeDays 30 -WarningVariable warnings -WarningAction SilentlyContinue

            $warnings.Count | Should -BeGreaterThan 0
            $warnings[0] | Should -Match "stary|old|age"
        }
    }

    Context "Corrupted baseline handling" {
        BeforeAll {
            # Cleanup
            if (Test-Path $script:TestDeltaStateDir) {
                Remove-Item $script:TestDeltaStateDir -Recurse -Force
            }
            Initialize-DeltaUpdateManager

            # Utwórz uszkodzony baseline (niepoprawny JSON)
            $corruptedPath = Join-Path $script:TestDeltaStateDir "baseline-20250123-120000.json"
            "{ invalid json content }" | Out-File $corruptedPath -Encoding UTF8
        }

        It "Get-BaselineState zwraca null dla uszkodzonego baseline" {
            $baseline = Get-BaselineState -ErrorAction SilentlyContinue

            $baseline | Should -BeNullOrEmpty
        }

        It "Invoke-DeltaUpdate gracefully degrades przy uszkodzonym baseline" {
            Mock -ModuleName DeltaUpdateManager -CommandName Get-CurrentPackageState -MockWith {
                return @{
                    Winget = @(
                        @{ Id = "Test.Package"; Version = "1.0.0" }
                    )
                }
            }

            {
                Invoke-DeltaUpdate -Sources @('Winget')
            } | Should -Not -Throw

            $result = Invoke-DeltaUpdate -Sources @('Winget') -ErrorAction SilentlyContinue

            # Powinno zachować się jak first run
            $result.HasBaseline | Should -Be $false
        }
    }

    Context "Performance comparison - Delta vs Full" -Skip {
        # UWAGA: Test oznaczony jako -Skip ponieważ wymaga rzeczywistego winget/npm/pip
        # i długiego czekania. Można odblokować dla manual testing.

        It "Delta mode jest szybszy niż full update dla małych zmian" {
            # Ten test wymaga rzeczywistego środowiska z zainstalowanymi pakietami

            # Pomiar full update
            $fullUpdateTime = Measure-Command {
                # Symulacja full update (wszystkie pakiety)
                # winget upgrade, npm outdated, pip list --outdated
            }

            # Pomiar delta update (tylko 2-3 pakiety)
            $deltaUpdateTime = Measure-Command {
                # Invoke-DeltaUpdate → tylko zmienione pakiety
            }

            $deltaUpdateTime.TotalSeconds | Should -BeLessThan ($fullUpdateTime.TotalSeconds * 0.7)
        }
    }

    Context "Real-world scenario simulation" {
        BeforeAll {
            # Cleanup
            if (Test-Path $script:TestDeltaStateDir) {
                Remove-Item $script:TestDeltaStateDir -Recurse -Force
            }
            Initialize-DeltaUpdateManager
        }

        It "Scenariusz 1: First run → Save baseline → Second run with 2 updates" {
            # First run
            Mock -ModuleName DeltaUpdateManager -CommandName Get-CurrentPackageState -MockWith {
                return @{
                    Winget = @(
                        @{ Id = "Microsoft.VisualStudioCode"; Version = "1.85.0" }
                        @{ Id = "Git.Git"; Version = "2.43.0" }
                        @{ Id = "Python.Python.3.12"; Version = "3.12.0" }
                    )
                }
            }

            $result1 = Invoke-DeltaUpdate -Sources @('Winget')
            $result1.HasBaseline | Should -Be $false

            # Save baseline
            Save-PackageStateBaseline -State $result1.CurrentState | Out-Null

            # Second run (2 updates)
            Mock -ModuleName DeltaUpdateManager -CommandName Get-CurrentPackageState -MockWith {
                return @{
                    Winget = @(
                        @{ Id = "Microsoft.VisualStudioCode"; Version = "1.86.0" }  # Updated
                        @{ Id = "Git.Git"; Version = "2.44.0" }  # Updated
                        @{ Id = "Python.Python.3.12"; Version = "3.12.0" }  # No change
                    )
                }
            }

            $result2 = Invoke-DeltaUpdate -Sources @('Winget')

            $result2.HasBaseline | Should -Be $true
            $result2.Diff.Winget.Updated.Count | Should -Be 2
            $result2.Targets.Winget.Count | Should -Be 2
            $result2.Targets.Winget | Should -Contain "Microsoft.VisualStudioCode"
            $result2.Targets.Winget | Should -Contain "Git.Git"
        }

        It "Scenariusz 2: No changes → Delta targets empty" {
            # Save baseline
            Mock -ModuleName DeltaUpdateManager -CommandName Get-CurrentPackageState -MockWith {
                return @{
                    Winget = @(
                        @{ Id = "Microsoft.VisualStudioCode"; Version = "1.85.0" }
                    )
                }
            }

            $result1 = Invoke-DeltaUpdate -Sources @('Winget')
            Save-PackageStateBaseline -State $result1.CurrentState | Out-Null

            # Second run (no changes)
            Mock -ModuleName DeltaUpdateManager -CommandName Get-CurrentPackageState -MockWith {
                return @{
                    Winget = @(
                        @{ Id = "Microsoft.VisualStudioCode"; Version = "1.85.0" }  # Same
                    )
                }
            }

            $result2 = Invoke-DeltaUpdate -Sources @('Winget')

            $result2.Diff.Winget.Updated.Count | Should -Be 0
            $result2.Diff.Winget.Added.Count | Should -Be 0
            $result2.Diff.Winget.Removed.Count | Should -Be 0
            $result2.Targets.Winget.Count | Should -Be 0
        }
    }
}
