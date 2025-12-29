# update-ultra

Zestaw narzędzi do aktualizacji środowiska Windows (winget, pip, npm, choco, PS modules, VS Code extensions, Docker, Git, WSL)
z czytelnym podsumowaniem + JSON summary.

## Funkcje
- Podsumowanie tabelą (OK/FAIL/SKIP, czas, liczniki)
- Pełny log tekstowy + plik summary JSON
- Bezpieczne uruchamianie kroków (każdy krok osobno)
- Przełączniki Skip dla sekcji

## Wymagania
- Windows 11
- PowerShell 7+
- Uruchomienie jako Administrator
- Zainstalowane narzędzia (opcjonalnie, zależnie od sekcji): winget, python/py, npm, choco, code, docker, git, wsl

## Uruchomienie
```powershell
# uruchom jako Administrator
.\src\Update-WingetAll.ps1
