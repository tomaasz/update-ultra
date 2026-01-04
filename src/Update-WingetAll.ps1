<#
Update-WingetAll.ps1 — ULTRA v4.1

Nowe w v4.1:
- Rozszerzona tabela podsumowania z szczegółowymi statystykami
- Nowe kolumny: Dostępne, Zaktualizowano, Pominięto, Błędy
- Globalne podsumowanie na końcu (total available/updated/skipped/failed)
- Interaktywne pytanie przed aktualizacją WSL distros (wymaga sudo)
- Komunikaty postępu dla WSL distros podczas aktualizacji

Nowe w v4.0:
- Naprawiono parser winget (nie wyciąga już linii postępu jako pakietów)
- Dodano ignorowanie pakietów (Discord.Discord w $WingetIgnoreIds)
- Dodano 10 nowych środowisk: Scoop, pipx, Cargo, Go, Ruby, Composer, Yarn, pnpm, MS Store, WSL Distros (apt/yum)
- Wszystkie sekcje automatycznie wykrywają czy narzędzie jest zainstalowane (SKIP jeśli brak)
- Skrypt jest uniwersalny - działa na różnych komputerach

Naprawy vs v3.3:
- FIX: Winget parser nie wyciąga już linii postępu (2%, 100%, MB, etc.) jako ID pakietów
- FIX: Użycie regex do wykrywania prawdziwych ID pakietów (format Vendor.Product)
- FIX: Unary comma w zwracanych tablicach aby uniknąć rozpakowania przez PowerShell

#>

[CmdletBinding()]
param(
    [string]$LogDirectory = "$env:ProgramData\Winget-Logs",
    [switch]$IncludeUnknown = $true,
    [switch]$Force,
    [switch]$WhatIf,

    [switch]$SkipWinget,
    [switch]$SkipPip,
    [switch]$SkipNpm,
    [switch]$SkipChoco,
    [switch]$SkipPSModules,
    [switch]$SkipVSCode,
    [switch]$SkipDocker,
    [switch]$SkipGit,
    [switch]$SkipWSL,
    [switch]$SkipScoop,
    [switch]$SkipPipx,
    [switch]$SkipCargo,
    [switch]$SkipGo,
    [switch]$SkipRuby,
    [switch]$SkipComposer,
    [switch]$SkipYarn,
    [switch]$SkipPnpm,
    [switch]$SkipMSStore,
    [switch]$SkipWSLDistros
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

# --- Encoding ---
try {
    $global:OutputEncoding = [System.Text.UTF8Encoding]::new($false)
    [Console]::OutputEncoding = [System.Text.UTF8Encoding]::new($false)
    chcp 65001 | Out-Null
} catch {}

# ----------------- CONFIG -----------------
$PythonInterpreters  = @() # empty = auto
$PythonVenvRootPaths = @("C:\venv", "$env:USERPROFILE\.virtualenvs")
$PythonVenvExplicit  = @()

$WingetRetryIds = @("Notepad++.Notepad++")
$WingetIgnoreIds = @("Discord.Discord") # Packages to ignore failures (e.g., pinned packages that auto-update)

$DockerImagesToUpdate = @() # empty = update all local images

$GitRepos     = @()
$GitRootPaths = @("C:\Dev")

# Go tools to update (empty = skip)
$GoTools = @()
# Example: @("github.com/golangci/golangci-lint/cmd/golangci-lint@latest")

# WSL distros to update (empty = auto-detect running distros)
$WSLDistros = @()
# Example: @("Ubuntu", "Debian")
# -----------------------------------------

# ----------------- SAFE HELPERS -----------------
function As-Array {
    param($x)
    if ($null -eq $x) { return @() }
    return @((,$x))   # unary comma => never unroll
}
function SafeCount {
    param($x)
    if ($null -eq $x) { return 0 }
    return (As-Array $x).Count
}
function Test-CommandExists {
    param([string]$Name)
    return [bool](Get-Command $Name -ErrorAction SilentlyContinue)
}

function Sanitize-FileName {
    param([string]$Name)
    if ([string]::IsNullOrWhiteSpace($Name)) { return "unknown" }

    # 1. Replace invalid chars with _ (including control chars)
    # Invalid: \ / : * ? " < > | and range 0x00-0x1F
    $clean = $Name -replace '[\\/:*?"<>|\x00-\x1F]', '_'

    # 2. Replace whitespace with _
    $clean = $clean -replace '\s+', '_'

    # 3. Trim trailing dots/spaces/underscores
    $clean = $clean -replace '[._]+$', ''

    # 4. Collapse multiple underscores
    $clean = $clean -replace '_+', '_'

    # 5. Handle reserved names
    if ($clean -match '^(CON|PRN|AUX|NUL|COM[1-9]|LPT[1-9])$') {
        $clean = "_$clean"
    }

    # 6. Cap length (120) + hash to avoid long paths/collisions
    if ($clean.Length -gt 120) {
        $hash = 0
        foreach ($c in [char[]]$clean) { $hash = ($hash * 31 + [int]$c) % 0xFFFFFFFF }
        $clean = $clean.Substring(0, 120) + "_" + $hash.ToString("X")
    }

    return $clean
}

function Resolve-ExistingLogOrNote {
    param([string]$Path)
    if ([string]::IsNullOrWhiteSpace($Path)) { return "(no log path)" }
    if (Test-Path -LiteralPath $Path) {
        return $Path
    }
    return "(log not created – winget exited before log was written)"
}

function Write-Log {
    param(
        [string]$Message,
        [ValidateSet('INFO','WARN','ERROR')]
        [string]$Level = 'INFO'
    )
    $line = "[{0:yyyy-MM-dd HH:mm:ss}] [{1}] {2}" -f (Get-Date), $Level, $Message
    $line | Tee-Object -FilePath $script:logFile -Append | Out-Null
}

function New-StepResult {
    param([string]$Name)
    [ordered]@{
        Name      = $Name
        Status    = "PENDING"  # OK/FAIL/SKIP
        Start     = Get-Date
        End       = $null
        DurationS = $null
        ExitCode  = 0
        Notes     = New-Object System.Collections.Generic.List[string]
        Actions   = New-Object System.Collections.Generic.List[string]
        Failures  = New-Object System.Collections.Generic.List[string]
        Counts    = [ordered]@{
            Installed = 0  # Wszystkie zainstalowane pakiety w środowisku
            Available = 0  # Dostępne aktualizacje (wykryte przed update)
            Updated   = 0  # Zaktualizowane pomyślnie
            Skipped   = 0  # Pominięte (ignorowane, user skip, etc.)
            Failed    = 0  # Błędy aktualizacji
            # Legacy dla kompatybilności:
            Ok        = 0
            Fail      = 0
            Total     = 0
        }
        Artifacts = [ordered]@{ }
    }
}

function Finish-StepResult {
    param($R, [string]$Status, [int]$ExitCode = 0)
    $R.End = Get-Date
    $R.DurationS = [math]::Round((New-TimeSpan -Start $R.Start -End $R.End).TotalSeconds, 1)
    $R.Status = $Status
    $R.ExitCode = $ExitCode
    return $R
}

function Invoke-Step {
    param(
        [string]$Name,
        [scriptblock]$Body,
        [switch]$Skip
    )

    $r = New-StepResult -Name $Name

    # Display progress header
    Write-Host "`n[$Name] " -NoNewline -ForegroundColor Cyan
    Write-Host "Rozpoczynam..." -ForegroundColor Gray

    if ($Skip) {
        Write-Host "[$Name] " -NoNewline -ForegroundColor Yellow
        Write-Host "POMINIĘTO (Skip)" -ForegroundColor Yellow
        $r.Notes.Add("Pominięte przełącznikiem Skip.")
        return (Finish-StepResult -R $r -Status "SKIP" -ExitCode 0)
    }

    try {
        & $Body $r
        if ($r.Status -eq "PENDING") {
            $finished = Finish-StepResult -R $r -Status "OK" -ExitCode 0
            Write-Host "[$Name] " -NoNewline -ForegroundColor Green
            Write-Host "✓ OK ($($finished.DurationS)s)" -ForegroundColor Green
            return $finished
        }
        $finished = Finish-StepResult -R $r -Status $r.Status -ExitCode ($r.ExitCode ?? 0)

        # Display completion status
        if ($finished.Status -eq "OK") {
            Write-Host "[$Name] " -NoNewline -ForegroundColor Green
            Write-Host "✓ OK ($($finished.DurationS)s)" -ForegroundColor Green
        } elseif ($finished.Status -eq "SKIP") {
            Write-Host "[$Name] " -NoNewline -ForegroundColor Yellow
            Write-Host "⊘ SKIP ($($finished.DurationS)s)" -ForegroundColor Yellow
        } elseif ($finished.Status -eq "FAIL") {
            Write-Host "[$Name] " -NoNewline -ForegroundColor Red
            Write-Host "✗ FAIL ($($finished.DurationS)s)" -ForegroundColor Red
        }

        return $finished
    } catch {
        $msg = $_.Exception.Message
        $ln = $null
        $line = $null
        $pos = $null
        try {
            $ln   = $_.InvocationInfo.ScriptLineNumber
            $line = $_.InvocationInfo.Line
            $pos  = $_.InvocationInfo.PositionMessage
        } catch {}

        $r.Failures.Add("Wyjątek: $msg")
        if ($ln)   { $r.Failures.Add("Linia: $ln") }
        if ($line) { $r.Failures.Add("Kod: $line") }

        Write-Log "[$Name] WYJĄTEK: $msg" "ERROR"
        if ($ln)   { Write-Log "[$Name] LINIA: $ln" "ERROR" }
        if ($line) { Write-Log "[$Name] KOD: $line" "ERROR" }
        if ($pos)  { Write-Log "[$Name] POS: $pos" "ERROR" }

        return (Finish-StepResult -R $r -Status "FAIL" -ExitCode 1)
    }
}

function Try-Run {
    param(
        [scriptblock]$Body,
        [ref]$OutputLines
    )
    $OutputLines.Value = @()
    try {
        $OutputLines.Value = @(& $Body 2>&1)
        return $LASTEXITCODE
    } catch {
        $OutputLines.Value = @("EXCEPTION: $($_.Exception.Message)")
        return 1
    }
}

# ------- Winget parsing helpers -------
function Parse-WingetUpgradeList {
    param([string[]]$Lines)

    $items = New-Object System.Collections.Generic.List[object]

    foreach ($raw in (As-Array $Lines)) {
        $l = [string]$raw
        if ([string]::IsNullOrWhiteSpace($l)) { continue }

        if ($l -match '^\s*Name\b') { continue }
        if ($l -match '^\s*-+\s*$') { continue }
        if ($l -match '^\s*\d+\s+upgrades?\b') { continue }
        if ($l -match 'No installed package') { continue }
        if ($l -match 'require explicit targeting') { continue }

        $parts = @($l -split '\s{2,}' | Where-Object { $_ -ne "" })

        if ($parts.Count -ge 5) {
            $items.Add([pscustomobject]@{
                Name      = $parts[0]
                Id        = $parts[1]
                Version   = $parts[2]
                Available = $parts[3]
                Source    = $parts[4]
            }) | Out-Null
        }
    }

    return $items.ToArray()
}

function Get-WingetExplicitTargetIds {
    param([string[]]$Lines)

    $ids = New-Object System.Collections.Generic.List[string]
    $inTable = $false
    $tableStarted = $false

    foreach ($raw in (As-Array $Lines)) {
        $l = [string]$raw

        if ($l -match 'require explicit targeting') { $inTable = $true; continue }
        if (-not $inTable) { continue }

        # Skip header and separator
        if ($l -match '^\s*Name\s+Id\s+Version') { continue }
        if ($l -match '^\s*-+\s*$') { $tableStarted = $true; continue }

        # Stop parsing when we hit a blank line AFTER table started, or found/downloading lines
        if ($tableStarted) {
            if ([string]::IsNullOrWhiteSpace($l)) { break }
            if ($l -match '^\s*\(?\d+/\d+\)?\s*(Found|Downloading)') { break }
        }

        # Skip blank lines before table starts
        if ([string]::IsNullOrWhiteSpace($l)) { continue }

        # Parse table rows: Name Id Version Available Source
        # Use regex to extract ID - typically in format Vendor.Product or similar
        # Match pattern: some text, then a word with dots (ID), then version numbers
        if ($l -match '\s+([A-Za-z0-9][A-Za-z0-9._\-]+?)\s+[\d\.]+\s+[\d\.]+\s+\w+\s*$') {
            $id = $Matches[1].Trim()
            if (-not [string]::IsNullOrWhiteSpace($id)) {
                $ids.Add($id) | Out-Null
            }
        }
    }

    # Ensure we always return an array (use unary comma to prevent PowerShell from unrolling single-item arrays)
    $result = @($ids.ToArray() | Select-Object -Unique)
    return ,$result
}

function Get-WingetRunningBlockers {
    param([string[]]$Lines)

    $blockers = New-Object System.Collections.Generic.List[object]
    $lastFound = $null

    foreach ($raw in (As-Array $Lines)) {
        $l = [string]$raw

        if ($l -match 'Found\s+(.+?)\s+\[(.+?)\]') {
            $lastFound = [pscustomobject]@{ Name=$Matches[1].Trim(); Id=$Matches[2].Trim() }
        }
        if ($l -match 'Application is currently running') {
            if ($null -ne $lastFound) { $blockers.Add($lastFound) | Out-Null }
        }
    }

    return @($blockers | Select-Object -Unique -Property Id)
}

# ------- Python target discovery -------
function Get-PythonTargets {
    param(
        [string[]]$InterpretersConfig,
        [string[]]$VenvRootPaths,
        [string[]]$VenvExplicit
    )

    $targets = New-Object System.Collections.Generic.List[string]

    if (SafeCount $InterpretersConfig -gt 0) {
        foreach ($name in (As-Array $InterpretersConfig)) {
            if (Test-CommandExists $name) { $targets.Add($name) | Out-Null }
        }
    } else {
        if (Test-CommandExists "py") {
            Write-Log "Auto-wykrywanie interpreterów Pythona przez 'py -0p'..."
            try {
                $pyList = @((py -0p) 2>&1)
                foreach ($line in $pyList) {
                    if ($line -match '^\s*\S+\s+(.+\.exe)\s*$') {
                        $path = $Matches[1]
                        if (Test-Path $path) { $targets.Add($path) | Out-Null }
                    }
                }
            } catch {
                Write-Log "Błąd 'py -0p': $($_.Exception.Message)" "WARN"
            }
        }

        foreach ($name in @("python","python3")) {
            if (Test-CommandExists $name) {
                try {
                    & $name --version *> $null
                    if ($LASTEXITCODE -eq 0) {
                        $targets.Add($name) | Out-Null
                    }
                } catch {
                    # Ignorujemy błędy uruchamiania (np. alias do Store, brak faktycznego pliku)
                }
            }
        }
    }

    foreach ($root in (As-Array $VenvRootPaths)) {
        if (-not (Test-Path $root)) {
            Write-Log "Katalog venv root '$root' nie istnieje – pomijam." "WARN"
            continue
        }
        try {
            Get-ChildItem -Path $root -Directory -Recurse -Depth 3 -ErrorAction SilentlyContinue |
                ForEach-Object {
                    $pyPath = Join-Path $_.FullName "Scripts\python.exe"
                    if (Test-Path $pyPath) { $targets.Add($pyPath) | Out-Null }
                }
        } catch {
            Write-Log "Błąd skanowania venv root '$root': $($_.Exception.Message)" "WARN"
        }
    }

    foreach ($venv in (As-Array $VenvExplicit)) {
        if (Test-Path $venv) { $targets.Add($venv) | Out-Null }
    }

    return @($targets | Select-Object -Unique)
}

# ----------------- ADMIN CHECK -----------------
$identity  = [Security.Principal.WindowsIdentity]::GetCurrent()
$principal = New-Object Security.Principal.WindowsPrincipal($identity)
if (-not $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    Write-Warning "Ten skrypt musi być uruchomiony jako Administrator."
    return
}

# ----------------- LOG START -----------------
if (-not (Test-Path -LiteralPath $LogDirectory)) {
    New-Item -ItemType Directory -Path $LogDirectory -Force | Out-Null
}
$timestamp = Get-Date -Format "yyyyMMdd_HHmmss"
$script:logFile = Join-Path $LogDirectory "dev_update_$timestamp.log"

# Display startup banner
Write-Host ""
Write-Host "╔════════════════════════════════════════════════╗" -ForegroundColor Cyan
Write-Host "║  UPDATE-ULTRA v4.1 - Uniwersalny Updater      ║" -ForegroundColor Cyan
Write-Host "╚════════════════════════════════════════════════╝" -ForegroundColor Cyan
Write-Host ""
Write-Host "Rozpoczynam aktualizację wszystkich środowisk..." -ForegroundColor White
Write-Host "Log: " -NoNewline -ForegroundColor Gray
Write-Host $script:logFile -ForegroundColor Yellow
Write-Host ""

Write-Log "===== START UPDATE (ULTRA v4.1) ====="
Write-Log "Log: $script:logFile"
Write-Log "WhatIf: $WhatIf, Force: $Force, IncludeUnknown: $IncludeUnknown"

$Results = New-Object System.Collections.Generic.List[object]

# ----------------- STEPS -----------------

# 1) WINGET
$Results.Add((Invoke-Step -Name "Winget" -Skip:$SkipWinget -Body {
    param($r)

    if (-not (Test-CommandExists "winget")) {
        $r.Status = "SKIP"
        $r.Notes.Add("winget nie jest dostępny w PATH.")
        return
    }

    Write-Log "winget --version:"
    try { @((winget --version) 2>&1) | ForEach-Object { Write-Log $_ } } catch {}

    Write-Log "winget source list:"
    try { @((winget source list) 2>&1) | ForEach-Object { Write-Log $_ } } catch {}

    Write-Log "winget pin list:"
    try { @((winget pin list) 2>&1) | ForEach-Object { Write-Log $_ } } catch {}

    Write-Host "  Sprawdzam dostępne aktualizacje..." -ForegroundColor Gray
    Write-Log "LIST PRZED: winget upgrade"
    $beforeRaw = @()
    [void](Try-Run -Body { winget upgrade } -OutputLines ([ref]$beforeRaw))

    $beforeItems = @(Parse-WingetUpgradeList -Lines $beforeRaw)
    $explicitIdsBefore = @(Get-WingetExplicitTargetIds -Lines $beforeRaw)

    # Statystyki
    $r.Counts.Available = $beforeItems.Count + $explicitIdsBefore.Count

    Write-Host "  Znaleziono: $($beforeItems.Count) pakietów do aktualizacji" -ForegroundColor Cyan
    if ($explicitIdsBefore.Count -gt 0) {
        Write-Host "  Explicit targeting: $($explicitIdsBefore.Count) pakietów" -ForegroundColor Yellow
    }

    $r.Actions.Add("Do aktualizacji (przed): $($beforeItems.Count)")
    if ($explicitIdsBefore.Count -gt 0) {
        $r.Actions.Add("Require explicit targeting (przed): $($explicitIdsBefore.Count) -> " + ($explicitIdsBefore -join ", "))
    }

    if ($WhatIf) {
        $r.Actions.Add("[WHATIF] winget source update")
    } else {
        Write-Host "  Aktualizuję źródła winget..." -ForegroundColor Gray
        Write-Log "winget source update..."
        @((winget source update) 2>&1) | ForEach-Object { Write-Log $_ }
    }

    if ($WhatIf) {
        $r.Actions.Add("[WHATIF] winget upgrade --id Microsoft.AppInstaller -e")
    } else {
        Write-Host "  Aktualizuję App Installer..." -ForegroundColor Gray
        Write-Log "Aktualizacja App Installer..."
        $aiLog = Join-Path $LogDirectory ("winget_AppInstaller_{0}.log" -f (Get-Date -Format "yyyyMMdd_HHmmss"))

        $aiArgs = @(
            "upgrade","--id","Microsoft.AppInstaller","-e",
            "--accept-source-agreements","--accept-package-agreements",
            "--disable-interactivity","--verbose-logs","-o",$aiLog
        )
        if ($Force) { $aiArgs += "--force" }

        $aiOut = @(& winget @aiArgs 2>&1)
        $aiEc  = $LASTEXITCODE
        $aiOut | ForEach-Object { Write-Log $_ }
        Write-Log "ExitCode AppInstaller: $aiEc"

        $r.Artifacts["winget_appinstaller_log"] = Resolve-ExistingLogOrNote -Path $aiLog

        if ($aiOut -match 'No available upgrade found') {
            $r.Notes.Add("AppInstaller: brak nowszej wersji (OK).")
        } elseif ($aiEc -ne 0) {
            $r.Notes.Add("AppInstaller: exitCode=$aiEc (log: $aiLog)")
        }
    }

    $wingetAllLog = Join-Path $LogDirectory ("winget_all_{0}.log" -f (Get-Date -Format "yyyyMMdd_HHmmss"))

    $upgradeArgs = @(
        "upgrade","--all",
        "--accept-source-agreements","--accept-package-agreements",
        "--disable-interactivity"
    )
    if ($IncludeUnknown) { $upgradeArgs += "--include-unknown" }
    if ($Force)          { $upgradeArgs += "--force" }

    $lines = @()
    if ($WhatIf) {
        $r.Actions.Add("[WHATIF] winget " + ($upgradeArgs -join " "))
        return
    }

    Write-Host "  Uruchamiam winget upgrade --all..." -ForegroundColor Gray
    Write-Host "  (To może potrwać kilka minut...)" -ForegroundColor DarkGray
    Write-Log "winget $($upgradeArgs -join ' ')"
    $ecAll = Try-Run -Body { winget @upgradeArgs 2>&1 | Tee-Object -FilePath $wingetAllLog } -OutputLines ([ref]$lines)
    $r.ExitCode = $ecAll
    @($lines) | ForEach-Object { Write-Log $_ }

    $r.Artifacts["winget_all_log"] = Resolve-ExistingLogOrNote -Path $wingetAllLog

    if ($ecAll -ne 0) {
        try {
            Write-Log "winget error $ecAll (dekodowanie):"
            @((winget error --input "$ecAll") 2>&1) | ForEach-Object { Write-Log $_ } | Out-Null
        } catch {}
    }

    $explicitIds = @(Get-WingetExplicitTargetIds -Lines $lines)
    if ($explicitIds.Count -gt 0) {
        Write-Host "  Znaleziono $($explicitIds.Count) pakietów wymagających explicit targeting" -ForegroundColor Yellow
        $r.Notes.Add("Require explicit targeting: " + ($explicitIds -join ", "))
    }

    $blockers = @(Get-WingetRunningBlockers -Lines $lines)
    if ($blockers.Count -gt 0) {
        foreach ($b in $blockers) {
            $r.Failures.Add("Aplikacja uruchomiona: $($b.Name) [$($b.Id)] — zamknij i uruchom ponownie.")
        }
    }

    foreach ($id in $explicitIds) {
        $cleanId = Sanitize-FileName $id
        $singleLog = Join-Path $LogDirectory ("winget_explicit_{0}_{1}.log" -f $cleanId, (Get-Date -Format "yyyyMMdd_HHmmss"))

        $args = @(
            "upgrade","--id",$id,"-e",
            "--accept-source-agreements","--accept-package-agreements",
            "--disable-interactivity","--verbose-logs","-o",$singleLog
        )
        if ($Force) { $args += "--force" }

        if ($WhatIf) {
            $r.Actions.Add("[WHATIF] EXPLICIT: winget $($args -join ' ')")
            continue
        }

        Write-Host "  Aktualizuję explicit: $id..." -ForegroundColor Gray
        Write-Log "EXPLICIT: winget $($args -join ' ')"
        $outX = @(& winget @args 2>&1)
        $ecX  = $LASTEXITCODE
        $outX | ForEach-Object { Write-Log $_ }

        $r.Artifacts["winget_explicit_$($cleanId)"] = Resolve-ExistingLogOrNote -Path $singleLog

        $isIgnored = $WingetIgnoreIds -contains $id

        $r.Counts.Total++
        if ($ecX -eq 0) {
            $r.Counts.Ok++
            $r.Counts.Updated++
            Write-Host "    ✓ $id" -ForegroundColor Green
            $r.Actions.Add("EXPLICIT OK: $id")
        }
        else {
            if ($isIgnored) {
                # Don't count ignored packages as failures
                $r.Counts.Skipped++
                Write-Host "    ⊘ $id (ignorowany)" -ForegroundColor Yellow
                $r.Notes.Add("EXPLICIT IGNORED: $id (exitCode=$ecX, package is in ignore list)")
                Write-Log "EXPLICIT IGNORED: $id (exitCode=$ecX, in ignore list)" "WARN"
            } else {
                $r.Counts.Fail++
                $r.Counts.Failed++
                Write-Host "    ✗ $id (błąd: $ecX)" -ForegroundColor Red
                $r.Failures.Add("EXPLICIT FAIL: $id (exitCode=$ecX) log=$(Resolve-ExistingLogOrNote -Path $singleLog)")
                # Policy: First non-zero exit code determines the section result.
                if ($r.ExitCode -eq 0) { $r.ExitCode = $ecX }
            }
        }
    }

    foreach ($id in $WingetRetryIds) {
        $shouldRetry = $false
        if ($beforeItems | Where-Object { $_.Id -eq $id }) { $shouldRetry = $true }
        if ($blockers   | Where-Object { $_.Id -eq $id }) { $shouldRetry = $true }
        if (-not $shouldRetry) { continue }

        $cleanId = Sanitize-FileName $id
        $retryLog = Join-Path $LogDirectory ("winget_retry_{0}_{1}.log" -f $cleanId, (Get-Date -Format "yyyyMMdd_HHmmss"))

        $retryArgs = @(
            "upgrade","--id",$id,"-e",
            "--accept-source-agreements","--accept-package-agreements",
            "--disable-interactivity","--verbose-logs","-o",$retryLog
        )
        if ($Force) { $retryArgs += "--force" }

        if ($WhatIf) {
            $r.Actions.Add("[WHATIF] RETRY: winget $($retryArgs -join ' ')")
            continue
        }

        Write-Log "RETRY: winget $($retryArgs -join ' ')"
        $outR = @(& winget @retryArgs 2>&1)
        $ecR  = $LASTEXITCODE
        $outR | ForEach-Object { Write-Log $_ }

        $r.Artifacts["winget_retry_$($cleanId)"] = Resolve-ExistingLogOrNote -Path $retryLog

        $isIgnored = $WingetIgnoreIds -contains $id

        $r.Counts.Total++
        if ($ecR -eq 0) {
            $r.Counts.Ok++
            $r.Counts.Updated++
            $r.Actions.Add("RETRY OK: $id")
        }
        else {
            if ($isIgnored) {
                # Don't count ignored packages as failures
                $r.Counts.Skipped++
                $r.Notes.Add("RETRY IGNORED: $id (exitCode=$ecR, package is in ignore list)")
                Write-Log "RETRY IGNORED: $id (exitCode=$ecR, in ignore list)" "WARN"
            } else {
                $r.Counts.Fail++
                $r.Counts.Failed++
                $r.Failures.Add("RETRY FAIL: $id (exitCode=$ecR) log=$(Resolve-ExistingLogOrNote -Path $retryLog)")
                if ($r.ExitCode -eq 0) { $r.ExitCode = $ecR }
            }
        }
    }

    Write-Log "LIST PO: winget upgrade"
    $afterRaw = @()
    [void](Try-Run -Body { winget upgrade } -OutputLines ([ref]$afterRaw))
    $afterItems = @(Parse-WingetUpgradeList -Lines $afterRaw)
    $explicitIdsAfter = @(Get-WingetExplicitTargetIds -Lines $afterRaw)

    $r.Actions.Add("Pozostało do aktualizacji (po): $($afterItems.Count)")
    if ($explicitIdsAfter.Count -gt 0) {
        $r.Actions.Add("Require explicit targeting (po): $($explicitIdsAfter.Count) -> " + ($explicitIdsAfter -join ", "))
    }

    $hasFailures = ($r.Failures.Count -gt 0) -or ($r.Counts.Fail -gt 0)
    if ($hasFailures -or $ecAll -ne 0) {
        $r.Status = "FAIL"
        if ($ecAll -ne 0) { $r.Failures.Add("winget upgrade --all exitCode=$ecAll (log: $wingetAllLog)") }
    } else {
        $r.Status = "OK"
    }
}))

# 2) PYTHON/PIP
$Results.Add((Invoke-Step -Name "Python/Pip" -Skip:$SkipPip -Body {
    param($r)

    $targets = @(Get-PythonTargets -InterpretersConfig $PythonInterpreters `
                                 -VenvRootPaths $PythonVenvRootPaths `
                                 -VenvExplicit  $PythonVenvExplicit)

    if ($targets.Count -eq 0) {
        $r.Status = "SKIP"
        $r.Notes.Add("Nie znaleziono działających interpreterów/venvów.")
        return
    }

    $r.Actions.Add("Targets: $($targets.Count)")

    foreach ($t in $targets) {
        Write-Log ">>> Python target: $t"
        if ($WhatIf) { $r.Actions.Add("[WHATIF] pip upgrade dla: $t"); continue }

        try {
            Write-Log "pip upgrade: $t -m pip install --upgrade pip"
            @(& $t -m pip install --upgrade pip 2>&1) | ForEach-Object { Write-Log $_ }
        } catch {
            $r.Counts.Total++; $r.Counts.Fail++
            $r.Failures.Add("pip self-upgrade FAIL: $t :: $($_.Exception.Message)")
            continue
        }

        $outdated = @()
        [void](Try-Run -Body { & $t -m pip list --outdated --format=json } -OutputLines ([ref]$outdated))
        $joined = (($outdated -join "`n").Trim())

        if (-not $joined -or -not $joined.StartsWith("[")) {
            $r.Notes.Add("Brak outdated lub nieczytelny format: $t")
            continue
        }

        $pkgs = @()
        try { $pkgs = @($joined | ConvertFrom-Json) } catch { $pkgs = @() }

        if ($pkgs.Count -eq 0) {
            $r.Notes.Add("Brak paczek do aktualizacji: $t")
            continue
        }

        $r.Actions.Add("pip outdated: $($pkgs.Count) ($t)")
        $r.Counts.Available += $pkgs.Count

        foreach ($p in $pkgs) {
            $r.Counts.Total++
            try {
                Write-Log "pip upgrade pkg: $($p.name) ($t)"
                @(& $t -m pip install --upgrade $p.name 2>&1) | ForEach-Object { Write-Log $_ }
                $r.Counts.Ok++
                $r.Counts.Updated++
            } catch {
                $r.Counts.Fail++
                $r.Counts.Failed++
                $r.Failures.Add("pip upgrade FAIL: $($p.name) ($t) :: $($_.Exception.Message)")
            }
        }
    }

    if ($r.Counts.Fail -gt 0) { $r.Status="FAIL"; $r.ExitCode=1 }
}))

# 3) NPM
$Results.Add((Invoke-Step -Name "npm (global)" -Skip:$SkipNpm -Body {
    param($r)
    if (-not (Test-CommandExists "npm")) { $r.Status="SKIP"; $r.Notes.Add("npm brak w PATH."); return }
    if ($WhatIf) { $r.Actions.Add("[WHATIF] npm -g update"); return }
    Write-Log "npm -g update..."
    @((npm -g update) 2>&1) | ForEach-Object { Write-Log $_ }
}))

# 4) CHOCO
$Results.Add((Invoke-Step -Name "Chocolatey" -Skip:$SkipChoco -Body {
    param($r)
    if (-not (Test-CommandExists "choco")) { $r.Status="SKIP"; $r.Notes.Add("choco brak w PATH."); return }
    if ($WhatIf) { $r.Actions.Add("[WHATIF] choco upgrade all -y"); return }
    Write-Log "choco upgrade all -y..."
    $out = @((choco upgrade all -y) 2>&1)
    $ec  = $LASTEXITCODE
    $out | ForEach-Object { Write-Log $_ }
    $r.ExitCode = $ec
    if ($ec -ne 0) { $r.Status="FAIL"; $r.ExitCode=1; $r.Failures.Add("choco exitCode=$ec") }
}))

# 5) PS MODULES
$Results.Add((Invoke-Step -Name "PowerShell Modules" -Skip:$SkipPSModules -Body {
    param($r)
    if (-not (Test-CommandExists "Get-InstalledModule") -or -not (Test-CommandExists "Update-Module")) {
        $r.Status="SKIP"; $r.Notes.Add("Brak PowerShellGet (Get-InstalledModule/Update-Module)."); return
    }
    if ($WhatIf) { $r.Actions.Add("[WHATIF] Update-Module (all)"); return }

    $mods = @(Get-InstalledModule -ErrorAction SilentlyContinue | Where-Object Name -ne 'Microsoft.WinGet.Client')
    if ($mods.Count -eq 0) { $r.Notes.Add("Brak modułów do aktualizacji."); return }

    $r.Actions.Add("Moduły: $($mods.Count)")
    $r.Counts.Available = $mods.Count

    foreach ($m in $mods) {
        $r.Counts.Total++
        try {
            Write-Log "Update-Module: $($m.Name)"
            Update-Module -Name $m.Name -Force -ErrorAction Continue 2>&1 | ForEach-Object { Write-Log $_ }
            $r.Counts.Ok++
            $r.Counts.Updated++
        } catch {
            $r.Counts.Fail++
            $r.Counts.Failed++
            $r.Failures.Add("Update-Module FAIL: $($m.Name) :: $($_.Exception.Message)")
        }
    }
    if ($r.Counts.Fail -gt 0) { $r.Status="FAIL"; $r.ExitCode=1 }
}))

# 6) VS CODE
$Results.Add((Invoke-Step -Name "VS Code Extensions" -Skip:$SkipVSCode -Body {
    param($r)
    if (-not (Test-CommandExists "code")) { $r.Status="SKIP"; $r.Notes.Add("code brak w PATH."); return }
    if ($WhatIf) { $r.Actions.Add("[WHATIF] update extensions"); return }

    $ext = @((code --list-extensions) 2>&1) | Where-Object { -not [string]::IsNullOrWhiteSpace($_) }
    $r.Actions.Add("Extensions: $($ext.Count)")
    $r.Counts.Available = $ext.Count

    foreach ($e in $ext) {
        $r.Counts.Total++
        try {
            Write-Log "VSCode ext --force: $e"
            @((code --install-extension $e --force) 2>&1) | ForEach-Object { Write-Log $_ }
            $r.Counts.Ok++
            $r.Counts.Updated++
        } catch {
            $r.Counts.Fail++
            $r.Counts.Failed++
            $r.Failures.Add("VSCode ext FAIL: $e :: $($_.Exception.Message)")
        }
    }
    if ($r.Counts.Fail -gt 0) { $r.Status="FAIL"; $r.ExitCode=1 }
}))

# 7) DOCKER
$Results.Add((Invoke-Step -Name "Docker Images" -Skip:$SkipDocker -Body {
    param($r)
    if (-not (Test-CommandExists "docker")) { $r.Status="SKIP"; $r.Notes.Add("docker brak w PATH."); return }
    if ($WhatIf) { $r.Actions.Add("[WHATIF] docker pull ..."); return }

    $outInfo = @()
    $ecInfo = Try-Run -Body { docker info } -OutputLines ([ref]$outInfo)
    if ($ecInfo -ne 0) {
        $r.Status = "SKIP"
        $r.Notes.Add("Docker daemon nie działa — pomijam (docker info exitCode=$ecInfo).")
        return
    }

    $images = @()

    if ($DockerImagesToUpdate.Count -gt 0) {
        $images = @($DockerImagesToUpdate)
    } else {
        $outList = @()
        $ecList  = Try-Run -Body { docker image ls --format '{{.Repository}}:{{.Tag}}' } -OutputLines ([ref]$outList)
        if ($ecList -ne 0) {
            $r.Status = "SKIP"
            $r.Notes.Add("Nie da się pobrać listy obrazów (docker image ls exitCode=$ecList) — pomijam.")
            return
        }
        $images = @($outList)
    }

    $images = @(
        $images |
        Where-Object { $_ -and ($_ -is [string]) } |
        ForEach-Object { $_.Trim() } |
        Where-Object {
            $_ -and $_ -ne "<none>:<none>" -and
            ($_ -match '^[a-z0-9][a-z0-9._/\-]*:[a-z0-9][a-z0-9._\-]*$')
        } |
        Select-Object -Unique
    )

    if ($images.Count -eq 0) { $r.Notes.Add("Brak obrazów do aktualizacji (albo nie spełniają formatu repo:tag)."); return }

    $r.Actions.Add("Images: $($images.Count)")
    foreach ($img in $images) {
        $r.Counts.Total++
        $outPull = @()
        $ecPull  = Try-Run -Body { docker pull $img } -OutputLines ([ref]$outPull)
        $outPull | ForEach-Object { Write-Log $_ }

        if ($ecPull -eq 0) { $r.Counts.Ok++ }
        else {
            $r.Counts.Fail++
            $r.Failures.Add("docker pull FAIL: $img (exitCode=$ecPull)")
        }
    }

    if ($r.Counts.Fail -gt 0) { $r.Status="FAIL"; $r.ExitCode=1 }
}))

# 8) GIT
$Results.Add((Invoke-Step -Name "Git Repos" -Skip:$SkipGit -Body {
    param($r)
    if (-not (Test-CommandExists "git")) { $r.Status="SKIP"; $r.Notes.Add("git brak w PATH."); return }

    $repos = @()
    if ($GitRepos.Count -gt 0) { $repos += @($GitRepos) }

    foreach ($root in $GitRootPaths) {
        if (-not (Test-Path $root)) {
            Write-Log "Git root '$root' nie istnieje – pomijam." "WARN"
            continue
        }
        try {
            $found = Get-ChildItem -Path $root -Directory -Recurse -Depth 4 -ErrorAction SilentlyContinue |
                Where-Object { Test-Path (Join-Path $_.FullName ".git") } |
                ForEach-Object { $_.FullName }
            $repos += @($found)
        } catch {}
    }

    $repos = @($repos | Select-Object -Unique)
    if ($repos.Count -eq 0) { $r.Status="SKIP"; $r.Notes.Add("Nie znaleziono repozytoriów."); return }

    if ($WhatIf) { $r.Actions.Add("[WHATIF] git pull (repos: $($repos.Count))"); return }

    $r.Actions.Add("Repos: $($repos.Count)")
    $r.Counts.Available = $repos.Count

    foreach ($repo in $repos) {
        $r.Counts.Total++
        Push-Location $repo
        try {
            Write-Log "git pull ($repo)"
            $outPull = @()
            $ecPull = Try-Run -Body { git pull } -OutputLines ([ref]$outPull)
            $outPull | ForEach-Object { Write-Log $_ }
            if ($ecPull -eq 0) { $r.Counts.Ok++; $r.Counts.Updated++ }
            else { $r.Counts.Fail++; $r.Counts.Failed++; $r.Failures.Add("git pull FAIL: $repo (exitCode=$ecPull)") }
        } finally {
            Pop-Location
        }
    }
    if ($r.Counts.Fail -gt 0) { $r.Status="FAIL"; $r.ExitCode=1 }
}))

# 9) WSL
$Results.Add((Invoke-Step -Name "WSL" -Skip:$SkipWSL -Body {
    param($r)
    if (-not (Test-CommandExists "wsl")) { $r.Status="SKIP"; $r.Notes.Add("wsl brak."); return }
    if ($WhatIf) { $r.Actions.Add("[WHATIF] wsl --update"); return }

    Write-Log "wsl --update..."
    $out = @()
    $ec  = Try-Run -Body { wsl --update } -OutputLines ([ref]$out)
    $out | ForEach-Object { Write-Log $_ }
    $r.ExitCode = $ec
    if ($ec -ne 0) { $r.Status="FAIL"; $r.ExitCode=1; $r.Failures.Add("wsl --update exitCode=$ec") }
}))

# 10) SCOOP
$Results.Add((Invoke-Step -Name "Scoop" -Skip:$SkipScoop -Body {
    param($r)
    if (-not (Test-CommandExists "scoop")) { $r.Status="SKIP"; $r.Notes.Add("scoop brak w PATH."); return }
    if ($WhatIf) { $r.Actions.Add("[WHATIF] scoop update *"); return }

    Write-Log "scoop update..."
    $out = @()
    $ec = Try-Run -Body { scoop update } -OutputLines ([ref]$out)
    $out | ForEach-Object { Write-Log $_ }

    Write-Log "scoop update *..."
    $out2 = @()
    $ec2 = Try-Run -Body { scoop update * } -OutputLines ([ref]$out2)
    $out2 | ForEach-Object { Write-Log $_ }

    $r.ExitCode = if ($ec -ne 0) { $ec } else { $ec2 }
    if ($r.ExitCode -ne 0) { $r.Status="FAIL"; $r.Failures.Add("scoop update exitCode=$($r.ExitCode)") }
}))

# 11) PIPX
$Results.Add((Invoke-Step -Name "pipx" -Skip:$SkipPipx -Body {
    param($r)
    if (-not (Test-CommandExists "pipx")) { $r.Status="SKIP"; $r.Notes.Add("pipx brak w PATH."); return }
    if ($WhatIf) { $r.Actions.Add("[WHATIF] pipx upgrade-all"); return }

    Write-Log "pipx upgrade-all..."
    $out = @()
    $ec = Try-Run -Body { pipx upgrade-all } -OutputLines ([ref]$out)
    $out | ForEach-Object { Write-Log $_ }
    $r.ExitCode = $ec
    if ($ec -ne 0) { $r.Status="FAIL"; $r.ExitCode=1; $r.Failures.Add("pipx upgrade-all exitCode=$ec") }
}))

# 12) CARGO (Rust)
$Results.Add((Invoke-Step -Name "Cargo (Rust)" -Skip:$SkipCargo -Body {
    param($r)
    if (-not (Test-CommandExists "cargo")) { $r.Status="SKIP"; $r.Notes.Add("cargo brak w PATH."); return }

    # Check if cargo-update is installed
    $hasCargoUpdate = $false
    try {
        $checkOut = @((cargo install --list) 2>&1)
        if ($checkOut -match 'cargo-update') { $hasCargoUpdate = $true }
    } catch {}

    if (-not $hasCargoUpdate) {
        $r.Status="SKIP"
        $r.Notes.Add("cargo-update nie jest zainstalowany. Zainstaluj: cargo install cargo-update")
        return
    }

    if ($WhatIf) { $r.Actions.Add("[WHATIF] cargo install-update -a"); return }

    Write-Log "cargo install-update -a..."
    $out = @()
    $ec = Try-Run -Body { cargo install-update -a } -OutputLines ([ref]$out)
    $out | ForEach-Object { Write-Log $_ }
    $r.ExitCode = $ec
    if ($ec -ne 0) { $r.Status="FAIL"; $r.ExitCode=1; $r.Failures.Add("cargo install-update exitCode=$ec") }
}))

# 13) GO TOOLS
$Results.Add((Invoke-Step -Name "Go Tools" -Skip:$SkipGo -Body {
    param($r)
    if (-not (Test-CommandExists "go")) { $r.Status="SKIP"; $r.Notes.Add("go brak w PATH."); return }

    if ($GoTools.Count -eq 0) {
        $r.Status="SKIP"
        $r.Notes.Add("Brak skonfigurowanych narzędzi Go (zmienna `$GoTools pusta).")
        return
    }

    if ($WhatIf) { $r.Actions.Add("[WHATIF] go install dla $($GoTools.Count) narzędzi"); return }

    $r.Actions.Add("Go tools: $($GoTools.Count)")
    foreach ($tool in $GoTools) {
        $r.Counts.Total++
        try {
            Write-Log "go install $tool"
            @((go install $tool) 2>&1) | ForEach-Object { Write-Log $_ }
            if ($LASTEXITCODE -eq 0) { $r.Counts.Ok++ }
            else { $r.Counts.Fail++; $r.Failures.Add("go install FAIL: $tool (exitCode=$LASTEXITCODE)") }
        } catch {
            $r.Counts.Fail++
            $r.Failures.Add("go install FAIL: $tool :: $($_.Exception.Message)")
        }
    }
    if ($r.Counts.Fail -gt 0) { $r.Status="FAIL"; $r.ExitCode=1 }
}))

# 14) RUBY GEMS
$Results.Add((Invoke-Step -Name "Ruby Gems" -Skip:$SkipRuby -Body {
    param($r)
    if (-not (Test-CommandExists "gem")) { $r.Status="SKIP"; $r.Notes.Add("gem brak w PATH."); return }
    if ($WhatIf) { $r.Actions.Add("[WHATIF] gem update --system && gem update"); return }

    Write-Log "gem update --system..."
    $out = @()
    $ec = Try-Run -Body { gem update --system } -OutputLines ([ref]$out)
    $out | ForEach-Object { Write-Log $_ }

    Write-Log "gem update..."
    $out2 = @()
    $ec2 = Try-Run -Body { gem update } -OutputLines ([ref]$out2)
    $out2 | ForEach-Object { Write-Log $_ }

    $r.ExitCode = if ($ec -ne 0) { $ec } else { $ec2 }
    if ($r.ExitCode -ne 0) { $r.Status="FAIL"; $r.Failures.Add("gem update exitCode=$($r.ExitCode)") }
}))

# 15) COMPOSER (PHP)
$Results.Add((Invoke-Step -Name "Composer (PHP)" -Skip:$SkipComposer -Body {
    param($r)
    if (-not (Test-CommandExists "composer")) { $r.Status="SKIP"; $r.Notes.Add("composer brak w PATH."); return }
    if ($WhatIf) { $r.Actions.Add("[WHATIF] composer global update"); return }

    Write-Log "composer global update..."
    $out = @()
    $ec = Try-Run -Body { composer global update } -OutputLines ([ref]$out)
    $out | ForEach-Object { Write-Log $_ }
    $r.ExitCode = $ec
    if ($ec -ne 0) { $r.Status="FAIL"; $r.ExitCode=1; $r.Failures.Add("composer global update exitCode=$ec") }
}))

# 16) YARN
$Results.Add((Invoke-Step -Name "Yarn (global)" -Skip:$SkipYarn -Body {
    param($r)
    if (-not (Test-CommandExists "yarn")) { $r.Status="SKIP"; $r.Notes.Add("yarn brak w PATH."); return }
    if ($WhatIf) { $r.Actions.Add("[WHATIF] yarn global upgrade"); return }

    Write-Log "yarn global upgrade..."
    $out = @()
    $ec = Try-Run -Body { yarn global upgrade } -OutputLines ([ref]$out)
    $out | ForEach-Object { Write-Log $_ }
    $r.ExitCode = $ec
    if ($ec -ne 0) { $r.Status="FAIL"; $r.ExitCode=1; $r.Failures.Add("yarn global upgrade exitCode=$ec") }
}))

# 17) PNPM
$Results.Add((Invoke-Step -Name "pnpm (global)" -Skip:$SkipPnpm -Body {
    param($r)
    if (-not (Test-CommandExists "pnpm")) { $r.Status="SKIP"; $r.Notes.Add("pnpm brak w PATH."); return }
    if ($WhatIf) { $r.Actions.Add("[WHATIF] pnpm update -g"); return }

    Write-Log "pnpm update -g..."
    $out = @()
    $ec = Try-Run -Body { pnpm update -g } -OutputLines ([ref]$out)
    $out | ForEach-Object { Write-Log $_ }
    $r.ExitCode = $ec
    if ($ec -ne 0) { $r.Status="FAIL"; $r.ExitCode=1; $r.Failures.Add("pnpm update -g exitCode=$ec") }
}))

# 18) MS STORE APPS
$Results.Add((Invoke-Step -Name "MS Store Apps" -Skip:$SkipMSStore -Body {
    param($r)
    if (-not (Test-CommandExists "winget")) { $r.Status="SKIP"; $r.Notes.Add("winget brak w PATH."); return }
    if ($WhatIf) { $r.Actions.Add("[WHATIF] winget upgrade --source msstore"); return }

    Write-Log "winget upgrade --source msstore..."
    $args = @("upgrade", "--all", "--source", "msstore", "--accept-source-agreements", "--accept-package-agreements")
    $out = @()
    $ec = Try-Run -Body { winget @args } -OutputLines ([ref]$out)
    $out | ForEach-Object { Write-Log $_ }
    $r.ExitCode = $ec
    if ($ec -ne 0) { $r.Status="FAIL"; $r.ExitCode=1; $r.Failures.Add("winget msstore exitCode=$ec") }
}))

# 19) WSL DISTROS (apt/yum/pacman inside)
$Results.Add((Invoke-Step -Name "WSL Distros (apt/yum/pacman)" -Skip:$SkipWSLDistros -Body {
    param($r)
    if (-not (Test-CommandExists "wsl")) { $r.Status="SKIP"; $r.Notes.Add("wsl brak."); return }

    $distros = @()
    if ($WSLDistros.Count -gt 0) {
        $distros = @($WSLDistros)
    } else {
        # Auto-detect running/available distros
        try {
            Write-Host "  Wykrywam dystrybucje WSL..." -ForegroundColor Gray
            $wslList = @((wsl -l -q) 2>&1 | Where-Object { $_ -and $_ -notmatch '^\s*$' })
            foreach ($d in $wslList) {
                $clean = $d.Trim() -replace '\x00',''
                if ($clean) { $distros += $clean }
            }
        } catch {
            Write-Log "Nie można pobrać listy dystrybucji WSL: $($_.Exception.Message)" "WARN"
        }
    }

    if ($distros.Count -eq 0) { $r.Status="SKIP"; $r.Notes.Add("Brak dystrybucji WSL."); return }

    Write-Host "  Znaleziono: $($distros.Count) dystrybucji WSL" -ForegroundColor Cyan
    Write-Host "  Dystrybucje: " -NoNewline -ForegroundColor Gray
    Write-Host ($distros -join ", ") -ForegroundColor Yellow
    Write-Host ""

    # Ask user if they want to update (requires sudo password)
    Write-Host "  UWAGA: Aktualizacja dystrybucji WSL wymaga hasła sudo!" -ForegroundColor Yellow
    Write-Host "  Będziesz musiał podać hasło dla każdej dystrybucji podczas aktualizacji." -ForegroundColor Yellow
    Write-Host ""
    Write-Host "  Czy chcesz kontynuować aktualizację WSL distros? [T/n]: " -NoNewline -ForegroundColor Cyan

    $userInput = Read-Host
    $shouldUpdate = $true

    if ($userInput -match '^[nN]') {
        $shouldUpdate = $false
    } elseif ([string]::IsNullOrWhiteSpace($userInput)) {
        # Default to Yes (just pressed Enter)
        $shouldUpdate = $true
    } elseif ($userInput -match '^[tTyY]') {
        $shouldUpdate = $true
    }

    if (-not $shouldUpdate) {
        $r.Status = "SKIP"
        $r.Notes.Add("Pominięto na życzenie użytkownika (wymaga hasła sudo).")
        Write-Host "  Pomijam aktualizację WSL distros" -ForegroundColor Yellow
        return
    }

    Write-Host "  Rozpoczynam aktualizację dystrybucji WSL..." -ForegroundColor Green
    Write-Host ""

    if ($WhatIf) { $r.Actions.Add("[WHATIF] aktualizacja $($distros.Count) dystrybucji WSL"); return }

    $r.Actions.Add("WSL distros: $($distros.Count)")
    $r.Counts.Available = $distros.Count

    foreach ($distro in $distros) {
        $r.Counts.Total++

        Write-Host "  Aktualizuję dystrybucję: " -NoNewline -ForegroundColor Gray
        Write-Host $distro -ForegroundColor Cyan

        $updated = $false

        # Check if distro has apt (Debian/Ubuntu-based)
        $hasApt = $false
        try {
            Write-Host "    Wykrywam menedżer pakietów..." -ForegroundColor DarkGray
            $checkApt = @((wsl -d $distro -- which apt) 2>&1)
            if ($LASTEXITCODE -eq 0) { $hasApt = $true }
        } catch {}

        if ($hasApt) {
            try {
                Write-Host "    Menedżer pakietów: " -NoNewline -ForegroundColor Gray
                Write-Host "apt (Debian/Ubuntu)" -ForegroundColor Yellow
                Write-Host "    Uruchamiam: apt update && apt upgrade -y" -ForegroundColor Gray
                Write-Host "    (Podaj hasło sudo gdy zostaniesz poproszony)" -ForegroundColor DarkYellow

                Write-Log "WSL ($distro): apt update && apt upgrade -y"
                $cmd = "sudo apt update && sudo apt upgrade -y"
                $outApt = @((wsl -d $distro -- bash -c $cmd) 2>&1)
                $ecApt = $LASTEXITCODE
                $outApt | ForEach-Object { Write-Log $_ }

                if ($ecApt -eq 0) {
                    $r.Counts.Ok++
                    $r.Counts.Updated++
                    Write-Host "    ✓ $distro zaktualizowano" -ForegroundColor Green
                }
                else {
                    $r.Counts.Fail++
                    $r.Counts.Failed++
                    $r.Failures.Add("WSL apt FAIL: $distro (exitCode=$ecApt)")
                    Write-Host "    ✗ $distro - błąd (exitCode=$ecApt)" -ForegroundColor Red
                }
                $updated = $true
            } catch {
                $r.Counts.Fail++
                $r.Counts.Failed++
                $r.Failures.Add("WSL apt FAIL: $distro :: $($_.Exception.Message)")
                Write-Host "    ✗ $distro - wyjątek: $($_.Exception.Message)" -ForegroundColor Red
                $updated = $true
            }
        }

        # Try yum (RHEL/CentOS/Fedora-based)
        if (-not $updated) {
            $hasYum = $false
            try {
                $checkYum = @((wsl -d $distro -- which yum) 2>&1)
                if ($LASTEXITCODE -eq 0) { $hasYum = $true }
            } catch {}

            if ($hasYum) {
                try {
                    Write-Host "    Menedżer pakietów: " -NoNewline -ForegroundColor Gray
                    Write-Host "yum (RHEL/CentOS/Fedora)" -ForegroundColor Yellow
                    Write-Host "    Uruchamiam: yum update -y" -ForegroundColor Gray
                    Write-Host "    (Podaj hasło sudo gdy zostaniesz poproszony)" -ForegroundColor DarkYellow

                    Write-Log "WSL ($distro): yum update -y"
                    $cmd = "sudo yum update -y"
                    $outYum = @((wsl -d $distro -- bash -c $cmd) 2>&1)
                    $ecYum = $LASTEXITCODE
                    $outYum | ForEach-Object { Write-Log $_ }

                    if ($ecYum -eq 0) {
                        $r.Counts.Ok++
                        $r.Counts.Updated++
                        Write-Host "    ✓ $distro zaktualizowano" -ForegroundColor Green
                    }
                    else {
                        $r.Counts.Fail++
                        $r.Counts.Failed++
                        $r.Failures.Add("WSL yum FAIL: $distro (exitCode=$ecYum)")
                        Write-Host "    ✗ $distro - błąd (exitCode=$ecYum)" -ForegroundColor Red
                    }
                    $updated = $true
                } catch {
                    $r.Counts.Fail++
                    $r.Counts.Failed++
                    $r.Failures.Add("WSL yum FAIL: $distro :: $($_.Exception.Message)")
                    Write-Host "    ✗ $distro - wyjątek: $($_.Exception.Message)" -ForegroundColor Red
                    $updated = $true
                }
            }
        }

        # Try pacman (Arch Linux-based)
        if (-not $updated) {
            $hasPacman = $false
            try {
                $checkPacman = @((wsl -d $distro -- which pacman) 2>&1)
                if ($LASTEXITCODE -eq 0) { $hasPacman = $true }
            } catch {}

            if ($hasPacman) {
                try {
                    Write-Host "    Menedżer pakietów: " -NoNewline -ForegroundColor Gray
                    Write-Host "pacman (Arch Linux)" -ForegroundColor Yellow
                    Write-Host "    Uruchamiam: pacman -Syu --noconfirm" -ForegroundColor Gray
                    Write-Host "    (Podaj hasło sudo gdy zostaniesz poproszony)" -ForegroundColor DarkYellow

                    Write-Log "WSL ($distro): pacman -Syu --noconfirm"
                    $cmd = "sudo pacman -Syu --noconfirm"
                    $outPacman = @((wsl -d $distro -- bash -c $cmd) 2>&1)
                    $ecPacman = $LASTEXITCODE
                    $outPacman | ForEach-Object { Write-Log $_ }

                    if ($ecPacman -eq 0) {
                        $r.Counts.Ok++
                        $r.Counts.Updated++
                        Write-Host "    ✓ $distro zaktualizowano" -ForegroundColor Green
                    }
                    else {
                        $r.Counts.Fail++
                        $r.Counts.Failed++
                        $r.Failures.Add("WSL pacman FAIL: $distro (exitCode=$ecPacman)")
                        Write-Host "    ✗ $distro - błąd (exitCode=$ecPacman)" -ForegroundColor Red
                    }
                    $updated = $true
                } catch {
                    $r.Counts.Fail++
                    $r.Counts.Failed++
                    $r.Failures.Add("WSL pacman FAIL: $distro :: $($_.Exception.Message)")
                    Write-Host "    ✗ $distro - wyjątek: $($_.Exception.Message)" -ForegroundColor Red
                    $updated = $true
                }
            }
        }

        if (-not $updated) {
            $r.Notes.Add("WSL: $distro - brak apt/yum/pacman, pomijam")
            Write-Log "WSL: $distro - brak apt/yum/pacman, pomijam" "WARN"
            Write-Host "    ⊘ $distro - brak obsługiwanego menedżera pakietów (apt/yum/pacman)" -ForegroundColor Yellow
        }
    }

    if ($r.Counts.Fail -gt 0) { $r.Status="FAIL"; $r.ExitCode=1 }
}))

# ----------------- SUMMARY -----------------
Write-Host ""
Write-Host "=== PODSUMOWANIE AKTUALIZACJI (ULTRA v4.1) ===" -ForegroundColor Cyan
Write-Host ""
Write-Host "Legenda kolumn:" -ForegroundColor Gray
Write-Host "  Dostępne     = pakiety z nowszą wersją (wykryte przed aktualizacją)" -ForegroundColor DarkGray
Write-Host "  Zaktualizowano = pakiety pomyślnie zaktualizowane" -ForegroundColor DarkGray
Write-Host "  Pominięto    = pakiety pominięte (ignorowane, user skip)" -ForegroundColor DarkGray
Write-Host "  Błędy        = pakiety z błędem aktualizacji" -ForegroundColor DarkGray
Write-Host ""

$summary = $Results | ForEach-Object {
    [pscustomobject]@{
        Sekcja         = $_.Name
        Status         = $_.Status
        'Czas(s)'      = $_.DurationS
        Dostępne       = $_.Counts.Available
        Zaktualizowano = $_.Counts.Updated
        Pominięto      = $_.Counts.Skipped
        'Błędy'        = $_.Counts.Failed
    }
}
$summary | Format-Table -AutoSize

# Podsumowanie końcowe
$totalAvailable = ($Results | Measure-Object -Property { $_.Counts.Available } -Sum).Sum
$totalUpdated = ($Results | Measure-Object -Property { $_.Counts.Updated } -Sum).Sum
$totalSkipped = ($Results | Measure-Object -Property { $_.Counts.Skipped } -Sum).Sum
$totalFailed = ($Results | Measure-Object -Property { $_.Counts.Failed } -Sum).Sum

Write-Host ""
Write-Host "=== PODSUMOWANIE GLOBALNE ===" -ForegroundColor Cyan
Write-Host ("  Dostępne aktualizacje: {0}" -f $totalAvailable) -ForegroundColor $(if ($totalAvailable -gt 0) { "Yellow" } else { "Gray" })
Write-Host ("  Zaktualizowano:        {0}" -f $totalUpdated) -ForegroundColor $(if ($totalUpdated -gt 0) { "Green" } else { "Gray" })
Write-Host ("  Pominięto:             {0}" -f $totalSkipped) -ForegroundColor $(if ($totalSkipped -gt 0) { "Yellow" } else { "Gray" })
Write-Host ("  Błędy:                 {0}" -f $totalFailed) -ForegroundColor $(if ($totalFailed -gt 0) { "Red" } else { "Gray" })
Write-Host ""

Write-Host ""
foreach ($r in $Results) {
    if ($r.Status -eq "FAIL") {
        Write-Host ("--- FAIL: {0} ---" -f $r.Name) -ForegroundColor Yellow
        foreach ($f in ($r.Failures | Select-Object -First 50)) {
            Write-Host "  $f" -ForegroundColor Yellow
        }
        if ($r.Artifacts.Keys.Count -gt 0) {
            Write-Host "  Logi/Artefakty:" -ForegroundColor Yellow
            foreach ($k in $r.Artifacts.Keys) {
                Write-Host ("    {0}: {1}" -f $k, $r.Artifacts[$k]) -ForegroundColor Yellow
            }
        }
        Write-Host ""
    }
}

$summaryObj = [pscustomobject]@{
    run_at   = (Get-Date).ToString("s")
    log_file = $script:logFile
    results  = $Results
}

$summaryJsonPath = Join-Path $LogDirectory ("dev_update_{0}_summary.json" -f $timestamp)
try {
    $summaryObj | ConvertTo-Json -Depth 12 | Set-Content -Path $summaryJsonPath -Encoding UTF8
    Write-Host "Summary JSON: $summaryJsonPath"
    Write-Log "Summary JSON: $summaryJsonPath"
} catch {
    Write-Log "Nie udało się zapisać summary JSON: $($_.Exception.Message)" "WARN"
}

Write-Host "Pełny log: $script:logFile"
Write-Log "===== END UPDATE (ULTRA v4.1) ====="

$overallFail = $Results | Where-Object { $_.Status -eq "FAIL" }
if ($overallFail) { exit 1 } else { exit 0 }
