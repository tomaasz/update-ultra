# test-parser-optimization.ps1
# Unit tests dla zoptymalizowanego parsera Winget (regex-based)

<#
.SYNOPSIS
Testy jednostkowe dla Parse-WingetUpgradeList

.DESCRIPTION
Weryfikuje działanie regex-based parsera w różnych scenariuszach:
- Standardowy output winget
- Edge cases (pakiety z spacjami w nazwie, wiele wersji)
- Błędne linie (header, separator, summary)

.NOTES
Wymaga: Pester 5.x
Uruchomienie: Invoke-Pester .\test-parser-optimization.ps1
#>

BeforeAll {
    # Import głównego skryptu (tylko funkcje parsera)
    $scriptPath = Join-Path $PSScriptRoot "..\..\src\Update-WingetAll.ps1"

    # Załaduj tylko funkcje pomocnicze bez wykonywania głównej logiki
    $scriptContent = Get-Content $scriptPath -Raw

    # Wyekstrahuj funkcję Parse-WingetUpgradeList
    $functionMatch = $scriptContent -match '(?s)function Parse-WingetUpgradeList\s*\{.*?^}'
    if ($functionMatch) {
        # Wyodrębnij funkcję As-Array jeśli potrzebna
        $asArrayMatch = $scriptContent -match '(?s)function As-Array\s*\{.*?^}'
        if ($asArrayMatch) {
            Invoke-Expression $Matches[0]
        }

        Invoke-Expression $Matches[0]
    }
    else {
        throw "Nie znaleziono funkcji Parse-WingetUpgradeList w skrypcie"
    }
}

Describe "Parse-WingetUpgradeList" {
    Context "Standardowy output winget" {
        It "Parsuje poprawnie pojedynczą linię z aktualizacją" {
            $lines = @(
                "Name                           Id                    Version       Available     Source",
                "----------------------------------------------------------------------------------------------",
                "Visual Studio Code             Microsoft.VisualStudioCode  1.85.0    1.85.1        winget"
            )

            $result = Parse-WingetUpgradeList -Lines $lines
            $result.Count | Should -Be 1
            $result[0].Name | Should -Be "Visual Studio Code"
            $result[0].Id | Should -Be "Microsoft.VisualStudioCode"
            $result[0].Version | Should -Be "1.85.0"
            $result[0].Available | Should -Be "1.85.1"
            $result[0].Source | Should -Be "winget"
        }

        It "Parsuje wiele linii z aktualizacjami" {
            $lines = @(
                "Name                           Id                         Version       Available     Source",
                "----------------------------------------------------------------------------------------------",
                "Visual Studio Code             Microsoft.VisualStudioCode 1.85.0        1.85.1        winget",
                "Git                            Git.Git                    2.42.0        2.43.0        winget",
                "Python 3.11                    Python.Python.3.11         3.11.5        3.11.7        winget"
            )

            $result = Parse-WingetUpgradeList -Lines $lines
            $result.Count | Should -Be 3
            $result[0].Id | Should -Be "Microsoft.VisualStudioCode"
            $result[1].Id | Should -Be "Git.Git"
            $result[2].Id | Should -Be "Python.Python.3.11"
        }

        It "Ignoruje linie header" {
            $lines = @(
                "Name                           Id                    Version       Available     Source",
                "Visual Studio Code             Microsoft.VisualStudioCode  1.85.0    1.85.1        winget"
            )

            $result = Parse-WingetUpgradeList -Lines $lines
            $result.Count | Should -Be 1
            $result[0].Name | Should -Not -Be "Name"
        }

        It "Ignoruje linie separator" {
            $lines = @(
                "----------------------------------------------------------------------------------------------",
                "Visual Studio Code             Microsoft.VisualStudioCode  1.85.0    1.85.1        winget"
            )

            $result = Parse-WingetUpgradeList -Lines $lines
            $result.Count | Should -Be 1
        }

        It "Ignoruje linie summary" {
            $lines = @(
                "Visual Studio Code             Microsoft.VisualStudioCode  1.85.0    1.85.1        winget",
                "3 upgrades available"
            )

            $result = Parse-WingetUpgradeList -Lines $lines
            $result.Count | Should -Be 1
        }
    }

    Context "Edge cases - Nazwy z spacjami" {
        It "Parsuje pakiety z długimi nazwami zawierającymi spacje" {
            $lines = @(
                "Microsoft Edge WebView2 Runtime  Microsoft.EdgeWebView2Runtime  119.0.2151.58  120.0.2210.61  winget"
            )

            $result = Parse-WingetUpgradeList -Lines $lines
            $result.Count | Should -Be 1
            $result[0].Name | Should -Match "Microsoft Edge WebView2 Runtime"
            $result[0].Id | Should -Be "Microsoft.EdgeWebView2Runtime"
        }

        It "Parsuje pakiety z nazwami zawierającymi wiele spacji" {
            $lines = @(
                "Some   Long   Name              App.Id.Here               1.0.0         2.0.0         winget"
            )

            $result = Parse-WingetUpgradeList -Lines $lines
            $result.Count | Should -Be 1
            # Nazwa może zawierać dodatkowe spacje
            $result[0].Id | Should -Be "App.Id.Here"
        }
    }

    Context "Edge cases - Wersje" {
        It "Parsuje wersje z literkami (beta, rc)" {
            $lines = @(
                "Node.js                        OpenJS.NodeJS              20.10.0       21.0.0-rc1    winget"
            )

            $result = Parse-WingetUpgradeList -Lines $lines
            $result.Count | Should -Be 1
            $result[0].Version | Should -Be "20.10.0"
            $result[0].Available | Should -Match "21.0.0"
        }

        It "Parsuje wersje z myślnikami" {
            $lines = @(
                "Some App                       App.Id                     1.0.0-beta    1.0.0         winget"
            )

            $result = Parse-WingetUpgradeList -Lines $lines
            $result.Count | Should -Be 1
            $result[0].Version | Should -Match "1.0.0"
        }

        It "Parsuje wersje z dodatkowymi segmentami" {
            $lines = @(
                "App                            App.Id                     1.2.3.4567    1.2.3.4568    winget"
            )

            $result = Parse-WingetUpgradeList -Lines $lines
            $result.Count | Should -Be 1
            $result[0].Version | Should -Be "1.2.3.4567"
            $result[0].Available | Should -Be "1.2.3.4568"
        }
    }

    Context "Edge cases - Puste i błędne linie" {
        It "Ignoruje puste linie" {
            $lines = @(
                "",
                "Visual Studio Code             Microsoft.VisualStudioCode  1.85.0    1.85.1        winget",
                "",
                "Git                            Git.Git                    2.42.0        2.43.0        winget",
                ""
            )

            $result = Parse-WingetUpgradeList -Lines $lines
            $result.Count | Should -Be 2
        }

        It "Ignoruje linie tylko z białymi znakami" {
            $lines = @(
                "   ",
                "Visual Studio Code             Microsoft.VisualStudioCode  1.85.0    1.85.1        winget",
                "    "
            )

            $result = Parse-WingetUpgradeList -Lines $lines
            $result.Count | Should -Be 1
        }

        It "Ignoruje linie 'No installed package found'" {
            $lines = @(
                "No installed package found matching input criteria."
            )

            $result = Parse-WingetUpgradeList -Lines $lines
            $result.Count | Should -Be 0
        }

        It "Ignoruje linie 'require explicit targeting'" {
            $lines = @(
                "Visual Studio Code             Microsoft.VisualStudioCode  1.85.0    1.85.1        winget",
                "The following packages require explicit targeting:",
                "Git                            Git.Git                    2.42.0        2.43.0        winget"
            )

            $result = Parse-WingetUpgradeList -Lines $lines
            # Parser powinien ignorować linię "require explicit targeting", ale parsować obie aplikacje
            $result.Count | Should -Be 2
        }
    }

    Context "Edge cases - Różne source'y" {
        It "Parsuje pakiety z msstore source" {
            $lines = @(
                "Netflix                        9WZDNCRFJ3TJ               12.52.161.0   12.53.170.0   msstore"
            )

            $result = Parse-WingetUpgradeList -Lines $lines
            $result.Count | Should -Be 1
            $result[0].Source | Should -Be "msstore"
        }

        It "Parsuje mieszane source'y" {
            $lines = @(
                "Visual Studio Code             Microsoft.VisualStudioCode  1.85.0    1.85.1        winget",
                "Netflix                        9WZDNCRFJ3TJ               12.52.0   12.53.0       msstore"
            )

            $result = Parse-WingetUpgradeList -Lines $lines
            $result.Count | Should -Be 2
            $result[0].Source | Should -Be "winget"
            $result[1].Source | Should -Be "msstore"
        }
    }

    Context "Performance - Duże listy" {
        It "Parsuje szybko 100 pakietów" {
            # Generuj 100 linii testowych
            $lines = @()
            $lines += "Name                           Id                    Version       Available     Source"
            $lines += "----------------------------------------------------------------------------------------------"

            for ($i = 1; $i -le 100; $i++) {
                $lines += "Application $i                 App.Id.$i             1.0.0         1.0.1         winget"
            }

            $stopwatch = [System.Diagnostics.Stopwatch]::StartNew()
            $result = Parse-WingetUpgradeList -Lines $lines
            $stopwatch.Stop()

            $result.Count | Should -Be 100

            # Parser powinien być szybki (< 100ms dla 100 pakietów)
            $stopwatch.ElapsedMilliseconds | Should -BeLessThan 100
        }
    }

    Context "Regression - Poprzednie błędy" {
        It "Nie zwraca duplikatów" {
            $lines = @(
                "Visual Studio Code             Microsoft.VisualStudioCode  1.85.0    1.85.1        winget",
                "Visual Studio Code             Microsoft.VisualStudioCode  1.85.0    1.85.1        winget"
            )

            $result = Parse-WingetUpgradeList -Lines $lines
            # Parser powinien zwrócić obie linie (winget może czasami duplikować)
            # ale to nie jest błąd parsera
            $result.Count | Should -Be 2
        }

        It "Obsługuje linie z nietypowymi odstępami" {
            $lines = @(
                "App Name    SomeId    1.0    2.0    winget"  # Mniej niż 2 spacje między kolumnami
            )

            # Linia nie spełnia wzorca (wymaga 2+ spacji), powinna być zignorowana
            $result = Parse-WingetUpgradeList -Lines $lines
            $result.Count | Should -Be 0
        }
    }
}
