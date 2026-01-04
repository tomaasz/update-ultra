# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

**update-ultra** is a comprehensive Windows development environment update automation tool that automatically detects and updates all installed development tools and package managers in a single unified operation. Written in PowerShell, it supports 19 different environments including Winget, Python/Pip, npm, Chocolatey, PowerShell Modules, VS Code Extensions, Docker, Git repos, WSL distros, and more.

Current version: **v4.1** (MIT License)

## Running the Script

```powershell
# Basic execution (requires Administrator)
.\src\Update-WingetAll.ps1

# Common options
.\src\Update-WingetAll.ps1 -WhatIf                    # Dry-run preview
.\src\Update-WingetAll.ps1 -Force                     # Force updates
.\src\Update-WingetAll.ps1 -SkipDocker -SkipWSL       # Skip specific sections

# After installing alias (via .\install-alias.ps1)
upd
upd -WhatIf
```

## Testing

```powershell
# Run all tests
pwsh -NoProfile -File .\tests\test-winget-parser.ps1
pwsh -NoProfile -File .\tests\test_sanitize.ps1
pwsh -NoProfile -File .\tests\test_log_reporting.ps1

# Tests run automatically via GitHub Actions on push to main/fix-* branches
```

## Architecture

### Main Entry Point

`src/Update-WingetAll.ps1` (1,666 lines) - Contains all core logic:
- **Lines 63-83**: Configuration section (customize package lists, paths, ignore lists)
- **Lines 152-178**: `New-StepResult()` - Core data structure for section results
- **Lines 180-238**: `Show-PackageList()` - Displays package updates with versions
- **Lines 252-336**: `Invoke-Step()` - Executes sections with error handling and timing
- **Lines 465-1435**: 19 update sections (Winget, Python/Pip, npm, etc.)
- **Lines 1436-1520**: Summary generation and reporting

### Core Data Structures

**StepResult Object:**
```powershell
[ordered]@{
    Name      = String           # Section name
    Status    = "OK|FAIL|SKIP"
    DurationS = Float            # Execution time
    Counts    = @{
        Installed = Int          # Total packages in environment
        Available = Int          # Updates available (detected before update)
        Updated   = Int          # Successfully updated
        Skipped   = Int          # Ignored packages
        Failed    = Int          # Failed updates
    }
    Packages  = List[object]     # Detailed package info with versions
    Failures  = List[string]     # Error messages
    Artifacts = @{}              # Log file paths
}
```

**Package Object:**
```powershell
[pscustomobject]@{
    Name          = String
    VersionBefore = String       # Version before update
    VersionAfter  = String       # Version after update
    Status        = "Updated|Failed|Skipped|NoChange"
}
```

### Key Helper Functions

**Critical Parsers (Winget):**
- `Parse-WingetUpgradeList()` - Parses `winget upgrade` output into structured objects
- `Get-WingetExplicitTargetIds()` - Extracts packages requiring `--id` explicit targeting
- `Get-WingetRunningBlockers()` - Detects running applications blocking updates

**Safe Execution:**
- `Try-Run()` - Executes external commands safely, captures output and exit code
- `Invoke-Step()` - Wrapper for section execution with timing, error handling, and package list display
- `As-Array()` / `SafeCount()` - Prevents PowerShell array unpacking issues (critical for reliability)

**Utilities:**
- `Sanitize-FileName()` - Converts package IDs to safe filenames (handles special chars, reserved names, length limits)
- `Get-PythonTargets()` - Auto-discovers Python interpreters and virtual environments
- `Test-CommandExists()` - Checks if a command is available in PATH

## Important Implementation Details

### Winget Section Special Handling

The Winget section has the most complex logic due to:
1. **Explicit Targeting**: Some packages require `winget upgrade --id <ID> -e` instead of `--all`
2. **Running Blockers**: Detects apps that must be closed before updating
3. **Ignore Lists**: `$WingetIgnoreIds` - packages that auto-update (e.g., Discord)
4. **Retry Logic**: `$WingetRetryIds` - packages that may need a second attempt
5. **Log Sanitization**: Package IDs are sanitized for log file names (e.g., `Discord.Discord` → `Discord.Discord`)

### PowerShell Compatibility

The script is compatible with **PowerShell 5.1** (Windows default) and **PowerShell 7+**:
- **DO NOT use `??` null coalescing operator** (only works in PS 7+)
- **Use explicit if/else chains** instead
- **Avoid `-and` operator on `List[object]` types** (causes "Argument types do not match" error in PS 5.1)
- **Split complex conditionals** into separate null checks

Example:
```powershell
# WRONG (PS 7+ only)
$name = $before.Name ?? $after.Name ?? $id

# RIGHT (PS 5.1 compatible)
$name = $id
if ($before -and $before.Name) { $name = $before.Name }
elseif ($after -and $after.Name) { $name = $after.Name }
```

### Python/Pip Auto-Discovery

The script auto-discovers Python environments through:
1. `py -0p` launcher (lists all installed Python versions)
2. Manual venv scanning in `$PythonVenvRootPaths` (default: `C:\venv`, `$HOME\.virtualenvs`)
3. Explicit venv paths in `$PythonVenvExplicit`
4. Command existence check for `python` and `python3`

### WSL Distros Interactive Prompt

WSL distros section requires sudo password, so it:
1. Auto-detects distros via `wsl -l -q`
2. **Prompts user** for confirmation (requires interactive input)
3. Detects package manager (apt/yum/pacman) via `which` command
4. Runs updates with sudo (user must enter password interactively)

### Logging & Output

**Log Directory:** `$env:ProgramData\Winget-Logs` (default: `C:\ProgramData\Winget-Logs`)

**Generated Files:**
- `dev_update_YYYYMMDD_HHmmss.log` - Full timestamped execution log
- `dev_update_YYYYMMDD_HHmmss_summary.json` - Structured JSON results
- `winget_all_*.log` - Winget bulk operation log
- `winget_explicit_<PackageID>_*.log` - Per-package explicit targeting logs
- `winget_retry_<PackageID>_*.log` - Retry operation logs

**Console Output:**
- Real-time progress with colored status indicators
- Symbol usage: `✓` (success), `✗` (fail), `⊘` (skip), `=` (no change)
- Package lists with version tracking (e.g., `pip 23.0.1 → 24.0`)
- Final summary table with statistics per section

## Configuration Customization

Edit lines 63-83 in `src/Update-WingetAll.ps1`:

```powershell
# Ignore specific winget packages (e.g., auto-updaters)
$WingetIgnoreIds = @("Discord.Discord", "Spotify.Spotify")

# Python venv root directories for auto-discovery
$PythonVenvRootPaths = @("C:\venv", "D:\Projects\.venvs")

# Git repository root directories for auto-discovery
$GitRootPaths = @("C:\Dev", "D:\Projects")

# Docker images to update (empty = all local images)
$DockerImagesToUpdate = @("nginx:latest", "postgres:15")

# WSL distros to update (empty = auto-detect all)
$WSLDistros = @("Ubuntu-24.04")
```

## Adding New Update Sections

Follow this pattern (see existing sections as examples):

```powershell
$Results.Add((Invoke-Step -Name "My Tool" -Skip:$SkipMyTool -Body {
    param($r)

    # 1. Check if tool exists
    if (-not (Test-CommandExists "mytool")) {
        $r.Status = "SKIP"
        $r.Notes.Add("mytool not found in PATH.")
        return
    }

    # 2. Get installed packages count
    $r.Counts.Installed = <count logic>

    # 3. Get available updates count
    $r.Counts.Available = <count logic>

    # 4. Run updates
    foreach ($pkg in $packages) {
        $r.Counts.Total++
        try {
            # Update package
            $r.Counts.Ok++
            $r.Counts.Updated++

            # Add to package list
            $r.Packages.Add([pscustomobject]@{
                Name          = $pkg.Name
                VersionBefore = $pkg.OldVersion
                VersionAfter  = $pkg.NewVersion
                Status        = "Updated"
            })
        } catch {
            $r.Counts.Fail++
            $r.Counts.Failed++
            $r.Failures.Add("Update failed: $($pkg.Name)")
        }
    }

    # 5. Set final status
    if ($r.Counts.Fail -gt 0) { $r.Status = "FAIL"; $r.ExitCode = 1 }
}))
```

Don't forget to add `-SkipMyTool` parameter to the param block (lines 26-44).

## Common Debugging

**Debug output is built-in** (look for `[DEBUG]` messages in DarkGray):
- Package list processing diagnostics
- Package count tracking
- Function call tracing

**Check logs** at `C:\ProgramData\Winget-Logs\`:
- Look for `[DEBUG]` entries showing package additions
- Review section completion messages with package counts
- Check error messages with stack traces

## Version History Notes

- **v4.1** (current): Enhanced statistics, package lists with version tracking, WSL interactive prompts
- **v4.0**: Added 10 new environments (Scoop, pipx, Cargo, Go, Ruby, etc.), universal detection
- **v3.x**: Winget parser fixes, explicit targeting support

## CI/CD

GitHub Actions runs tests on:
- Push to `main` or `fix-*` branches
- Pull requests to `main`

Tests run on Windows runners and validate:
- Winget parser logic (19 assertions)
- Filename sanitization (11 test cases)
- Log path resolution (4 scenarios)
