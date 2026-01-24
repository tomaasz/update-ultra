# Update-Ultra: Przewodnik Developera

## Spis Treści

1. [Architektura Projektu](#architektura-projektu)
2. [Struktura Katalogów](#struktura-katalogów)
3. [Konwencje Kodowania](#konwencje-kodowania)
4. [Proces Rozwoju](#proces-rozwoju)
5. [Testowanie](#testowanie)
6. [Debugowanie](#debugowanie)
7. [Współpraca](#współpraca)

---

## Architektura Projektu

### Główne Komponenty

```
┌─────────────────────────────────────────┐
│     Update-WingetAll.ps1 (Main)         │
│  - Orchestrator wszystkich operacji     │
│  - Zarządzanie parametrami CLI          │
│  - Logowanie i raportowanie             │
└──────────────┬──────────────────────────┘
               │
      ┌────────┴────────┐
      │                 │
┌─────▼──────┐    ┌────▼─────────┐
│  Core      │    │  Extensions  │
│  Modules   │    │  Modules     │
└─────┬──────┘    └────┬─────────┘
      │                │
      │                │
┌─────▼────────────────▼─────┐
│  Execution Engine          │
│  - Invoke-Step             │
│  - Try-Run                 │
│  - Error handling          │
└────────────────────────────┘
```

### Core Modules (Obowiązkowe)

1. **ParallelExecution.psm1**
   - Równoległe wykonanie sekcji
   - Grupowanie zadań według zależności
   - Job management

2. **WingetCache.psm1**
   - Cache'owanie wyników winget
   - Zarządzanie pamięcią i dyskiem
   - Inteligentne unieważnianie

3. **Parsers.psm1** (Planowane)
   - Zoptymalizowane parsery dla winget, pip, npm, etc.
   - Zunifikowane API dla wszystkich menedżerów pakietów

### Extension Modules (Opcjonalne)

4. **SnapshotManager.psm1**
   - Tworzenie snapshotów przed aktualizacją
   - Rollback do poprzednich wersji
   - Zarządzanie historią

5. **TaskScheduler.psm1**
   - Integracja z Windows Task Scheduler
   - Automatyczne harmonogramy
   - Trigger management

6. **NotificationManager.psm1**
   - Toast notifications (BurntToast)
   - Email (SMTP)
   - Webhooks (Slack, Discord, Teams)

7. **HtmlReporter.psm1**
   - Generowanie raportów HTML
   - Wykresy i wizualizacje
   - Interaktywne tabele

8. **MetricsExporter.psm1**
   - Eksport do InfluxDB
   - Prometheus Pushgateway
   - Custom backends

---

## Struktura Katalogów

```
update-ultra/
├── src/
│   ├── Update-WingetAll.ps1         # Main script
│   ├── ParallelExecution.psm1       # Core: Parallel execution
│   ├── WingetCache.psm1             # Core: Caching
│   ├── Parsers.psm1                 # Core: Optimized parsers
│   ├── SnapshotManager.psm1         # Ext: Rollback system
│   ├── TaskScheduler.psm1           # Ext: Auto-scheduling
│   ├── NotificationManager.psm1     # Ext: Notifications
│   ├── HtmlReporter.psm1            # Ext: HTML reports
│   ├── MetricsExporter.psm1         # Ext: Metrics export
│   └── Utils.psm1                   # Shared utilities
│
├── config/
│   ├── update-ultra.config.json     # Default config
│   ├── profiles/
│   │   ├── minimal.json             # Minimal profile
│   │   ├── full.json                # Full profile
│   │   └── dev.json                 # Dev-only profile
│   └── schemas/
│       └── config.schema.json       # JSON schema for validation
│
├── templates/
│   ├── html/
│   │   ├── report-template.html     # HTML report template
│   │   ├── styles.css               # Styles
│   │   └── chart.min.js             # Chart.js
│   └── email/
│       └── notification.html        # Email template
│
├── locales/
│   ├── en-US.psd1                   # English strings
│   ├── pl-PL.psd1                   # Polish strings (default)
│   └── de-DE.psd1                   # German strings
│
├── tests/
│   ├── unit/
│   │   ├── test-winget-parser.ps1
│   │   ├── test-cache.ps1
│   │   ├── test-parallel.ps1
│   │   └── test-sanitize.ps1
│   ├── integration/
│   │   ├── test-full-run.ps1
│   │   ├── test-rollback.ps1
│   │   └── test-scheduled.ps1
│   └── mocks/
│       ├── mock-winget-output.txt
│       ├── mock-pip-output.txt
│       └── mock-npm-output.json
│
├── docs/
│   ├── API.md                       # API documentation
│   ├── EXAMPLES.md                  # Usage examples
│   ├── TROUBLESHOOTING.md           # Common issues
│   └── CONTRIBUTING.md              # Contribution guide
│
├── scripts/
│   ├── install-alias.ps1            # Install 'upd' alias
│   ├── uninstall.ps1                # Uninstall script
│   └── build-module.ps1             # Build PowerShell module
│
├── .github/
│   ├── workflows/
│   │   ├── tests.yml                # CI: Unit tests
│   │   ├── integration.yml          # CI: Integration tests
│   │   └── release.yml              # CI: Release automation
│   └── ISSUE_TEMPLATE/
│       ├── bug_report.md
│       └── feature_request.md
│
├── ROADMAP.md                       # Development roadmap
├── DEVELOPMENT.md                   # This file
├── CLAUDE.md                        # AI assistant guide
├── README.md                        # User documentation
├── LICENSE                          # MIT License
└── CHANGELOG.md                     # Version history
```

---

## Konwencje Kodowania

### Nazewnictwo

1. **Funkcje**: PascalCase z czasownikiem PowerShell
   ```powershell
   function Get-CachedResult { }
   function Invoke-ParallelSteps { }
   function New-PackageSnapshot { }
   ```

2. **Zmienne**: camelCase dla lokalnych, PascalCase dla parametrów
   ```powershell
   $localVariable = "value"
   [string]$ParameterName
   ```

3. **Moduły**: PascalCase z suffiksem `.psm1`
   ```
   WingetCache.psm1
   ParallelExecution.psm1
   ```

### Formatowanie

```powershell
# GOOD: Clean function with proper formatting
function Get-Example {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Name,

        [switch]$Force
    )

    # Single responsibility
    $result = Get-Data -Name $Name

    # Early return on error
    if (-not $result) {
        Write-Error "No data found"
        return
    }

    # Process and return
    return $result | Format-Output
}

# BAD: Mixed styles, unclear logic
function getExample($n,$f){
  $r=Get-Data -Name $n
  if($r){return $r|Format-Output}else{Write-Error "No data"}
}
```

### Comment Headers

Każda funkcja publiczna musi mieć pełny comment-based help:

```powershell
<#
.SYNOPSIS
Short one-line description

.DESCRIPTION
Detailed multi-line description explaining:
- What the function does
- When to use it
- Important considerations

.PARAMETER ParameterName
Description of this parameter

.EXAMPLE
Get-Example -Name "Test"
Description of what this example does

.EXAMPLE
Get-Example -Name "Test" -Force
Another example with different parameters

.NOTES
Version: 1.0
Author: update-ultra team
#>
```

### Error Handling

```powershell
# GOOD: Proper error handling
function Get-SafeData {
    [CmdletBinding()]
    param([string]$Path)

    try {
        # Attempt operation
        $data = Get-Content $Path -ErrorAction Stop

        # Validate result
        if (-not $data) {
            throw "File is empty: $Path"
        }

        return $data
    }
    catch [System.IO.FileNotFoundException] {
        Write-Error "File not found: $Path"
        return $null
    }
    catch {
        Write-Error "Unexpected error: $($_.Exception.Message)"
        throw
    }
}

# BAD: Silent failures
function Get-Data {
    $data = Get-Content $Path -ErrorAction SilentlyContinue
    return $data  # Może być $null bez ostrzeżenia!
}
```

### PowerShell 5.1 Compatibility

❌ **NIE UŻYWAJ** (tylko PS 7+):
```powershell
$value = $null ?? "default"  # Null coalescing
$items = @(1..10).ForEach{$_ * 2}  # ForEach method
```

✅ **UŻYWAJ** (PS 5.1 compatible):
```powershell
$value = if ($null -eq $var) { "default" } else { $var }
$items = 1..10 | ForEach-Object { $_ * 2 }
```

### Module Structure

```powershell
# MyModule.psm1

# Private functions (not exported)
function Get-PrivateHelper {
    # Internal use only
}

# Public functions (exported)
function Get-PublicFunction {
    [CmdletBinding()]
    param()

    # Use private helpers
    $data = Get-PrivateHelper

    return $data
}

# Export only public functions
Export-ModuleMember -Function Get-PublicFunction
```

---

## Proces Rozwoju

### 1. Planowanie (Before Code)

```bash
# 1. Utwórz issue na GitHub
https://github.com/user/update-ultra/issues/new

# 2. Przypisz do milestone
Milestone: v5.1 - Nowe Funkcje

# 3. Dodaj labels
Labels: enhancement, high-priority, help-wanted

# 4. Stwórz branch
git checkout -b feature/M2.1-snapshot-manager
```

### 2. Implementacja (During Code)

```powershell
# 1. Stwórz moduł z template
Copy-Item .\templates\module-template.psm1 .\src\SnapshotManager.psm1

# 2. Implementuj funkcje step-by-step
# - Najpierw prywatne helpery
# - Potem publiczne API
# - Na końcu dokumentacja

# 3. Dodaj testy równolegle z kodem
New-Item .\tests\unit\test-snapshot.ps1

# 4. Uruchamiaj testy często
Invoke-Pester .\tests\unit\test-snapshot.ps1

# 5. Commit często, małe zmiany
git add src\SnapshotManager.psm1 tests\unit\test-snapshot.ps1
git commit -m "feat(snapshot): Add New-PackageSnapshot function"
```

### 3. Testowanie (After Code)

```powershell
# 1. Unit tests
Invoke-Pester .\tests\unit\

# 2. Integration tests
Invoke-Pester .\tests\integration\

# 3. Manual testing
.\src\Update-WingetAll.ps1 -CreateSnapshot -WhatIf

# 4. Performance testing
Measure-Command { .\src\Update-WingetAll.ps1 -Parallel }
```

### 4. Code Review

```bash
# 1. Push branch
git push origin feature/M2.1-snapshot-manager

# 2. Stwórz Pull Request
# - Link do issue
# - Opis zmian
# - Screenshots/output jeśli applicable
# - Checklist:
#   [x] Testy passed
#   [x] Dokumentacja updated
#   [x] CHANGELOG.md updated

# 3. Request review
# - Co najmniej 1 reviewer
# - Adresuj feedback
```

### 5. Merge i Release

```bash
# 1. Merge do main
git checkout main
git merge feature/M2.1-snapshot-manager

# 2. Tag version
git tag v5.1.0
git push origin v5.1.0

# 3. Update CHANGELOG.md
# 4. Publikuj release notes
```

---

## Testowanie

### Unit Tests z Pester

```powershell
# tests/unit/test-cache.ps1

BeforeAll {
    # Import module
    Import-Module "$PSScriptRoot\..\..\src\WingetCache.psm1" -Force

    # Setup test environment
    $script:testCacheDir = "$env:TEMP\update-ultra-test-cache"
    Initialize-WingetCache -EnableDiskCache -CacheDirectory $script:testCacheDir
}

AfterAll {
    # Cleanup
    if (Test-Path $script:testCacheDir) {
        Remove-Item $script:testCacheDir -Recurse -Force
    }
}

Describe "WingetCache" {
    Context "Get-CachedResult" {
        It "Should cache command results" {
            $key = "test-command"
            $firstCall = Get-CachedResult -Key $key -ScriptBlock { Get-Date }

            Start-Sleep -Milliseconds 100

            $secondCall = Get-CachedResult -Key $key -ScriptBlock { Get-Date }

            # Second call should return cached result (same time)
            $firstCall | Should -Be $secondCall
        }

        It "Should respect TTL expiration" {
            $key = "test-ttl"
            $firstCall = Get-CachedResult -Key $key -TTL 1 -ScriptBlock { Get-Random }

            Start-Sleep -Seconds 2

            $secondCall = Get-CachedResult -Key $key -TTL 1 -ScriptBlock { Get-Random }

            # After TTL, should execute again (different random)
            $firstCall | Should -Not -Be $secondCall
        }

        It "Should force refresh with -Force" {
            $key = "test-force"
            $firstCall = Get-CachedResult -Key $key -ScriptBlock { Get-Random }
            $secondCall = Get-CachedResult -Key $key -Force -ScriptBlock { Get-Random }

            $firstCall | Should -Not -Be $secondCall
        }
    }

    Context "Clear-WingetCache" {
        It "Should clear specific cache key" {
            $key = "test-clear"
            Get-CachedResult -Key $key -ScriptBlock { "data" }

            Clear-WingetCache -Key $key

            $stats = Get-CacheStatistics
            # Key should not exist after clear
            # (implementation detail - verify via stats or direct access)
        }

        It "Should clear all cache with -All" {
            Get-CachedResult -Key "test1" -ScriptBlock { "data1" }
            Get-CachedResult -Key "test2" -ScriptBlock { "data2" }

            Clear-WingetCache -All

            $stats = Get-CacheStatistics
            $stats.MemoryEntries | Should -Be 0
        }
    }
}
```

### Integration Tests

```powershell
# tests/integration/test-full-run.ps1

Describe "Full Update Run" {
    It "Should complete successfully with -WhatIf" {
        $result = & "$PSScriptRoot\..\..\src\Update-WingetAll.ps1" -WhatIf -SkipWSL -SkipDocker

        $LASTEXITCODE | Should -Be 0
    }

    It "Should generate log files" {
        $logDir = "$env:ProgramData\Winget-Logs"
        & "$PSScriptRoot\..\..\src\Update-WingetAll.ps1" -WhatIf -LogDirectory $logDir

        $logFiles = Get-ChildItem $logDir -Filter "dev_update_*.log"
        $logFiles.Count | Should -BeGreaterThan 0
    }

    It "Should respect -Sequential flag" {
        $sequential = Measure-Command {
            & "$PSScriptRoot\..\..\src\Update-WingetAll.ps1" -Sequential -WhatIf
        }

        # Sequential should work (existence test)
        $sequential.TotalSeconds | Should -BeGreaterThan 0
    }
}
```

### Mocking External Commands

```powershell
Describe "Parse-WingetUpgradeList with Mocks" {
    BeforeAll {
        # Mock winget command
        Mock -CommandName winget -MockWith {
            param($command, $flags)

            if ($command -eq "upgrade") {
                return @"
Name                     Id                      Version    Available  Source
----------------------------------------------------------------------------------
Visual Studio Code       Microsoft.VisualStudioCode  1.85.0     1.86.0     winget
Git                      Git.Git                 2.42.0     2.43.0     winget
"@
            }
        }
    }

    It "Should parse mocked winget output" {
        $output = winget upgrade
        $parsed = Parse-WingetUpgradeList -Lines $output.Split("`n")

        $parsed.Count | Should -Be 2
        $parsed[0].Name | Should -Be "Visual Studio Code"
        $parsed[1].Id | Should -Be "Git.Git"
    }
}
```

---

## Debugowanie

### Verbose Output

```powershell
# Włącz verbose logging
.\Update-WingetAll.ps1 -Verbose

# Output:
# VERBOSE: Cache HIT: winget-list-all (age: 45s)
# VERBOSE: Starting parallel group: PackageManagers
# VERBOSE: Job completed: Winget (120s)
```

### Debug Breakpoints

```powershell
# W kodzie:
function Get-Example {
    $data = Get-Data

    # Set breakpoint here
    $PSDebugContext  # Inspect variables

    return $data
}

# W konsoli:
Set-PSBreakpoint -Script .\src\Update-WingetAll.ps1 -Line 500
.\src\Update-WingetAll.ps1
```

### Transcript Logging

```powershell
# Zapisz CAŁY output (including errors) do pliku
Start-Transcript -Path "C:\Logs\debug-session.txt"

.\src\Update-WingetAll.ps1 -Verbose

Stop-Transcript
```

### Performance Profiling

```powershell
# Measure każdej sekcji
$measurements = @{}

$measurements['Winget'] = Measure-Command {
    # ... winget operations
}

$measurements['Pip'] = Measure-Command {
    # ... pip operations
}

# Wyświetl najwolniejsze sekcje
$measurements.GetEnumerator() | Sort-Object Value -Descending | Format-Table
```

---

## Współpraca

### Git Workflow

```bash
# 1. Fork repository
# 2. Clone your fork
git clone https://github.com/YOUR-USERNAME/update-ultra.git

# 3. Add upstream remote
git remote add upstream https://github.com/ORIGINAL-OWNER/update-ultra.git

# 4. Create feature branch
git checkout -b feature/my-awesome-feature

# 5. Make changes and commit
git add .
git commit -m "feat: Add my awesome feature"

# 6. Keep branch updated
git fetch upstream
git rebase upstream/main

# 7. Push to your fork
git push origin feature/my-awesome-feature

# 8. Create Pull Request on GitHub
```

### Commit Message Format

Format: `<type>(<scope>): <subject>`

**Types**:
- `feat`: Nowa funkcja
- `fix`: Naprawa błędu
- `docs`: Zmiany w dokumentacji
- `style`: Formatowanie (bez zmian w logice)
- `refactor`: Refactoring kodu
- `test`: Dodanie lub poprawienie testów
- `chore`: Maintenance (dependencies, build, etc.)

**Examples**:
```
feat(cache): Add disk-based caching for winget results
fix(winget): Handle explicit targeting for pinned packages
docs(readme): Add installation instructions for PowerShell Gallery
refactor(parallel): Extract job management to separate function
test(snapshot): Add unit tests for rollback functionality
chore(deps): Update BurntToast module to v0.8.5
```

### Code Review Checklist

**Dla autora**:
- [ ] Kod działa lokalnie i przechodzi wszystkie testy
- [ ] Dodano testy dla nowej funkcjonalności
- [ ] Dokumentacja jest aktualna (README, API docs, comments)
- [ ] CHANGELOG.md jest updated
- [ ] Commit messages są jasne i zgodne z formatem
- [ ] Branch jest rebased na latest main
- [ ] Nie ma conflict\u00f3w z main

**Dla reviewera**:
- [ ] Kod jest czytelny i dobrze skomentowany
- [ ] Logika jest poprawna i wydajna
- [ ] Nie ma oczywistych bug\u00f3w lub security issues
- [ ] Testy są kompletne i sensowne
- [ ] Dokumentacja jest jasna i dokładna
- [ ] Zmiany są zgodne z architecture projektu

---

## Narzędzia Developerskie

### Rekomendowane Extensions (VS Code)

```json
{
  "recommendations": [
    "ms-vscode.powershell",
    "tyriar.lorem-ipsum",
    "streetsidesoftware.code-spell-checker",
    "davidanson.vscode-markdownlint",
    "eamodio.gitlens"
  ]
}
```

### PowerShell Linting

```powershell
# Install PSScriptAnalyzer
Install-Module -Name PSScriptAnalyzer -Scope CurrentUser

# Run linter
Invoke-ScriptAnalyzer -Path .\src\Update-WingetAll.ps1 -Recurse

# Auto-fix issues
Invoke-ScriptAnalyzer -Path .\src\ -Recurse -Fix
```

### Pre-commit Hook

```bash
# .git/hooks/pre-commit
#!/bin/bash

# Run tests before commit
pwsh -NoProfile -Command "Invoke-Pester .\tests\unit\ -CI"

if [ $? -ne 0 ]; then
  echo "Tests failed. Commit aborted."
  exit 1
fi

# Run linter
pwsh -NoProfile -Command "Invoke-ScriptAnalyzer -Path .\src\ -Recurse"

if [ $? -ne 0 ]; then
  echo "Linter found issues. Fix them or use --no-verify to skip."
  exit 1
fi

exit 0
```

---

## Kontakt

- **Issues**: https://github.com/user/update-ultra/issues
- **Discussions**: https://github.com/user/update-ultra/discussions
- **Email**: maintainers@update-ultra.dev

---

**Wersja**: 1.0
**Ostatnia aktualizacja**: 2026-01-23
**Maintainers**: Claude Code, Tomasz
