<#
Update-WingetAll.ps1 — ULTRA v3.3

Naprawy vs v3.2:
- 100% odporność na PS "Count" (pojedynczy obiekt vs tablica vs pipeline unrolling)
- Winget parsing: $parts zawsze jest tablicą (@(...))
- Python/Pip: SafeCount nie opiera się na To-Array output
- Docker: jeśli daemon/CLI zwróci błąd przy listowaniu obrazów -> SKIP, nie pull "tekstu błędu"
- Debug: w razie wyjątku pokazuje Linia + Kod

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
    [switch]$SkipWSL
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

$DockerImagesToUpdate = @() # empty = update all local images

$GitRepos     = @()
$GitRootPaths = @("C:\Dev")
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
        Counts    = [ordered]@{ Ok = 0; Fail = 0; Total = 0 }
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

    if ($Skip) {
        $r.Notes.Add("Pominięte przełącznikiem Skip.")
        return (Finish-StepResult -R $r -Status "SKIP" -ExitCode 0)
    }

    try {
        & $Body $r
        if ($r.Status -eq "PENDING") {
            return (Finish-StepResult -R $r -Status "OK" -ExitCode 0)
        }
        return (Finish-StepResult -R $r -Status $r.Status -ExitCode ($r.ExitCode ?? 0))
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

    foreach ($raw in (As-Array $Lines)) {
        $l = [string]$raw

        if ($l -match 'require explicit targeting') { $inTable = $true; continue }
        if (-not $inTable) { continue }
        if ($l -match '^\s*Name\s+Id\s+Version') { continue }
        if ($l -match '^\s*-+\s*$') { continue }
        if ([string]::IsNullOrWhiteSpace($l)) {
            # Skip blank lines before table or between sections.
            continue
        }

        $parts = @($l -split '\s{2,}' | Where-Object { $_ -ne "" })
        if ($parts.Count -ge 2) { $ids.Add($parts[1]) | Out-Null }
    }

    return @($ids | Select-Object -Unique)
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

Write-Log "===== START UPDATE (ULTRA v3.3) ====="
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

    Write-Log "LIST PRZED: winget upgrade"
    $beforeRaw = @()
    [void](Try-Run -Body { winget upgrade } -OutputLines ([ref]$beforeRaw))

    $beforeItems = @(Parse-WingetUpgradeList -Lines $beforeRaw)
    $explicitIdsBefore = @(Get-WingetExplicitTargetIds -Lines $beforeRaw)

    $r.Actions.Add("Do aktualizacji (przed): $($beforeItems.Count)")
    if ($explicitIdsBefore.Count -gt 0) {
        $r.Actions.Add("Require explicit targeting (przed): $($explicitIdsBefore.Count) -> " + ($explicitIdsBefore -join ", "))
    }

    if ($WhatIf) {
        $r.Actions.Add("[WHATIF] winget source update")
    } else {
        Write-Log "winget source update..."
        @((winget source update) 2>&1) | ForEach-Object { Write-Log $_ }
    }

    if ($WhatIf) {
        $r.Actions.Add("[WHATIF] winget upgrade --id Microsoft.AppInstaller -e")
    } else {
        Write-Log "Aktualizacja App Installer..."
        $aiLog = Join-Path $LogDirectory ("winget_AppInstaller_{0}.log" -f (Get-Date -Format "yyyyMMdd_HHmmss"))

        $aiArgs = @(
            "upgrade","--id","Microsoft.AppInstaller","-e",
            "--accept-source-agreements","--accept-package-agreements",
            "--disable-interactivity"
        )
        if ($Force) { $aiArgs += "--force" }

        $aiOut = @(& winget @aiArgs 2>&1)
        $aiEc  = $LASTEXITCODE
        try { $aiOut | Set-Content -LiteralPath $aiLog -Encoding UTF8 -ErrorAction SilentlyContinue } catch {}
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
            "--disable-interactivity"
        )
        if ($Force) { $args += "--force" }

        if ($WhatIf) {
            $r.Actions.Add("[WHATIF] EXPLICIT: winget $($args -join ' ')")
            continue
        }

        Write-Log "EXPLICIT: winget $($args -join ' ')"
        $outX = @(& winget @args 2>&1)
        $ecX  = $LASTEXITCODE
        try { $outX | Set-Content -LiteralPath $singleLog -Encoding UTF8 -ErrorAction SilentlyContinue } catch {}
        $outX | ForEach-Object { Write-Log $_ }

        $r.Artifacts["winget_explicit_$($cleanId)"] = Resolve-ExistingLogOrNote -Path $singleLog

        $r.Counts.Total++
        if ($ecX -eq 0) { $r.Counts.Ok++; $r.Actions.Add("EXPLICIT OK: $id") }
        else {
            $r.Counts.Fail++
            $r.Failures.Add("EXPLICIT FAIL: $id (exitCode=$ecX) log=$(Resolve-ExistingLogOrNote -Path $singleLog)")
            # Policy: First non-zero exit code determines the section result.
            if ($r.ExitCode -eq 0) { $r.ExitCode = $ecX }
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
            "--disable-interactivity"
        )
        if ($Force) { $retryArgs += "--force" }

        if ($WhatIf) {
            $r.Actions.Add("[WHATIF] RETRY: winget $($retryArgs -join ' ')")
            continue
        }

        Write-Log "RETRY: winget $($retryArgs -join ' ')"
        $outR = @(& winget @retryArgs 2>&1)
        $ecR  = $LASTEXITCODE
        try { $outR | Set-Content -LiteralPath $retryLog -Encoding UTF8 -ErrorAction SilentlyContinue } catch {}
        $outR | ForEach-Object { Write-Log $_ }

        $r.Artifacts["winget_retry_$($cleanId)"] = Resolve-ExistingLogOrNote -Path $retryLog

        $r.Counts.Total++
        if ($ecR -eq 0) { $r.Counts.Ok++; $r.Actions.Add("RETRY OK: $id") }
        else {
            $r.Counts.Fail++
            $r.Failures.Add("RETRY FAIL: $id (exitCode=$ecR) log=$(Resolve-ExistingLogOrNote -Path $retryLog)")
            if ($r.ExitCode -eq 0) { $r.ExitCode = $ecR }
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
        foreach ($p in $pkgs) {
            $r.Counts.Total++
            try {
                Write-Log "pip upgrade pkg: $($p.name) ($t)"
                @(& $t -m pip install --upgrade $p.name 2>&1) | ForEach-Object { Write-Log $_ }
                $r.Counts.Ok++
            } catch {
                $r.Counts.Fail++
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
    foreach ($m in $mods) {
        $r.Counts.Total++
        try {
            Write-Log "Update-Module: $($m.Name)"
            Update-Module -Name $m.Name -Force -ErrorAction Continue 2>&1 | ForEach-Object { Write-Log $_ }
            $r.Counts.Ok++
        } catch {
            $r.Counts.Fail++
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

    foreach ($e in $ext) {
        $r.Counts.Total++
        try {
            Write-Log "VSCode ext --force: $e"
            @((code --install-extension $e --force) 2>&1) | ForEach-Object { Write-Log $_ }
            $r.Counts.Ok++
        } catch {
            $r.Counts.Fail++
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
    foreach ($repo in $repos) {
        $r.Counts.Total++
        Push-Location $repo
        try {
            Write-Log "git pull ($repo)"
            $outPull = @()
            $ecPull = Try-Run -Body { git pull } -OutputLines ([ref]$outPull)
            $outPull | ForEach-Object { Write-Log $_ }
            if ($ecPull -eq 0) { $r.Counts.Ok++ }
            else { $r.Counts.Fail++; $r.Failures.Add("git pull FAIL: $repo (exitCode=$ecPull)") }
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

# ----------------- SUMMARY -----------------
Write-Host ""
Write-Host "=== PODSUMOWANIE AKTUALIZACJI (ULTRA v3.3) ==="

$summary = $Results | ForEach-Object {
    [pscustomobject]@{
        Sekcja   = $_.Name
        Status   = $_.Status
        Czas_s   = $_.DurationS
        ExitCode = $_.ExitCode
        OK       = $_.Counts.Ok
        FAIL     = $_.Counts.Fail
        Total    = $_.Counts.Total
    }
}
$summary | Format-Table -AutoSize

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
Write-Log "===== END UPDATE (ULTRA v3.3) ====="

$overallFail = $Results | Where-Object { $_.Status -eq "FAIL" }
if ($overallFail) { exit 1 } else { exit 0 }
