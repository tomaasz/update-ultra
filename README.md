# update-ultra v5.1

Uniwersalny skrypt do aktualizacji WSZYSTKICH środowisk deweloperskich na Windows.
Automatycznie wykrywa zainstalowane narzędzia i aktualizuje je z zaawansowanymi funkcjami wydajnościowymi, automatyzacją i powiadomieniami.

## Obsługiwane środowiska (19 sekcji)

**Menedżery pakietów:**
- ✅ Winget (z obsługą explicit targeting i pinned packages)
- ✅ Chocolatey
- ✅ Scoop
- ✅ npm (global)
- ✅ yarn (global)
- ✅ pnpm (global)
- ✅ pipx (Python CLI tools)
- ✅ Cargo (Rust packages)
- ✅ Go tools
- ✅ Ruby gems
- ✅ Composer (PHP)
- ✅ MS Store Apps

**Środowiska:**
- ✅ Python/Pip (z auto-wykrywaniem venvs)
- ✅ PowerShell Modules
- ✅ VS Code Extensions
- ✅ Docker Images
- ✅ Git Repositories (auto-pull)
- ✅ WSL (Windows Subsystem for Linux)
- ✅ WSL Distros (apt/yum/pacman wewnątrz dystrybucji)
  - Debian/Ubuntu (apt)
  - RHEL/CentOS/Fedora (yum)
  - Arch Linux (pacman)

## Funkcje v5.1 (NAJNOWSZE!)
📅 **Scheduling i Automatyzacja (NOWE w 5.1):**
- ⏰ **TaskScheduler** - automatyczne planowanie aktualizacji (Daily/Weekly/Monthly)
- ⚙️ **Konfiguracja warunków** - uruchamianie tylko przy zasilaniu AC, połączeniu sieciowym lub idle
- 🎯 **Przekazywanie parametrów** - scheduled tasks mogą używać wszystkich parametrów skryptu

⚡ **Delta Updates - Inteligentne Aktualizacje (NOWE w 5.1):**
- 🔍 **Smart update** - aktualizuje TYLKO zmienione pakiety (zamiast wszystkich)
- 📊 **Baseline tracking** - porównuje stan pakietów między uruchomieniami
- ⚡ **Wydajność** - ~50% szybsze aktualizacje przy małych zmianach
- 🗄️ **Historia baseline** - automatyczne zarządzanie stanem pakietów

🚀 **Wydajność (v5.0):**
- ⚡ **Zoptymalizowany parser Winget** - regex-based, 30-50% szybszy niż split-based
- 🗄️ **System cache'owania** - cache'owanie wyników winget (pamięć + dysk, configurowalny TTL)
- 🔄 **Równoległe wykonanie** - możliwość równoległego wykonania niezależnych sekcji (moduł ParallelExecution)

📸 **Snapshoty i Rollback (v5.0):**
- 💾 **SnapshotManager** - tworzenie snapshotów pakietów przed aktualizacją
- ⏪ **Rollback** - możliwość przywrócenia poprzedniego stanu pakietów
- 📦 **Porównywanie snapshotów** - analiza zmian między snapshotami

🔔 **Powiadomienia (v5.0):**
- 🔔 **Toast notifications** - Windows 10/11 native toast (wymaga BurntToast)
- 📧 **Email notifications** - powiadomienia SMTP z podsumowaniem aktualizacji
- 🌐 **Webhook notifications** - integracja ze Slack, Discord, Teams lub custom webhooks

🎣 **Hooks system (v5.0):**
- ⚙️ **Pre/Post-Update hooks** - wykonaj custom kod przed/po aktualizacji
- 🎯 **Section-specific hooks** - hooks dla konkretnych sekcji (np. tylko dla Winget)

🔧 **Funkcje z v4.0:**
- ✨ **Automatyczne wykrywanie** - każda sekcja sprawdza czy narzędzie jest zainstalowane
- ✨ **Uniwersalność** - działa na różnych komputerach, pomija brakujące narzędzia (SKIP)
- ✨ **Ignorowanie pakietów** - możliwość wykluczenia pakietów z błędów (np. Discord auto-update)
- 📊 Podsumowanie tabelą (OK/FAIL/SKIP, czas, liczniki)
- 📝 Pełny log tekstowy + plik summary JSON
- 🔒 Bezpieczne uruchamianie kroków (każdy krok osobno)
- ⚙️ Przełączniki Skip dla każdej sekcji
- 🗂️ Logi Winget "explicit" z sanityzowanymi nazwami plików

## Wymagania
- Windows 10/11
- PowerShell 7+
- Uruchomienie jako Administrator
- Zainstalowane narzędzia (opcjonalnie - skrypt pominie brakujące)

## Instalacja aliasu "upd"

**Zalecane:** Zainstaluj alias, aby uruchamiać skrypt jednym poleceniem:

```powershell
cd C:\Dev\update-ultra
.\install-alias.ps1
```

Po instalacji możesz używać:
```powershell
upd                    # Uruchom pełną aktualizację (z auto-admin)
upd -WhatIf            # Podgląd bez zmian
upd -Force             # Wymuś aktualizacje
upd -Skip Docker,WSL   # Pomiń wybrane sekcje
```

## Uruchomienie (bez aliasu)

```powershell
# Podstawowe uruchomienie (wszystkie sekcje)
.\src\Update-WingetAll.ps1

# Pomiń wybrane sekcje
.\src\Update-WingetAll.ps1 -SkipDocker -SkipWSLDistros

# WhatIf mode (dry-run, bez zmian)
.\src\Update-WingetAll.ps1 -WhatIf

# Force mode (wymusza aktualizacje)
.\src\Update-WingetAll.ps1 -Force
```

## Nowe funkcje v5.1 - Przykłady użycia

### Scheduling - Automatyczne aktualizacje (NOWE v5.1)
```powershell
# Zainstaluj scheduled task - codziennie o 3:00
.\src\Update-WingetAll.ps1 -InstallSchedule -RunAt "03:00" -Frequency Daily

# Zainstaluj scheduled task - co niedzielę o 4:00
.\src\Update-WingetAll.ps1 -InstallSchedule -RunAt "04:00" -Frequency Weekly -DayOfWeek Sunday

# Zainstaluj scheduled task - co miesiąc o 2:00
.\src\Update-WingetAll.ps1 -InstallSchedule -RunAt "02:00" -Frequency Monthly

# Scheduled task z warunkami (tylko przy AC power i sieci)
$conditions = @{
    RequireAC = $true
    RequireNetwork = $true
    RequireIdle = $false
}
.\src\Update-WingetAll.ps1 -InstallSchedule -RunAt "03:00" `
    -Frequency Weekly -DayOfWeek Sunday `
    -ScheduleConditions $conditions

# Usuń scheduled task
.\src\Update-WingetAll.ps1 -RemoveSchedule

# Sprawdź konfigurację scheduled task
Import-Module .\src\TaskScheduler.psm1
Get-UpdateSchedule
Test-UpdateSchedule
```

### Delta Updates - Inteligentne aktualizacje (NOWE v5.1)
```powershell
# Włącz delta mode - aktualizuje TYLKO zmienione pakiety
.\src\Update-WingetAll.ps1 -DeltaMode

# Wymuś pełną aktualizację (pomiń delta)
.\src\Update-WingetAll.ps1 -DeltaMode -ForceAll

# Delta mode + cache + powiadomienia
.\src\Update-WingetAll.ps1 -DeltaMode -EnableCache -NotifyToast

# Ręczne zarządzanie baseline
Import-Module .\src\DeltaUpdateManager.psm1

# Wyświetl aktualny stan pakietów
$currentState = Get-CurrentPackageState -Sources @('Winget', 'npm', 'pip')
$currentState | ConvertTo-Json -Depth 10

# Porównaj z baseline
$baseline = Get-BaselineState
$diff = Compare-PackageState -CurrentState $currentState -BaselineState $baseline.State

# Wyświetl diff
Write-Host "Added: $($diff.Winget.Added.Count)"
Write-Host "Removed: $($diff.Winget.Removed.Count)"
Write-Host "Updated: $($diff.Winget.Updated.Count)"

# Wyczyść wszystkie baseline (reset)
Clear-DeltaBaselines
```

### Cache'owanie (wydajność v5.0)
```powershell
# Włącz cache z domyślnym TTL (300s = 5 min)
.\src\Update-WingetAll.ps1 -EnableCache

# Włącz cache z custom TTL (10 minut)
.\src\Update-WingetAll.ps1 -EnableCache -CacheTTL 600

# Wyczyść cache ręcznie
Import-Module .\src\WingetCache.psm1
Clear-WingetCache -All
```

### Snapshoty i Rollback
```powershell
# Automatyczny snapshot przed aktualizacją
.\src\Update-WingetAll.ps1 -AutoSnapshot

# Ręczne zarządzanie snapshotami
Import-Module .\src\SnapshotManager.psm1

# Utwórz snapshot
$snapshot = New-PackageSnapshot -Name "pre-update-backup"

# Wyświetl snapshoty
Get-PackageSnapshots

# Porównaj snapshoty
Compare-PackageSnapshot -Snapshot1Id $id1 -Snapshot2Id $id2

# Przywróć snapshot
Restore-PackageSnapshot -SnapshotId $id
```

### Powiadomienia
```powershell
# Toast notification (wymaga BurntToast: Install-Module BurntToast)
.\src\Update-WingetAll.ps1 -NotifyToast

# Email notification
.\src\Update-WingetAll.ps1 -NotifyEmail "admin@example.com" `
    -SmtpServer "smtp.gmail.com" -SmtpPort 587 `
    -SmtpUsername "user@gmail.com" -SmtpPassword "app-password"

# Slack webhook
.\src\Update-WingetAll.ps1 -NotifyWebhook "https://hooks.slack.com/services/XXX/YYY/ZZZ"

# Discord webhook
.\src\Update-WingetAll.ps1 -NotifyWebhook "https://discord.com/api/webhooks/XXX/YYY"

# Wszystkie powiadomienia naraz
.\src\Update-WingetAll.ps1 -NotifyToast -NotifyEmail "admin@example.com" `
    -SmtpServer "smtp.gmail.com" -SmtpUsername "user@gmail.com" -SmtpPassword "pass" `
    -NotifyWebhook "https://hooks.slack.com/services/XXX"
```

### Hooks system
```powershell
# Pre-Update Hook - wykona się przed aktualizacją
$preHook = {
    Write-Host "Starting backup..."
    # Custom backup logic
}
.\src\Update-WingetAll.ps1 -PreUpdateHook $preHook

# Post-Update Hook - wykona się po aktualizacji
$postHook = {
    Write-Host "Sending metrics to monitoring..."
    # Custom metrics logic
}
.\src\Update-WingetAll.ps1 -PostUpdateHook $postHook

# Section-specific hooks
$sectionHooks = @{
    Winget = @{
        Pre = { Write-Host "Before Winget section..." }
        Post = { Write-Host "After Winget section..." }
    }
    npm = @{
        Pre = { Write-Host "Before npm section..." }
        Post = { Write-Host "After npm section..." }
    }
}
.\src\Update-WingetAll.ps1 -SectionHooks $sectionHooks

# Kombinacja wszystkich hooków
.\src\Update-WingetAll.ps1 -PreUpdateHook $preHook -PostUpdateHook $postHook -SectionHooks $sectionHooks
```

### Pełna konfiguracja z nowymi funkcjami v5.1
```powershell
# Maksymalna wydajność + delta updates + powiadomienia + snapshoty
.\src\Update-WingetAll.ps1 `
    -DeltaMode `
    -EnableCache -CacheTTL 600 `
    -AutoSnapshot `
    -NotifyToast `
    -NotifyEmail "admin@example.com" `
    -SmtpServer "smtp.gmail.com" `
    -SmtpUsername "user@gmail.com" `
    -SmtpPassword "app-password" `
    -PreUpdateHook { Write-Host "Starting update..." } `
    -PostUpdateHook { Write-Host "Update completed!" }

# Scheduled task z pełną konfiguracją
# Uwaga: parametry -NotifyToast, -EnableCache, -DeltaMode zostaną przekazane do scheduled task
.\src\Update-WingetAll.ps1 -InstallSchedule `
    -RunAt "03:00" -Frequency Weekly -DayOfWeek Sunday `
    -ScheduleConditions @{ RequireAC = $true; RequireNetwork = $true }
```

## Konfiguracja

Skrypt ma sekcję CONFIG na początku, gdzie możesz dostosować:
- `$WingetIgnoreIds` - pakiety do ignorowania (np. Discord.Discord)
- `$PythonVenvRootPaths` - ścieżki do virtualenvs
- `$GitRootPaths` - katalogi z repozytoriami git
- `$GoTools` - narzędzia Go do aktualizacji
- `$WSLDistros` - dystrybucje WSL do aktualizacji
- i więcej...

## Testy
Projekt posiada kompleksową suite testów jednostkowych i integracyjnych.

### Uruchomienie testów (wymaga Pester 5.x)
```powershell
# Zainstaluj Pester jeśli nie masz
Install-Module -Name Pester -MinimumVersion 5.0 -Scope CurrentUser -Force

# Uruchom wszystkie testy jednostkowe
Invoke-Pester .\tests\unit\

# Uruchom konkretny test
Invoke-Pester .\tests\unit\test-parser-optimization.ps1
Invoke-Pester .\tests\unit\test-cache.ps1
Invoke-Pester .\tests\unit\test-notifications.ps1

# Uruchom testy integracyjne (wymaga Admin)
Invoke-Pester .\tests\integration\test-full-run.ps1

# Legacy testy (backward compatibility)
pwsh -NoProfile -File .\tests\test_sanitize.ps1
pwsh -NoProfile -File .\tests\test-winget-parser.ps1
```

### Pokrycie testów
- ✅ **Parser Optimization** - 19 test cases (różne edge cases, performance)
- ✅ **WingetCache** - cache hit/miss, TTL expiration, disk persistence
- ✅ **NotificationManager** - toast, email, webhook, graceful degradation
- ✅ **Integration** - full run, hooks execution, module loading

Testy uruchamiane są automatycznie w GitHub Actions przy każdym push/PR.
