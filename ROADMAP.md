# Update-Ultra: Roadmap Rozwoju v5.0

## Przegląd

Ten dokument opisuje plan rozwoju projektu update-ultra od wersji 4.2 do 5.0+.
Wszystkie 30 planowanych ulepszeń zostało podzielonych na 6 milestone'ów (kamieni milowych).

## Status Ogólny

- ✅ **v4.2**: Baza stabilna, 19 środowisk, podstawowe logowanie
- 🔄 **v5.0**: Równoległe wykonanie, cache, optymalizacje parsera
- 📋 **v5.1**: Nowe funkcje (rollback, scheduling, hooks)
- 📋 **v5.2**: Raportowanie HTML, porównania, eksport metryk
- 📋 **v5.3**: Bezpieczeństwo, testy, CI/CD
- 📋 **v6.0**: Dystrybucja, UI/UX, konfiguracja, lokalizacja

---

## Milestone 1: Optymalizacje Wydajności (v5.0)

**Cel**: Przyspieszyć wykonanie o 40-60% poprzez równoległe wykonanie i optymalizacje

### ✅ 1.1 Równoległa aktualizacja środowisk
**Status**: Ukończone
**Plik**: `src/ParallelExecution.psm1`
**Opis**: Moduł umożliwiający równoległe uruchamianie niezależnych sekcji aktualizacji

**Użycie**:
```powershell
.\Update-WingetAll.ps1 -Parallel -MaxParallelJobs 4
.\Update-WingetAll.ps1 -Sequential  # Wyłącz równoległość
```

**Grupy wykonania**:
- Grupa 1: Package Managers (Winget, Chocolatey, Scoop, MS Store)
- Grupa 2: Language Tools (Python/Pip, npm, Cargo, Ruby, etc.)
- Grupa 3: Dev Tools (VS Code, PowerShell Modules)
- Grupa 4: System Services (Docker, WSL) - sekwencyjnie
- Grupa 5: Git Repos - sekwencyjnie

### 🔄 1.2 Cache'owanie wyników winget list
**Status**: W trakcie
**Plik**: `src/WingetCache.psm1` (do stworzenia)
**Opis**: Cache'owanie wyników `winget list` i `winget upgrade` dla przyspieszenia

**Implementacja**:
- Cache w pamięci dla pojedynczego uruchomienia
- Opcjonalny cache na dysku z TTL (Time To Live)
- Automatyczne unieważnianie po `winget source update`

**Użycie**:
```powershell
.\Update-WingetAll.ps1 -EnableDiskCache -CacheTTL 300  # 5 min cache
```

### 📋 1.3 Przyspieszenie parsera Winget
**Status**: Zaplanowane
**Plik**: `src/Update-WingetAll.ps1` (linie 390-461)
**Opis**: Optymalizacja funkcji parsowania używając regex zamiast split

**Zmiany**:
```powershell
# Przed: split i iteracja po tablicach
$parts = @($l -split '\s{2,}' | Where-Object { $_ -ne "" })

# Po: bezpośredni regex match
if ($l -match '^(\S+)\s{2,}(\S+)\s{2,}([\d\.]+)\s{2,}([\d\.]+)\s{2,}(\S+)') {
    [pscustomobject]@{
        Name = $Matches[1]; Id = $Matches[2]
        Version = $Matches[3]; Available = $Matches[4]; Source = $Matches[5]
    }
}
```

**Spodziewany zysk**: 30-50% szybsze parsowanie dużych list (100+ pakietów)

---

## Milestone 2: Nowe Funkcje Core (v5.1)

**Cel**: Dodać kluczowe funkcje dla production use

### 📋 2.1 Mechanizm Rollback ze snapshotami
**Plik**: `src/SnapshotManager.psm1`
**Opis**: Zapisuj snapshot wszystkich wersji pakietów przed aktualizacją, umożliw rollback

**Funkcje**:
- `New-PackageSnapshot`: Tworzy snapshot przed aktualizacją
- `Compare-PackageSnapshot`: Porównuje dwa snapshoty
- `Restore-PackageSnapshot`: Przywraca pakiety do poprzednich wersji
- `Get-SnapshotHistory`: Lista dostępnych snapshotów

**Użycie**:
```powershell
.\Update-WingetAll.ps1 -CreateSnapshot  # Automatyczny snapshot
.\Update-WingetAll.ps1 -Rollback -SnapshotDate "20260123_140530"
```

**Format snapshota** (JSON):
```json
{
  "timestamp": "2026-01-23T14:05:30",
  "environment": "Windows 11 Pro",
  "packages": {
    "winget": [
      {"id": "Microsoft.VisualStudioCode", "version": "1.85.0"},
      ...
    ],
    "pip": [
      {"name": "requests", "version": "2.31.0"},
      ...
    ]
  }
}
```

### 📋 2.2 Scheduling i Auto-Update
**Plik**: `src/TaskScheduler.psm1`
**Opis**: Integracja z Windows Task Scheduler dla automatycznych aktualizacji

**Funkcje**:
- `Install-UpdateSchedule`: Tworzy scheduled task
- `Remove-UpdateSchedule`: Usuwa scheduled task
- `Get-UpdateSchedule`: Wyświetla aktualny harmonogram
- `Test-UpdateSchedule`: Testuje konfigurację

**Użycie**:
```powershell
.\Update-WingetAll.ps1 -InstallSchedule -RunAt "03:00" -Frequency Daily
.\Update-WingetAll.ps1 -InstallSchedule -RunAt "03:00" -Frequency Weekly -DayOfWeek Sunday
.\Update-WingetAll.ps1 -RemoveSchedule
```

**Opcje**:
- Trigger: Time-based, On boot, On network connect
- Conditions: AC power, Idle, Network available
- Actions: Send email report, create toast notification

### 📋 2.3 Pre/Post-Update Hooks
**Plik**: `src/Update-WingetAll.ps1` (rozszerzenie)
**Opis**: Możliwość definiowania własnych akcji przed/po aktualizacji

**Implementacja**:
```powershell
# W pliku konfiguracyjnym lub parametrach
[CmdletBinding()]
param(
    [scriptblock]$PreUpdateHook,
    [scriptblock]$PostUpdateHook,
    [hashtable]$SectionHooks  # Per-section hooks
)

# Przykład użycia
.\Update-WingetAll.ps1 -PreUpdateHook {
    Write-Host "Zatrzymywanie usług..."
    Stop-Service "MojaAplikacja"
} -PostUpdateHook {
    Write-Host "Uruchamianie usług..."
    Start-Service "MojaAplikacja"
}

# Section-specific hooks
.\Update-WingetAll.ps1 -SectionHooks @{
    "Docker Images" = @{
        Pre = { docker stop $(docker ps -q) }
        Post = { docker start $(docker ps -aq) }
    }
}
```

### 📋 2.4 Powiadomienia Desktop/Email
**Plik**: `src/NotificationManager.psm1`
**Opis**: Wysyłaj powiadomienia po zakończeniu aktualizacji

**Kanały**:
1. **Windows Toast Notifications** (BurntToast module)
2. **Email** (SMTP)
3. **Webhook** (Slack, Discord, Teams)
4. **Log File** (zawsze aktywny)

**Użycie**:
```powershell
.\Update-WingetAll.ps1 -NotifyToast
.\Update-WingetAll.ps1 -NotifyEmail -SmtpServer "smtp.gmail.com" -To "admin@example.com"
.\Update-WingetAll.ps1 -NotifyWebhook -WebhookUrl "https://hooks.slack.com/..."
```

**Treść powiadomienia**:
- Czas wykonania
- Liczba zaktualizowanych pakietów
- Błędy (jeśli występują)
- Link do pełnego raportu

### 📋 2.5 Delta Updates
**Plik**: `src/DeltaUpdateManager.psm1`
**Opis**: Aktualizuj tylko pakiety, które rzeczywiście się zmieniły

**Mechanizm**:
- Porównaj aktualne wersje z repozytorium/cache
- Pomiń pakiety, które już są aktualne
- Szczególnie ważne dla VS Code extensions, PowerShell Modules

**Użycie**:
```powershell
.\Update-WingetAll.ps1 -DeltaMode  # Domyślnie włączone w v5.1+
.\Update-WingetAll.ps1 -ForceAll   # Wymuś aktualizację wszystkich
```

---

## Milestone 3: Raportowanie i Monitoring (v5.2)

### 📋 3.1 Graficzny Report HTML
**Plik**: `src/HtmlReporter.psm1`
**Opis**: Generuj interaktywne raporty HTML z wykresami

**Elementy raportu**:
- Executive summary (metryki główne)
- Tabele pakietów z sortowaniem i filtrowaniem
- Wykresy kołowe (sukces/błędy)
- Wykresy słupkowe (czas wykonania per sekcja)
- Timeline aktualizacji
- Porównanie z poprzednimi uruchomieniami

**Użycie**:
```powershell
.\Update-WingetAll.ps1 -GenerateHtmlReport
```

**Technologie**:
- HTML5 + CSS3
- Chart.js dla wykresów
- DataTables dla interaktywnych tabel
- Responsive design

### 📋 3.2 Eksport do InfluxDB/Prometheus
**Plik**: `src/MetricsExporter.psm1`
**Opis**: Wysyłaj metryki do systemów monitoringu

**Metryki**:
- `update_duration_seconds{section="Winget"}`: Czas wykonania
- `packages_updated_total{section="Winget"}`: Liczba pakietów
- `update_errors_total{section="Winget"}`: Liczba błędów
- `update_success{section="Winget"}`: Status sukcesu (0/1)

**Użycie**:
```powershell
# InfluxDB
.\Update-WingetAll.ps1 -InfluxDBUrl "http://localhost:8086" -InfluxDBToken "..."

# Prometheus Pushgateway
.\Update-WingetAll.ps1 -PrometheusUrl "http://localhost:9091"
```

### 📋 3.3 Porównanie z Poprzednią Aktualizacją
**Plik**: `src/ComparisonEngine.psm1`
**Opis**: Wyświetl różnice między uruchomieniami

**Porównania**:
- Które pakiety zostały zaktualizowane
- Zmiany w czasie wykonania
- Nowe błędy vs. naprawione błędy
- Trend wydajności

**Użycie**:
```powershell
.\Update-WingetAll.ps1 -CompareWithPrevious
```

**Output**:
```
=== PORÓWNANIE Z POPRZEDNIM URUCHOMIENIEM ===
Poprzednia aktualizacja: 2026-01-22 15:30:00

Zmiany:
  ✅ Winget: 15 → 12 pakietów zaktualizowanych (-3)
  ⚠️  Python/Pip: 8 → 10 pakietów zaktualizowanych (+2)
  ✅ Czas wykonania: 180s → 120s (-60s, -33%)

Nowe aktualizacje:
  + Microsoft.VisualStudioCode 1.85.0 → 1.86.0
  + Git.Git 2.42.0 → 2.43.0
```

---

## Milestone 4: Bezpieczeństwo i Testy (v5.3)

### 📋 4.1 Weryfikacja Podpisów Pakietów
**Plik**: `src/SignatureValidator.psm1`
**Opis**: Weryfikuj podpisy cyfrowe/checksumy przed instalacją

**Mechanizmy**:
- Winget: Użyj wbudowanej weryfikacji
- Chocolatey: Sprawdź `checksumType` i `checksum`
- Manual: Pobierz SHA256/GPG z oficjalnych źródeł

**Użycie**:
```powershell
.\Update-WingetAll.ps1 -VerifySignatures -VerifyLevel Strict
```

### 📋 4.2 Rozszerzony Dry-Run
**Plik**: `src/Update-WingetAll.ps1` (rozszerzenie)
**Opis**: Szczegółowa analiza co zostanie zmienione

**Output**:
```powershell
.\Update-WingetAll.ps1 -WhatIf -Detailed

=== DRY RUN: SZCZEGÓŁOWA ANALIZA ===

[Winget]
  Microsoft.VisualStudioCode
    Obecna:    1.85.0
    Dostępna:  1.86.0
    Rozmiar:   ~120 MB
    Akcja:     winget upgrade --id Microsoft.VisualStudioCode -e
    Ryzyko:    🟢 Niskie (oficjalne źródło, zweryfikowany podpis)

[Python/Pip - C:\Python311\python.exe]
  requests
    Obecna:    2.31.0
    Dostępna:  2.32.0
    Rozmiar:   ~500 KB
    Akcja:     pip install --upgrade requests
    Ryzyko:    🟢 Niskie (PyPI verified project)

PODSUMOWANIE:
  Całkowity rozmiar:  ~2.5 GB
  Szacowany czas:     ~15 minut
  Wymagany restart:   Nie
  Ryzyko ogólne:      🟢 Niskie
```

### 📋 4.3 Mock-Based Unit Tests
**Plik**: `tests/test-mocks.ps1`
**Opis**: Testy jednostkowe z mockowaniem zewnętrznych komend

**Framework**: Pester 5.x

**Przykład**:
```powershell
Describe "Parse-WingetUpgradeList" {
    It "Should parse standard output correctly" {
        $mockOutput = @"
Name                     Id                      Version    Available  Source
----------------------------------------------------------------------------------
Visual Studio Code       Microsoft.VisualStudioCode  1.85.0     1.86.0     winget
"@
        $result = Parse-WingetUpgradeList -Lines $mockOutput.Split("`n")
        $result.Count | Should -Be 1
        $result[0].Name | Should -Be "Visual Studio Code"
        $result[0].Id | Should -Be "Microsoft.VisualStudioCode"
    }
}
```

### 📋 4.4 Integration Tests na VM
**Plik**: `.github/workflows/integration-tests.yml`
**Opis**: Pełne testy integracyjne na czystych VM

**Środowiska testowe**:
- Windows 11 Pro
- Windows Server 2022
- Windows 10 (minimum supported version)

**Scenariusze**:
1. Czysta instalacja → uruchomienie skryptu
2. Aktualizacja z wymuszeniem błędu
3. Rollback po nieudanej aktualizacji
4. Równoległe vs. sekwencyjne wykonanie

---

## Milestone 5: Dystrybucja (v6.0)

### 📋 5.1 PowerShell Gallery
**Plik**: `UpdateUltra/UpdateUltra.psd1` (module manifest)
**Opis**: Publikacja jako moduł PowerShell

**Struktura modułu**:
```
UpdateUltra/
├── UpdateUltra.psd1           # Module manifest
├── UpdateUltra.psm1           # Main module file
├── Public/
│   └── Invoke-UpdateUltra.ps1 # Public function
├── Private/
│   ├── ParallelExecution.ps1
│   ├── WingetCache.ps1
│   └── ...
└── en-US/
    └── about_UpdateUltra.help.txt
```

**Instalacja**:
```powershell
Install-Module -Name UpdateUltra -Scope CurrentUser
Update-Ultra -Parallel -NotifyToast
```

### 📋 5.2 Chocolatey Package
**Plik**: `chocolatey/update-ultra.nuspec`
**Opis**: Package dla Chocolatey

**Instalacja**:
```powershell
choco install update-ultra
upd -Parallel
```

### 📋 5.3 Winget Manifest
**Plik**: `manifests/UpdateUltra.yaml`
**Opis**: Manifest dla Microsoft winget-pkgs repo

**Instalacja**:
```powershell
winget install UpdateUltra
```

---

## Milestone 6: UI/UX i Konfiguracja (v6.0)

### 📋 6.1 Progress Bar
**Plik**: `src/ProgressManager.psm1`
**Opis**: Graficzne paski postępu zamiast tekstowych komunikatów

**Przykład**:
```
[Winget] Aktualizacja w toku...
████████████░░░░░░░░  60% (15/25 pakietów) | Microsoft.VisualStudioCode
```

### 📋 6.2 Rozszerzony Output z Emoji
**Plik**: `src/OutputFormatter.psm1`
**Opis**: Bogatsze formatowanie wyjścia

**Symbole**:
- 🔄 Aktualizacja w trakcie
- ✅ Sukces
- ❌ Błąd
- ⏭️  Pominięto
- 🔥 Błąd krytyczny
- 📦 Nowy pakiet
- 🗑️  Usunięty pakiet

### 📋 6.3 Plik Konfiguracyjny JSON
**Plik**: `config/update-ultra.config.json`
**Opis**: Zewnętrzny plik konfiguracyjny

**Przykład**:
```json
{
  "execution": {
    "parallel": true,
    "maxParallelJobs": 4
  },
  "winget": {
    "ignoreIds": ["Discord.Discord", "Spotify.Spotify"],
    "retryIds": ["Notepad++.Notepad++"]
  },
  "python": {
    "venvRootPaths": ["C:\\venv", "D:\\Projects\\.venvs"],
    "ignorePaths": ["C:\\venv\\broken"]
  },
  "notifications": {
    "enabled": true,
    "toast": true,
    "email": {
      "enabled": false,
      "smtp": "smtp.gmail.com",
      "to": "admin@example.com"
    }
  }
}
```

### 📋 6.4 Profile Użytkowników
**Plik**: `config/profiles/`
**Opis**: Różne profile konfiguracji

**Przykład**:
```powershell
.\Update-WingetAll.ps1 -Profile "minimal"  # Tylko Winget + npm
.\Update-WingetAll.ps1 -Profile "full"     # Wszystkie środowiska
.\Update-WingetAll.ps1 -Profile "dev"      # Dev tools only
```

### 📋 6.5 System Lokalizacji
**Plik**: `locales/en-US.psd1`, `locales/pl-PL.psd1`
**Opis**: Wielojęzyczne komunikaty

**Użycie**:
```powershell
.\Update-WingetAll.ps1 -Language en-US
.\Update-WingetAll.ps1 -Language pl-PL  # Domyślne
```

**Struktura pliku językowego**:
```powershell
# en-US.psd1
@{
    StartUpdate = "Starting update process..."
    Completed = "Update completed successfully!"
    AvailableUpdates = "{0} updates available"
}
```

---

## Harmonogram Implementacji

| Milestone | Wersja | Czas Realizacji | Priorytet |
|-----------|--------|-----------------|-----------|
| M1: Optymalizacje | v5.0 | 1-2 tygodnie | 🔥 Wysoki |
| M2: Nowe Funkcje | v5.1 | 2-3 tygodnie | 🔥 Wysoki |
| M3: Raportowanie | v5.2 | 1-2 tygodnie | 🟡 Średni |
| M4: Bezpieczeństwo | v5.3 | 2 tygodnie | 🔥 Wysoki |
| M5: Dystrybucja | v6.0 | 1 tydzień | 🟡 Średni |
| M6: UI/UX | v6.0 | 1-2 tygodnie | 🟢 Niski |

**Całkowity szacowany czas**: 8-12 tygodni

---

## Kolejne Kroki

1. ✅ **Ukończone**: ParallelExecution.psm1 (M1.1)
2. 🔄 **W trakcie**: WingetCache.psm1 (M1.2)
3. 📋 **Następne**: Optymalizacja parsera (M1.3)

---

## Jak Przyczynić się do Rozwoju

1. Wybierz funkcję z roadmap
2. Sprawdź czy nikt nie pracuje nad nią (`Status: In Progress`)
3. Stwórz branch: `feature/M1.2-winget-cache`
4. Implementuj według specyfikacji
5. Dodaj testy
6. Stwórz Pull Request

---

## Kontakt i Wsparcie

- **Issues**: https://github.com/anthropics/update-ultra/issues
- **Discussions**: https://github.com/anthropics/update-ultra/discussions
- **Wiki**: https://github.com/anthropics/update-ultra/wiki

---

**Wersja dokumentu**: 1.0
**Ostatnia aktualizacja**: 2026-01-23
**Autor**: Claude Code + Tomasz
