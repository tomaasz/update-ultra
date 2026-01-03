# update-ultra v4.0

Uniwersalny skrypt do aktualizacji WSZYSTKICH środowisk deweloperskich na Windows.
Automatycznie wykrywa zainstalowane narzędzia i aktualizuje je.

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

## Funkcje v4.0
- ✨ **Automatyczne wykrywanie** - każda sekcja sprawdza czy narzędzie jest zainstalowane
- ✨ **Uniwersalność** - działa na różnych komputerach, pomija brakujące narzędzia (SKIP)
- ✨ **Ignorowanie pakietów** - możliwość wykluczenia pakietów z błędów (np. Discord auto-update)
- 🐛 **Naprawiony parser winget** - nie wyciąga już linii postępu jako pakietów
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

## Konfiguracja

Skrypt ma sekcję CONFIG na początku, gdzie możesz dostosować:
- `$WingetIgnoreIds` - pakiety do ignorowania (np. Discord.Discord)
- `$PythonVenvRootPaths` - ścieżki do virtualenvs
- `$GitRootPaths` - katalogi z repozytoriami git
- `$GoTools` - narzędzia Go do aktualizacji
- `$WSLDistros` - dystrybucje WSL do aktualizacji
- i więcej...

## Testy
Aby uruchomić testy lokalnie (np. testy sanityzacji):
```powershell
pwsh -NoProfile -File .\tests\test_sanitize.ps1
```
Testy uruchamiane są automatycznie w GitHub Actions.
