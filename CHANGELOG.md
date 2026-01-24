# Changelog

Wszystkie znaczące zmiany w projekcie update-ultra będą dokumentowane w tym pliku.

Format oparty na [Keep a Changelog](https://keepachangelog.com/en/1.0.0/).

## [5.2.0] - 2025-01-23

### 📊 Dodano - Raportowanie i Monitoring (Etap 3)
- **HtmlReporter.psm1**: Interaktywne raporty HTML
  - Generowanie graficznych raportów z wynikami aktualizacji
  - Executive summary z metrykami (total duration, packages updated/failed, section statuses)
  - Wykresy Chart.js (pie charts dla statusów, bar charts dla czasu wykonania)
  - Tabele z sortowaniem (wyniki per sekcja, szczegóły pakietów)
  - Responsive design z gradient backgrounds
  - Funkcje: `New-HtmlReport`
  - Automatyczne zapisywanie w `%ProgramData%\update-ultra\reports`
- **MetricsExporter.psm1**: Eksport metryk do systemów monitoringu
  - **InfluxDB**: Eksport w formacie Line Protocol
  - **Prometheus**: Push do Pushgateway w text format
  - **Custom endpoints**: JSON lub plain text do custom HTTP endpoints
  - Metryki: duration_seconds, packages_updated_total, packages_failed_total, status_success per sekcja
  - Funkcje: `Export-MetricsToInfluxDB`, `Export-MetricsToPrometheus`, `Export-MetricsToCustomEndpoint`
  - Support dla Basic Auth, custom headers, labels/tags
- **ComparisonEngine.psm1**: Porównywanie uruchomień i analiza trendów
  - Porównywanie dwóch summary JSON (diff sekcji, pakietów, metryk)
  - Analiza trendów z ostatnich N uruchomień (średnie czasy, success rate)
  - Wykrywanie anomalii (outliers) w czasie wykonania
  - Generowanie raportów zmian (Text lub Markdown format)
  - Trend detection (Increasing/Decreasing/Stable) z linear regression
  - Funkcje: `Compare-UpdateRuns`, `Get-UpdateTrends`, `Show-ChangeReport`
  - Historia przechowywana w `%APPDATA%\update-ultra\history`

### 🔧 Zmieniono (Etap 3)
- Dodano embedded CSS i JavaScript (Chart.js) w HtmlReporter dla standalone raportów
- MetricsExporter wspiera różne backendy z jednolitym API
- ComparisonEngine automatycznie inicjalizuje katalog history

### 📦 Struktura Plików (Etap 3)
- `src/HtmlReporter.psm1` (~800 linii)
- `src/MetricsExporter.psm1` (~650 linii)
- `src/ComparisonEngine.psm1` (~750 linii)

---

## [5.1.0] - 2025-01-23

### 📅 Dodano - Scheduling i Automatyzacja
- **TaskScheduler.psm1**: Windows Task Scheduler integration
  - Automatyczne planowanie aktualizacji (Daily/Weekly/Monthly)
  - Funkcje: `Install-UpdateSchedule`, `Remove-UpdateSchedule`, `Get-UpdateSchedule`, `Test-UpdateSchedule`
  - Konfiguracja czasu uruchomienia, dni tygodnia, warunków (AC power, Network, Idle)
  - Przekazywanie parametrów skryptu do scheduled tasks
  - Walidacja konfiguracji i testowanie scheduled tasks
- **Parametry scheduling** w głównym skrypcie:
  - `-InstallSchedule`: Instaluje scheduled task
  - `-RemoveSchedule`: Usuwa scheduled task
  - `-RunAt <HH:mm>`: Godzina uruchomienia (domyślnie: "03:00")
  - `-Frequency <Daily|Weekly|Monthly>`: Częstotliwość (domyślnie: "Weekly")
  - `-DayOfWeek <Sunday|Monday|...>`: Dzień tygodnia dla Weekly (domyślnie: "Sunday")
  - `-ScheduleConditions <hashtable>`: Warunki wykonania (RequireAC, RequireNetwork, RequireIdle)

### ⚡ Dodano - Delta Updates (Inteligentne Aktualizacje)
- **DeltaUpdateManager.psm1**: Smart delta updates system
  - Aktualizacja TYLKO zmienionych pakietów (zamiast wszystkich)
  - Porównywanie stanu pakietów między uruchomieniami
  - Baseline state management w `%APPDATA%\update-ultra\delta-state`
  - Wykrywanie Added/Removed/Updated packages
  - Automatyczne zarządzanie historią baseline (domyślnie: ostatnie 10)
  - Funkcje: `Get-CurrentPackageState`, `Compare-PackageState`, `Get-DeltaUpdateTargets`, `Save-PackageStateBaseline`, `Invoke-DeltaUpdate`
  - Graceful degradation (brak baseline → full update)
- **Parametry delta mode** w głównym skrypcie:
  - `-DeltaMode`: Włącza tryb delta updates
  - `-ForceAll`: Wymusza pełną aktualizację (pomija delta)
- **Wydajność**: Delta mode redukuje czas aktualizacji o ~50% przy małych zmianach pakietów

### 🧪 Dodano - Testy
- **Unit tests (Pester 5.x)**:
  - `tests/unit/test-scheduler.ps1`: 11 kontekstów testowych dla TaskScheduler (parameter validation, triggers, conditions)
  - `tests/unit/test-delta-updates.ps1`: Comprehensive tests dla DeltaUpdateManager (state management, diff detection, baseline handling)
- **Integration tests**:
  - `tests/integration/test-scheduler-integration.ps1`: Full lifecycle testing (Install → Get → Test → Remove), wymaga Admin
  - `tests/integration/test-delta-integration.ps1`: Real-world scenarios, baseline history, performance comparison

### 🔧 Zmieniono
- Rozszerzono parametry skryptu o opcje scheduling i delta mode
- Import modułów TaskScheduler i DeltaUpdateManager tylko gdy potrzebne (lazy loading)
- Delta baseline automatycznie zapisywany po zakończeniu aktualizacji (gdy `-DeltaMode` aktywny)

### ⚙️ Kompatybilność
- Backward compatible z v5.0 (wszystkie nowe funkcje są opt-in)
- PowerShell 5.1 i 7+ compatible
- Windows 10/11 (scheduled tasks)
- Wymaga uprawnień Administrator dla scheduled tasks

### 📦 Struktura Plików
- `src/TaskScheduler.psm1` (~620 linii)
- `src/DeltaUpdateManager.psm1` (~550 linii)
- `tests/unit/test-scheduler.ps1`
- `tests/unit/test-delta-updates.ps1`
- `tests/integration/test-scheduler-integration.ps1`
- `tests/integration/test-delta-integration.ps1`

---

## [5.0.0] - 2025-01-23

### 🚀 Dodano - Wydajność
- **Zoptymalizowany parser Winget**: Refactoring z split-based na regex-based parsing
  - 30-50% szybsze parsowanie list pakietów
  - Lepsza obsługa edge cases (nazwy z spacjami, wersje beta/rc)
  - Funkcja `Parse-WingetUpgradeList` w `src/Update-WingetAll.ps1:395-426`
- **System cache'owania (WingetCache.psm1)**:
  - Cache w pamięci + opcjonalny disk cache
  - Konfigurowalny TTL (Time To Live)
  - Funkcje: `Get-CachedResult`, `Get-CachedWingetUpgrade`, `Clear-WingetCache`
  - Automatyczna invalidacja cache po operacjach modyfikujących
  - Integracja z głównym skryptem przez parametr `-EnableCache` i `-CacheTTL`
- **Moduł równoległego wykonania (ParallelExecution.psm1)**:
  - Równoległe wykonanie niezależnych sekcji z ThreadJob
  - Automatyczna analiza zależności między sekcjami
  - Funkcje: `Invoke-ParallelSteps`, `Get-OptimalStepGroups`

### 📸 Dodano - Snapshoty i Rollback
- **SnapshotManager.psm1**:
  - Tworzenie snapshotów zainstalowanych pakietów (Winget, Chocolatey, npm, pip, etc.)
  - Przechowywanie snapshotów w `%APPDATA%\update-ultra\snapshots`
  - Porównywanie snapshotów (diff added/removed/updated packages)
  - Rollback do poprzedniego stanu pakietów
  - Funkcje: `New-PackageSnapshot`, `Get-PackageSnapshots`, `Compare-PackageSnapshot`, `Restore-PackageSnapshot`
  - Parametr `-AutoSnapshot` w głównym skrypcie

### 🔔 Dodano - System powiadomień
- **NotificationManager.psm1**:
  - **Toast notifications**: Windows 10/11 native toast (wymaga BurntToast)
  - **Email notifications**: wysyłanie przez SMTP z HTML formatowaniem
  - **Webhook notifications**: integracja ze Slack, Discord, Teams, custom webhooks
  - Automatyczna detekcja typu webhook (Slack/Discord/Teams) po URL
  - Graceful degradation (brak BurntToast nie blokuje innych funkcji)
  - Funkcje: `Send-ToastNotification`, `Send-EmailNotification`, `Send-WebhookNotification`, `Send-UpdateNotification`
- **Parametry powiadomień** w głównym skrypcie:
  - `-NotifyToast`: Windows toast notification
  - `-NotifyEmail <email>`: email notification
  - `-SmtpServer`, `-SmtpPort`, `-SmtpUsername`, `-SmtpPassword`: konfiguracja SMTP
  - `-NotifyWebhook <url>`: webhook notification

### 🎣 Dodano - Hooks system
- **Pre-Update Hook**: wykonuje custom kod przed rozpoczęciem aktualizacji
  - Parametr: `-PreUpdateHook <scriptblock>`
  - Wywołanie w `src/Update-WingetAll.ps1:684-697`
- **Post-Update Hook**: wykonuje custom kod po zakończeniu aktualizacji
  - Parametr: `-PostUpdateHook <scriptblock>`
  - Wywołanie w `src/Update-WingetAll.ps1:1880-1897`
- **Section-specific hooks**: hooks dla konkretnych sekcji (Pre/Post per section)
  - Parametr: `-SectionHooks <hashtable>`
  - Wywołanie w funkcji `Invoke-Step` (lines 325-337, 386-398)
- Use cases: backup przed aktualizacją, wysyłanie custom metryk, integracja z monitoring

### 🧪 Dodano - Testy
- **Unit tests (Pester 5.x)**:
  - `tests/unit/test-parser-optimization.ps1`: 19 test cases dla parsera (edge cases, performance)
  - `tests/unit/test-cache.ps1`: testy cache (hit/miss, TTL, disk persistence, invalidation)
  - `tests/unit/test-notifications.ps1`: testy powiadomień (toast, email, webhook, graceful degradation)
- **Integration tests**:
  - `tests/integration/test-full-run.ps1`: pełne uruchomienie skryptu, hooks execution, module loading

### 📚 Dodano - Dokumentacja
- **ROADMAP.md**: plan rozwoju projektu (6 milestones, 30 funkcji)
- **DEVELOPMENT.md**: przewodnik dla developerów (coding conventions, testing strategies, git workflow)
- **templates/module-template.psm1**: szablon nowych modułów PowerShell
- **CHANGELOG.md**: ten plik

### 🔧 Zmieniono
- Zaktualizowano banner skryptu do wersji v5.0 (`src/Update-WingetAll.ps1:671`)
- Zaktualizowano log końcowy do v5.0 (`src/Update-WingetAll.ps1:1950`)
- Rozszerzono parametry skryptu o nowe opcje (cache, snapshoty, powiadomienia, hooks)
- Zmodyfikowano funkcję `Invoke-Step` do obsługi section-specific hooks

### 🐛 Naprawiono
- Parser Winget lepiej obsługuje pakiety z długimi nazwami zawierającymi spacje
- Parser Winget ignoruje linie "require explicit targeting" bez duplikowania pakietów
- Cache invalidation po operacjach `winget source update`

### 🔒 Bezpieczeństwo
- Email passwords akceptują SecureString (opcjonalnie plain text dla kompatybilności)
- Webhook URLs są walidowane przed wysłaniem
- Toast notifications używają graceful degradation (brak BurntToast = warning, nie error)

### 📦 Zależności
- **Opcjonalne**:
  - BurntToast (dla toast notifications): `Install-Module BurntToast`
  - Pester 5.x (dla testów): `Install-Module Pester -MinimumVersion 5.0`
- **Wbudowane**:
  - System.Net.Mail (email)
  - ThreadJob (parallel execution)

### ⚙️ Kompatybilność
- Backward compatible z v4.2 (wszystkie nowe funkcje są opt-in)
- PowerShell 5.1 i 7+ compatible
- Windows 10/11 (toast wymaga Win10+)

---

## [4.2.0] - 2024-01-XX

### 🐛 Naprawiono
- Fix Winget array bug
- Ulepszona widoczność WSL sudo prompt
- Ignorowanie uszkodzonych repozytoriów Git

### 📝 Dodano
- CLAUDE.md documentation dla AI instances
- Comprehensive debug output dla diagnostyki list pakietów

---

## [4.1.0] - 2023-XX-XX

### ✨ Dodano
- Rozszerzone statystyki (Installed, Available, Updated, Skipped, Failed)
- Listy pakietów z śledzeniem wersji (Before → After)
- Interaktywne prompty dla WSL distros

---

## [4.0.0] - 2023-XX-XX

### 🚀 Dodano - Major Release
- 10 nowych środowisk (Scoop, pipx, Cargo, Go, Ruby, Composer, Yarn, pnpm, MS Store, WSL Distros)
- Uniwersalne wykrywanie zainstalowanych narzędzi
- Podsumowanie tabelaryczne (OK/FAIL/SKIP, czas, liczniki)
- Summary JSON output
- Logi Winget z sanityzowanymi nazwami plików
- Przełączniki Skip dla każdej sekcji
- Naprawiony parser Winget (ignoruje linie postępu)

---

## [3.x] - 2023-XX-XX

### 🐛 Naprawiono
- Winget parser fixes
- Explicit targeting support

---

## [Wcześniejsze wersje]
- Podstawowa funkcjonalność aktualizacji Winget, Python/Pip, npm
- Logi tekstowe
- Podstawowe error handling

---

## Plany na przyszłość

Zobacz [ROADMAP.md](ROADMAP.md) dla szczegółowego planu rozwoju.

### Milestone 2: Nowe Funkcje Core
- TaskScheduler.psm1 - Scheduling i auto-update
- DeltaUpdateManager.psm1 - Aktualizacja tylko zmienionych pakietów

### Milestone 3: Raportowanie
- HtmlReporter.psm1 - Graficzne raporty HTML z wykresami
- MetricsExporter.psm1 - Eksport do InfluxDB/Prometheus
- ComparisonEngine.psm1 - Porównanie z poprzednimi uruchomieniami

### Milestone 4: Bezpieczeństwo
- SignatureValidator.psm1 - Weryfikacja podpisów cyfrowych
- Rozszerzony -WhatIf z szczegółowym kosztorysem

### Milestone 5: Dystrybucja
- Moduł PowerShell Gallery
- Chocolatey package
- Winget manifest

### Milestone 6: UI/UX
- ProgressManager.psm1 - Progress bary
- OutputFormatter.psm1 - Rozszerzony output z emoji
- System konfiguracji JSON
- Profile użytkowników
- System lokalizacji (en-US, pl-PL)
