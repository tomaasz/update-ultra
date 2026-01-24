# test-cache.ps1
# Unit tests dla WingetCache.psm1

<#
.SYNOPSIS
Testy jednostkowe dla modułu WingetCache

.DESCRIPTION
Weryfikuje:
- Inicjalizację cache
- Cache hit/miss
- TTL expiration
- Force refresh
- Disk cache persistence
- Cache invalidation

.NOTES
Wymaga: Pester 5.x
Uruchomienie: Invoke-Pester .\test-cache.ps1
#>

BeforeAll {
    # Import modułu WingetCache
    $modulePath = Join-Path $PSScriptRoot "..\..\src\WingetCache.psm1"
    Import-Module $modulePath -Force

    # Użyj tymczasowego katalogu dla testów
    $script:testCacheDir = Join-Path $env:TEMP "update-ultra-test-cache-$(Get-Random)"
}

AfterAll {
    # Cleanup
    if (Test-Path $script:testCacheDir) {
        Remove-Item $script:testCacheDir -Recurse -Force -ErrorAction SilentlyContinue
    }

    # Usuń moduł
    Remove-Module WingetCache -ErrorAction SilentlyContinue
}

Describe "WingetCache - Initialization" {
    Context "Basic initialization" {
        It "Inicjalizuje moduł bez błędów" {
            { Initialize-WingetCache -CacheDirectory $script:testCacheDir } | Should -Not -Throw
        }

        It "Tworzy katalog cache gdy nie istnieje" {
            $customDir = Join-Path $env:TEMP "cache-test-$(Get-Random)"

            Initialize-WingetCache -EnableDiskCache -CacheDirectory $customDir

            Test-Path $customDir | Should -Be $true

            # Cleanup
            Remove-Item $customDir -Recurse -Force -ErrorAction SilentlyContinue
        }

        It "Nie rzuca błędu przy wielokrotnej inicjalizacji" {
            { Initialize-WingetCache -CacheDirectory $script:testCacheDir } | Should -Not -Throw
            { Initialize-WingetCache -CacheDirectory $script:testCacheDir } | Should -Not -Throw
        }
    }
}

Describe "WingetCache - Basic Caching" {
    BeforeEach {
        # Wyczyść cache przed każdym testem
        Clear-WingetCache -All
    }

    Context "Cache hit/miss" {
        It "Cache miss przy pierwszym wywołaniu" {
            $callCount = 0
            $result1 = Get-CachedResult -Key "test-key-1" -ScriptBlock {
                $callCount++
                return "result-1"
            }

            $callCount | Should -Be 1
            $result1 | Should -Be "result-1"
        }

        It "Cache hit przy drugim wywołaniu" {
            $callCount = 0
            $scriptBlock = {
                $callCount++
                return "result-2"
            }

            $result1 = Get-CachedResult -Key "test-key-2" -ScriptBlock $scriptBlock
            $result2 = Get-CachedResult -Key "test-key-2" -ScriptBlock $scriptBlock

            # ScriptBlock powinien być wywołany tylko raz
            $callCount | Should -Be 1
            $result1 | Should -Be "result-2"
            $result2 | Should -Be "result-2"
        }

        It "Różne klucze dają różne wyniki" {
            $result1 = Get-CachedResult -Key "key-a" -ScriptBlock { return "value-a" }
            $result2 = Get-CachedResult -Key "key-b" -ScriptBlock { return "value-b" }

            $result1 | Should -Be "value-a"
            $result2 | Should -Be "value-b"
        }
    }

    Context "TTL Expiration" {
        It "Cache expiruje po przekroczeniu TTL" {
            $callCount = 0
            $scriptBlock = {
                $callCount++
                return Get-Date
            }

            # Pierwsze wywołanie - cache miss
            $result1 = Get-CachedResult -Key "ttl-test" -TTL 1 -ScriptBlock $scriptBlock
            Start-Sleep -Seconds 2

            # Drugie wywołanie po przekroczeniu TTL - cache miss
            $result2 = Get-CachedResult -Key "ttl-test" -TTL 1 -ScriptBlock $scriptBlock

            $callCount | Should -Be 2
            $result1 | Should -Not -Be $result2
        }

        It "Cache nie expiruje przed TTL" {
            $callCount = 0
            $scriptBlock = {
                $callCount++
                return Get-Date
            }

            # Pierwsze wywołanie
            $result1 = Get-CachedResult -Key "ttl-test-2" -TTL 10 -ScriptBlock $scriptBlock
            Start-Sleep -Milliseconds 500

            # Drugie wywołanie przed TTL - cache hit
            $result2 = Get-CachedResult -Key "ttl-test-2" -TTL 10 -ScriptBlock $scriptBlock

            $callCount | Should -Be 1
            $result1 | Should -Be $result2
        }
    }

    Context "Force Refresh" {
        It "Force odświeża cache" {
            $callCount = 0
            $scriptBlock = {
                $callCount++
                return "result-$callCount"
            }

            $result1 = Get-CachedResult -Key "force-test" -ScriptBlock $scriptBlock
            $result2 = Get-CachedResult -Key "force-test" -ScriptBlock $scriptBlock -Force

            $callCount | Should -Be 2
            $result1 | Should -Be "result-1"
            $result2 | Should -Be "result-2"
        }
    }
}

Describe "WingetCache - Disk Persistence" {
    BeforeAll {
        # Inicjalizuj z disk cache
        Initialize-WingetCache -EnableDiskCache -CacheDirectory $script:testCacheDir -TTL 300
    }

    BeforeEach {
        Clear-WingetCache -All
    }

    Context "Save to disk" {
        It "Zapisuje cache na dysku" {
            Get-CachedResult -Key "disk-test-1" -ScriptBlock { return "saved-data" }

            # Sprawdź czy plik został utworzony
            $cacheFiles = Get-ChildItem -Path $script:testCacheDir -Filter "*.cache.json"
            $cacheFiles.Count | Should -BeGreaterThan 0
        }

        It "Ładuje cache z dysku po ponownej inicjalizacji" {
            # Zapisz dane do cache
            Get-CachedResult -Key "persist-test" -ScriptBlock { return "persistent-value" }

            # Symuluj ponowną inicjalizację (reload z dysku)
            Remove-Module WingetCache -Force
            Import-Module (Join-Path $PSScriptRoot "..\..\src\WingetCache.psm1") -Force
            Initialize-WingetCache -EnableDiskCache -CacheDirectory $script:testCacheDir -TTL 300

            # Sprawdź czy dane są dostępne (nie wywołuj scriptblock)
            $callCount = 0
            $result = Get-CachedResult -Key "persist-test" -ScriptBlock {
                $callCount++
                return "should-not-execute"
            }

            $callCount | Should -Be 0
            $result | Should -Be "persistent-value"
        }
    }
}

Describe "WingetCache - Cache Management" {
    BeforeEach {
        Clear-WingetCache -All
    }

    Context "Clear cache" {
        It "Clear-WingetCache -All czyści wszystkie wpisy" {
            Get-CachedResult -Key "clear-test-1" -ScriptBlock { return "data-1" }
            Get-CachedResult -Key "clear-test-2" -ScriptBlock { return "data-2" }

            Clear-WingetCache -All

            # Po wyczyszczeniu, scriptblock powinien być wywołany ponownie
            $callCount = 0
            Get-CachedResult -Key "clear-test-1" -ScriptBlock {
                $callCount++
                return "new-data"
            }

            $callCount | Should -Be 1
        }

        It "Clear-WingetCache -Key czyści konkretny wpis" {
            Get-CachedResult -Key "specific-1" -ScriptBlock { return "data-1" }
            Get-CachedResult -Key "specific-2" -ScriptBlock { return "data-2" }

            Clear-WingetCache -Key "specific-1"

            # specific-1 powinien być wyczyszczony
            $callCount1 = 0
            Get-CachedResult -Key "specific-1" -ScriptBlock {
                $callCount1++
                return "new-data-1"
            }

            # specific-2 powinien nadal być w cache
            $callCount2 = 0
            Get-CachedResult -Key "specific-2" -ScriptBlock {
                $callCount2++
                return "new-data-2"
            }

            $callCount1 | Should -Be 1
            $callCount2 | Should -Be 0  # Cache hit
        }
    }

    Context "Cache statistics" {
        It "Get-CacheStatistics zwraca poprawne dane" {
            Get-CachedResult -Key "stat-test-1" -ScriptBlock { return "data" }
            Get-CachedResult -Key "stat-test-2" -ScriptBlock { return "data" }

            $stats = Get-CacheStatistics
            $stats.MemoryEntries | Should -BeGreaterOrEqual 2
        }
    }

    Context "Cache invalidation" {
        It "Invoke-CacheInvalidation czyści wpisy winget" {
            Get-CachedResult -Key "winget-list" -ScriptBlock { return "winget-data" }
            Get-CachedResult -Key "other-cache" -ScriptBlock { return "other-data" }

            Invoke-CacheInvalidation -Reason "Test invalidation"

            # Sprawdź czy winget-list został wyczyszczony
            $callCount1 = 0
            Get-CachedResult -Key "winget-list" -ScriptBlock {
                $callCount1++
                return "new-winget-data"
            }

            # other-cache powinien pozostać
            $callCount2 = 0
            Get-CachedResult -Key "other-cache" -ScriptBlock {
                $callCount2++
                return "new-other-data"
            }

            $callCount1 | Should -Be 1  # Cache miss (wyczyszczony)
            $callCount2 | Should -Be 0  # Cache hit (nie wyczyszczony)
        }
    }
}

Describe "WingetCache - Specialized Functions" {
    BeforeEach {
        Clear-WingetCache -All
    }

    Context "Get-CachedWingetUpgrade" {
        It "Wykonuje winget upgrade i cache'uje wynik" -Skip {
            # Ten test wymaga winget w systemie
            # Skip w środowisku testowym bez winget

            $result = Get-CachedWingetUpgrade
            $result | Should -Not -BeNullOrEmpty
            $result.Output | Should -Not -BeNullOrEmpty
            $result.ExitCode | Should -BeOfType [int]
        }

        It "Zwraca cache przy drugim wywołaniu" {
            # Mock wynik winget upgrade
            Mock -ModuleName WingetCache -CommandName winget -MockWith {
                return @("Mocked output line 1", "Mocked output line 2")
            }

            $result1 = Get-CachedWingetUpgrade
            $result2 = Get-CachedWingetUpgrade

            # Wyniki powinny być identyczne (z cache)
            $result1.Output.Count | Should -Be $result2.Output.Count
        }
    }
}

Describe "WingetCache - Error Handling" {
    Context "ScriptBlock errors" {
        It "Propaguje błędy z ScriptBlock" {
            {
                Get-CachedResult -Key "error-test" -ScriptBlock {
                    throw "Intentional error"
                }
            } | Should -Throw "Intentional error"
        }

        It "Nie cache'uje wyników po błędzie" {
            $callCount = 0

            # Pierwsze wywołanie - błąd
            try {
                Get-CachedResult -Key "error-nocache" -ScriptBlock {
                    $callCount++
                    throw "Error"
                }
            }
            catch { }

            # Drugie wywołanie - powinien ponownie wywołać scriptblock
            try {
                Get-CachedResult -Key "error-nocache" -ScriptBlock {
                    $callCount++
                    throw "Error"
                }
            }
            catch { }

            $callCount | Should -Be 2
        }
    }
}
