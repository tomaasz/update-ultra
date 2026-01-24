# SnapshotManager.psm1
# Package snapshot and rollback system

<#
.SYNOPSIS
Module for creating snapshots of package versions and rolling back updates

.DESCRIPTION
Provides comprehensive snapshot functionality:
- Create snapshots before updates
- Compare snapshots to see what changed
- Rollback to previous package versions
- Manage snapshot history

.NOTES
Version: 1.0
Author: update-ultra team
Created: 2026-01-23
Dependencies: None (core module)
#>

# =============================================================================
# MODULE INITIALIZATION
# =============================================================================

$script:SnapshotConfig = @{
    Version = "1.0"
    SnapshotDirectory = "$env:ProgramData\Update-Ultra\Snapshots"
    MaxSnapshots = 10  # Keep last 10 snapshots
    CompressionEnabled = $true
}

# =============================================================================
# PRIVATE FUNCTIONS
# =============================================================================

function Get-SystemInfo {
    [CmdletBinding()]
    param()

    return [pscustomobject]@{
        Hostname = $env:COMPUTERNAME
        Username = $env:USERNAME
        OSVersion = [System.Environment]::OSVersion.VersionString
        PowerShellVersion = $PSVersionTable.PSVersion.ToString()
        Architecture = [System.Environment]::Is64BitOperatingSystem ? "x64" : "x86"
    }
}

function Get-WingetPackages {
    [CmdletBinding()]
    param()

    $packages = New-Object System.Collections.Generic.List[object]

    try {
        $output = @((winget list --source winget) 2>&1)

        foreach ($line in $output) {
            if ($line -match '^\s*Name\s+Id\s+Version') { continue }
            if ($line -match '^\s*-+\s*$') { continue }
            if ([string]::IsNullOrWhiteSpace($line)) { continue }

            $parts = @($line -split '\s{2,}' | Where-Object { $_ -ne "" })

            if ($parts.Count -ge 3) {
                $packages.Add([pscustomobject]@{
                    Name = $parts[0]
                    Id = $parts[1]
                    Version = $parts[2]
                    Source = "winget"
                })
            }
        }
    }
    catch {
        Write-Warning "Failed to get Winget packages: $($_.Exception.Message)"
    }

    return $packages
}

function Get-PipPackages {
    [CmdletBinding()]
    param([string]$PythonExe)

    $packages = New-Object System.Collections.Generic.List[object]

    try {
        $output = & $PythonExe -m pip list --format=json 2>$null | ConvertFrom-Json

        foreach ($pkg in $output) {
            $packages.Add([pscustomobject]@{
                Name = $pkg.name
                Version = $pkg.version
                Interpreter = $PythonExe
            })
        }
    }
    catch {
        Write-Warning "Failed to get pip packages from $PythonExe : $($_.Exception.Message)"
    }

    return $packages
}

function Get-NpmPackages {
    [CmdletBinding()]
    param()

    $packages = New-Object System.Collections.Generic.List[object]

    try {
        $output = npm list -g --depth=0 --json 2>$null | ConvertFrom-Json

        foreach ($pkgName in $output.dependencies.PSObject.Properties.Name) {
            $pkgData = $output.dependencies.$pkgName
            $packages.Add([pscustomobject]@{
                Name = $pkgName
                Version = $pkgData.version
            })
        }
    }
    catch {
        Write-Warning "Failed to get npm packages: $($_.Exception.Message)"
    }

    return $packages
}

function Get-ChocoPackages {
    [CmdletBinding()]
    param()

    $packages = New-Object System.Collections.Generic.List[object]

    try {
        $output = @((choco list --local-only) 2>&1)

        foreach ($line in $output) {
            if ($line -match '^(\S+)\s+([\d\.]+)') {
                $packages.Add([pscustomobject]@{
                    Name = $Matches[1]
                    Version = $Matches[2]
                })
            }
        }
    }
    catch {
        Write-Warning "Failed to get Chocolatey packages: $($_.Exception.Message)"
    }

    return $packages
}

function Get-PowerShellModulesSnapshot {
    [CmdletBinding()]
    param()

    $modules = New-Object System.Collections.Generic.List[object]

    try {
        $installed = Get-InstalledModule -ErrorAction SilentlyContinue

        foreach ($mod in $installed) {
            $modules.Add([pscustomobject]@{
                Name = $mod.Name
                Version = $mod.Version.ToString()
                Repository = $mod.Repository
            })
        }
    }
    catch {
        Write-Warning "Failed to get PowerShell modules: $($_.Exception.Message)"
    }

    return $modules
}

function Compress-Snapshot {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$SourcePath,

        [Parameter(Mandatory)]
        [string]$DestinationPath
    )

    try {
        Compress-Archive -Path $SourcePath -DestinationPath $DestinationPath -CompressionLevel Optimal -Force
        Write-Verbose "Compressed snapshot: $DestinationPath"
        return $true
    }
    catch {
        Write-Warning "Failed to compress snapshot: $($_.Exception.Message)"
        return $false
    }
}

function Expand-Snapshot {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$ArchivePath,

        [Parameter(Mandatory)]
        [string]$DestinationPath
    )

    try {
        Expand-Archive -Path $ArchivePath -DestinationPath $DestinationPath -Force
        Write-Verbose "Expanded snapshot: $ArchivePath"
        return $true
    }
    catch {
        Write-Warning "Failed to expand snapshot: $($_.Exception.Message)"
        return $false
    }
}

# =============================================================================
# PUBLIC FUNCTIONS
# =============================================================================

<#
.SYNOPSIS
Initialize snapshot system

.DESCRIPTION
Creates snapshot directory and validates configuration

.PARAMETER SnapshotDirectory
Custom directory for storing snapshots

.PARAMETER MaxSnapshots
Maximum number of snapshots to keep (older ones are deleted)

.PARAMETER DisableCompression
Disable compression for faster snapshots (uses more disk space)

.EXAMPLE
Initialize-SnapshotManager

.EXAMPLE
Initialize-SnapshotManager -SnapshotDirectory "D:\Backups\Snapshots" -MaxSnapshots 20
#>

function Initialize-SnapshotManager {
    [CmdletBinding()]
    param(
        [string]$SnapshotDirectory = $script:SnapshotConfig.SnapshotDirectory,
        [int]$MaxSnapshots = $script:SnapshotConfig.MaxSnapshots,
        [switch]$DisableCompression
    )

    $script:SnapshotConfig.SnapshotDirectory = $SnapshotDirectory
    $script:SnapshotConfig.MaxSnapshots = $MaxSnapshots
    $script:SnapshotConfig.CompressionEnabled = -not $DisableCompression

    if (-not (Test-Path $SnapshotDirectory)) {
        New-Item -ItemType Directory -Path $SnapshotDirectory -Force | Out-Null
        Write-Verbose "Created snapshot directory: $SnapshotDirectory"
    }

    Write-Host "Snapshot system initialized" -ForegroundColor Green
    Write-Host "  Directory: $SnapshotDirectory" -ForegroundColor Gray
    Write-Host "  Max snapshots: $MaxSnapshots" -ForegroundColor Gray
    Write-Host "  Compression: $($script:SnapshotConfig.CompressionEnabled)" -ForegroundColor Gray
}

<#
.SYNOPSIS
Create a snapshot of all installed packages

.DESCRIPTION
Captures current versions of all packages from supported package managers:
- Winget
- Python/Pip (all discovered interpreters)
- npm (global)
- Chocolatey
- PowerShell Modules
- VS Code Extensions
- Docker Images

.PARAMETER Name
Optional custom name for snapshot (default: timestamp)

.PARAMETER IncludePython
Include Python/Pip packages (may be slow with many environments)

.PARAMETER IncludeDocker
Include Docker images (may be very large)

.EXAMPLE
New-PackageSnapshot
Creates snapshot with auto-generated timestamp name

.EXAMPLE
New-PackageSnapshot -Name "before-major-update"
Creates snapshot with custom name

.OUTPUTS
PSCustomObject with snapshot metadata
#>

function New-PackageSnapshot {
    [CmdletBinding()]
    param(
        [string]$Name,

        [switch]$IncludePython = $true,
        [switch]$IncludeDocker = $false
    )

    # Ensure initialized
    if (-not (Test-Path $script:SnapshotConfig.SnapshotDirectory)) {
        Initialize-SnapshotManager
    }

    $timestamp = Get-Date -Format "yyyyMMdd_HHmmss"
    $snapshotName = if ($Name) { "${Name}_${timestamp}" } else { "snapshot_${timestamp}" }

    Write-Host ""
    Write-Host "Creating package snapshot: " -NoNewline -ForegroundColor Cyan
    Write-Host $snapshotName -ForegroundColor Yellow
    Write-Host ""

    $snapshot = [ordered]@{
        Name = $snapshotName
        Timestamp = Get-Date
        System = Get-SystemInfo
        Packages = @{}
    }

    # Winget
    if (Get-Command winget -ErrorAction SilentlyContinue) {
        Write-Host "  Capturing Winget packages..." -ForegroundColor Gray
        $snapshot.Packages.Winget = @(Get-WingetPackages)
        Write-Host "    ✓ $($snapshot.Packages.Winget.Count) packages" -ForegroundColor Green
    }

    # Python/Pip
    if ($IncludePython -and (Get-Command python -ErrorAction SilentlyContinue)) {
        Write-Host "  Capturing Python/Pip packages..." -ForegroundColor Gray
        $pythonTargets = @("python", "python3")

        # Try py launcher
        if (Get-Command py -ErrorAction SilentlyContinue) {
            try {
                $pyList = @((py -0p) 2>&1)
                foreach ($line in $pyList) {
                    if ($line -match '\s+(.+\.exe)\s*$') {
                        $pythonTargets += $Matches[1]
                    }
                }
            } catch {}
        }

        $pythonTargets = @($pythonTargets | Select-Object -Unique)

        foreach ($pyExe in $pythonTargets) {
            if (Get-Command $pyExe -ErrorAction SilentlyContinue) {
                $pkgs = @(Get-PipPackages -PythonExe $pyExe)
                if ($pkgs.Count -gt 0) {
                    if (-not $snapshot.Packages.Pip) {
                        $snapshot.Packages.Pip = @()
                    }
                    $snapshot.Packages.Pip += $pkgs
                }
            }
        }

        if ($snapshot.Packages.Pip) {
            Write-Host "    ✓ $($snapshot.Packages.Pip.Count) packages" -ForegroundColor Green
        }
    }

    # npm
    if (Get-Command npm -ErrorAction SilentlyContinue) {
        Write-Host "  Capturing npm packages..." -ForegroundColor Gray
        $snapshot.Packages.Npm = @(Get-NpmPackages)
        Write-Host "    ✓ $($snapshot.Packages.Npm.Count) packages" -ForegroundColor Green
    }

    # Chocolatey
    if (Get-Command choco -ErrorAction SilentlyContinue) {
        Write-Host "  Capturing Chocolatey packages..." -ForegroundColor Gray
        $snapshot.Packages.Chocolatey = @(Get-ChocoPackages)
        Write-Host "    ✓ $($snapshot.Packages.Chocolatey.Count) packages" -ForegroundColor Green
    }

    # PowerShell Modules
    Write-Host "  Capturing PowerShell modules..." -ForegroundColor Gray
    $snapshot.Packages.PowerShellModules = @(Get-PowerShellModulesSnapshot)
    Write-Host "    ✓ $($snapshot.Packages.PowerShellModules.Count) modules" -ForegroundColor Green

    # VS Code Extensions
    if (Get-Command code -ErrorAction SilentlyContinue) {
        Write-Host "  Capturing VS Code extensions..." -ForegroundColor Gray
        try {
            $extensions = @((code --list-extensions --show-versions) 2>&1)
            $snapshot.Packages.VSCodeExtensions = @(
                $extensions | ForEach-Object {
                    if ($_ -match '^(.+)@(.+)$') {
                        [pscustomobject]@{
                            Name = $Matches[1]
                            Version = $Matches[2]
                        }
                    }
                }
            )
            Write-Host "    ✓ $($snapshot.Packages.VSCodeExtensions.Count) extensions" -ForegroundColor Green
        } catch {
            Write-Warning "Failed to capture VS Code extensions"
        }
    }

    # Docker Images (optional, can be large)
    if ($IncludeDocker -and (Get-Command docker -ErrorAction SilentlyContinue)) {
        Write-Host "  Capturing Docker images..." -ForegroundColor Gray
        try {
            $images = @((docker image ls --format "{{.Repository}}:{{.Tag}}:{{.ID}}") 2>&1)
            $snapshot.Packages.DockerImages = @(
                $images | ForEach-Object {
                    $parts = $_ -split ':'
                    if ($parts.Count -eq 3) {
                        [pscustomobject]@{
                            Repository = $parts[0]
                            Tag = $parts[1]
                            ImageId = $parts[2]
                        }
                    }
                }
            )
            Write-Host "    ✓ $($snapshot.Packages.DockerImages.Count) images" -ForegroundColor Green
        } catch {
            Write-Warning "Failed to capture Docker images"
        }
    }

    # Save snapshot to file
    $snapshotFile = Join-Path $script:SnapshotConfig.SnapshotDirectory "$snapshotName.json"

    try {
        $snapshot | ConvertTo-Json -Depth 10 | Set-Content $snapshotFile -Encoding UTF8
        Write-Verbose "Snapshot saved to: $snapshotFile"

        # Compress if enabled
        if ($script:SnapshotConfig.CompressionEnabled) {
            $archiveFile = "$snapshotFile.zip"
            if (Compress-Snapshot -SourcePath $snapshotFile -DestinationPath $archiveFile) {
                Remove-Item $snapshotFile -Force
                $snapshotFile = $archiveFile
            }
        }

        Write-Host ""
        Write-Host "✓ Snapshot created successfully" -ForegroundColor Green
        Write-Host "  File: $snapshotFile" -ForegroundColor Gray
        Write-Host "  Size: $([math]::Round((Get-Item $snapshotFile).Length / 1KB, 2)) KB" -ForegroundColor Gray
        Write-Host ""

        # Cleanup old snapshots
        Remove-OldSnapshots

        return [pscustomobject]@{
            Name = $snapshotName
            FilePath = $snapshotFile
            Timestamp = $snapshot.Timestamp
            TotalPackages = ($snapshot.Packages.Values | ForEach-Object { if ($_ -is [array]) { $_.Count } else { 0 } } | Measure-Object -Sum).Sum
        }
    }
    catch {
        Write-Error "Failed to save snapshot: $($_.Exception.Message)"
        throw
    }
}

<#
.SYNOPSIS
Get list of available snapshots

.DESCRIPTION
Returns all snapshots in the snapshot directory with metadata

.PARAMETER Latest
Return only the most recent snapshot

.PARAMETER Count
Number of recent snapshots to return

.EXAMPLE
Get-PackageSnapshots

.EXAMPLE
Get-PackageSnapshots -Latest

.EXAMPLE
Get-PackageSnapshots -Count 5
#>

function Get-PackageSnapshots {
    [CmdletBinding()]
    param(
        [switch]$Latest,
        [int]$Count = 0
    )

    if (-not (Test-Path $script:SnapshotConfig.SnapshotDirectory)) {
        Write-Warning "No snapshots directory found. Run Initialize-SnapshotManager first."
        return @()
    }

    $files = Get-ChildItem -Path $script:SnapshotConfig.SnapshotDirectory -Filter "*.json*" |
             Sort-Object LastWriteTime -Descending

    if ($Latest) {
        $files = $files | Select-Object -First 1
    } elseif ($Count -gt 0) {
        $files = $files | Select-Object -First $Count
    }

    $snapshots = foreach ($file in $files) {
        [pscustomobject]@{
            Name = $file.BaseName -replace '\.json$', ''
            FilePath = $file.FullName
            Timestamp = $file.LastWriteTime
            SizeKB = [math]::Round($file.Length / 1KB, 2)
            Compressed = $file.Extension -eq '.zip'
        }
    }

    return $snapshots
}

<#
.SYNOPSIS
Compare two snapshots or current state with a snapshot

.DESCRIPTION
Shows differences in package versions between snapshots

.PARAMETER ReferenceSnapshot
Name or path of reference snapshot (older)

.PARAMETER DifferenceSnapshot
Name or path of difference snapshot (newer). If omitted, compares with current state.

.EXAMPLE
Compare-PackageSnapshot -ReferenceSnapshot "snapshot_20260123_140000"

.EXAMPLE
Compare-PackageSnapshot -ReferenceSnapshot "before-update" -DifferenceSnapshot "after-update"

.OUTPUTS
PSCustomObject with comparison results
#>

function Compare-PackageSnapshot {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$ReferenceSnapshot,

        [string]$DifferenceSnapshot
    )

    Write-Host "Comparing package snapshots..." -ForegroundColor Cyan

    # Load reference snapshot
    $refFile = if (Test-Path $ReferenceSnapshot) {
        $ReferenceSnapshot
    } else {
        $found = Get-ChildItem -Path $script:SnapshotConfig.SnapshotDirectory -Filter "*$ReferenceSnapshot*" |
                 Select-Object -First 1
        if ($found) { $found.FullName } else { $null }
    }

    if (-not $refFile) {
        Write-Error "Reference snapshot not found: $ReferenceSnapshot"
        return
    }

    # TODO: Implement full comparison logic
    # This is a skeleton - full implementation would compare each package manager

    Write-Host "Reference: $refFile" -ForegroundColor Gray
    Write-Host "Difference: " -NoNewline -ForegroundColor Gray
    Write-Host $(if ($DifferenceSnapshot) { $DifferenceSnapshot } else { "Current state" }) -ForegroundColor Yellow

    Write-Warning "Full comparison functionality not yet implemented - coming in next version!"
}

<#
.SYNOPSIS
Restore packages to snapshot state

.DESCRIPTION
Attempts to downgrade/upgrade packages to match snapshot versions.
**USE WITH CAUTION** - this may break your system if dependencies conflict.

.PARAMETER SnapshotName
Name of snapshot to restore

.PARAMETER WhatIf
Preview changes without making them

.PARAMETER PackageManagers
Limit restore to specific package managers (e.g., "Winget", "Pip")

.EXAMPLE
Restore-PackageSnapshot -SnapshotName "before-update" -WhatIf

.EXAMPLE
Restore-PackageSnapshot -SnapshotName "snapshot_20260123" -PackageManagers "Winget"
#>

function Restore-PackageSnapshot {
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [Parameter(Mandatory)]
        [string]$SnapshotName,

        [string[]]$PackageManagers
    )

    Write-Warning "Restore functionality is experimental and may cause issues!"
    Write-Host "This will attempt to install/downgrade packages to match the snapshot." -ForegroundColor Yellow
    Write-Host ""

    $confirm = Read-Host "Are you sure you want to continue? (yes/NO)"
    if ($confirm -ne "yes") {
        Write-Host "Restore cancelled" -ForegroundColor Yellow
        return
    }

    # TODO: Implement restore logic
    # This is extremely complex and risky - needs careful implementation
    # - For each package manager
    # - For each package in snapshot
    # - Check if version differs
    # - Attempt to install specific version
    # - Handle errors gracefully

    Write-Warning "Full restore functionality not yet implemented - coming in v5.2!"
}

<#
.SYNOPSIS
Remove old snapshots beyond retention limit

.DESCRIPTION
Automatically called after creating new snapshots.
Removes oldest snapshots when count exceeds MaxSnapshots.

.EXAMPLE
Remove-OldSnapshots
#>

function Remove-OldSnapshots {
    [CmdletBinding()]
    param()

    $snapshots = Get-PackageSnapshots
    $maxSnapshots = $script:SnapshotConfig.MaxSnapshots

    if ($snapshots.Count -le $maxSnapshots) {
        Write-Verbose "Snapshot count ($($snapshots.Count)) within limit ($maxSnapshots)"
        return
    }

    $toRemove = $snapshots | Select-Object -Skip $maxSnapshots

    foreach ($snapshot in $toRemove) {
        try {
            Remove-Item $snapshot.FilePath -Force
            Write-Verbose "Removed old snapshot: $($snapshot.Name)"
        }
        catch {
            Write-Warning "Failed to remove snapshot $($snapshot.Name): $($_.Exception.Message)"
        }
    }

    Write-Host "Cleaned up $($toRemove.Count) old snapshots" -ForegroundColor Gray
}

# =============================================================================
# EXPORT PUBLIC FUNCTIONS
# =============================================================================

Export-ModuleMember -Function `
    Initialize-SnapshotManager, `
    New-PackageSnapshot, `
    Get-PackageSnapshots, `
    Compare-PackageSnapshot, `
    Restore-PackageSnapshot
