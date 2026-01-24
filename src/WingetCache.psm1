# WingetCache.psm1
# Caching module for winget operations to improve performance

<#
.SYNOPSIS
Provides caching mechanisms for winget list and upgrade commands

.DESCRIPTION
Reduces repeated winget calls by caching results in memory and optionally on disk.
Supports TTL (Time To Live) for cache expiration and automatic invalidation.

.NOTES
Version: 1.0
Author: update-ultra team
#>

# Module-level cache storage
$script:MemoryCache = @{}
$script:CacheDirectory = "$env:TEMP\update-ultra-cache"
$script:DefaultTTL = 300 # 5 minutes

<#
.SYNOPSIS
Initializes the cache system

.DESCRIPTION
Creates cache directory and loads existing disk cache if enabled

.PARAMETER EnableDiskCache
Enable persistent disk-based caching

.PARAMETER CacheDirectory
Custom cache directory path

.PARAMETER TTL
Default Time To Live for cache entries in seconds
#>

function Initialize-WingetCache {
    [CmdletBinding()]
    param(
        [switch]$EnableDiskCache,
        [string]$CacheDirectory = $script:CacheDirectory,
        [int]$TTL = $script:DefaultTTL
    )

    $script:CacheDirectory = $CacheDirectory
    $script:DefaultTTL = $TTL

    if ($EnableDiskCache) {
        if (-not (Test-Path $script:CacheDirectory)) {
            New-Item -ItemType Directory -Path $script:CacheDirectory -Force | Out-Null
            Write-Verbose "Created cache directory: $script:CacheDirectory"
        }

        # Load existing cache from disk
        $cacheFiles = Get-ChildItem -Path $script:CacheDirectory -Filter "*.cache.json" -ErrorAction SilentlyContinue
        foreach ($file in $cacheFiles) {
            try {
                $cacheData = Get-Content $file.FullName -Raw | ConvertFrom-Json

                # Check if cache is still valid
                $age = (Get-Date) - [datetime]$cacheData.Timestamp
                if ($age.TotalSeconds -lt $TTL) {
                    $key = $file.BaseName -replace '\.cache$', ''
                    $script:MemoryCache[$key] = $cacheData
                    Write-Verbose "Loaded cache from disk: $key (age: $([math]::Round($age.TotalSeconds))s)"
                } else {
                    Remove-Item $file.FullName -Force -ErrorAction SilentlyContinue
                    Write-Verbose "Removed expired cache file: $($file.Name)"
                }
            }
            catch {
                Write-Warning "Failed to load cache file $($file.Name): $($_.Exception.Message)"
            }
        }
    }

    Write-Verbose "Cache initialized. Memory cache entries: $($script:MemoryCache.Count)"
}

<#
.SYNOPSIS
Gets cached data or executes command if cache miss

.DESCRIPTION
Checks memory cache first, then disk cache, then executes command if no valid cache found.

.PARAMETER Key
Cache key (usually command signature)

.PARAMETER ScriptBlock
Command to execute on cache miss

.PARAMETER TTL
Time To Live override for this specific cache entry

.PARAMETER Force
Force refresh cache even if valid entry exists

.EXAMPLE
$result = Get-CachedResult -Key "winget-list-all" -ScriptBlock { winget list --source winget }
#>

function Get-CachedResult {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Key,

        [Parameter(Mandatory)]
        [scriptblock]$ScriptBlock,

        [int]$TTL = $script:DefaultTTL,

        [switch]$Force
    )

    $sanitizedKey = $Key -replace '[\\/:*?"<>|]', '_'

    # Check memory cache first
    if (-not $Force -and $script:MemoryCache.ContainsKey($sanitizedKey)) {
        $cacheEntry = $script:MemoryCache[$sanitizedKey]
        $age = (Get-Date) - [datetime]$cacheEntry.Timestamp

        if ($age.TotalSeconds -lt $TTL) {
            Write-Verbose "Cache HIT (memory): $sanitizedKey (age: $([math]::Round($age.TotalSeconds))s)"
            return $cacheEntry.Data
        } else {
            Write-Verbose "Cache EXPIRED: $sanitizedKey (age: $([math]::Round($age.TotalSeconds))s, TTL: $TTL)"
            $script:MemoryCache.Remove($sanitizedKey)
        }
    }

    # Cache miss - execute command
    Write-Verbose "Cache MISS: $sanitizedKey - executing command..."
    $startTime = Get-Date

    try {
        $result = & $ScriptBlock
        $duration = ((Get-Date) - $startTime).TotalSeconds

        Write-Verbose "Command executed successfully in $([math]::Round($duration, 2))s"

        # Store in memory cache
        $cacheEntry = @{
            Key = $sanitizedKey
            Timestamp = Get-Date
            TTL = $TTL
            Data = $result
            Duration = $duration
        }

        $script:MemoryCache[$sanitizedKey] = $cacheEntry

        # Store in disk cache if directory exists
        if (Test-Path $script:CacheDirectory) {
            try {
                $cacheFile = Join-Path $script:CacheDirectory "$sanitizedKey.cache.json"
                $cacheEntry | ConvertTo-Json -Depth 10 | Set-Content $cacheFile -Encoding UTF8
                Write-Verbose "Saved to disk cache: $cacheFile"
            }
            catch {
                Write-Warning "Failed to save disk cache: $($_.Exception.Message)"
            }
        }

        return $result
    }
    catch {
        Write-Error "Failed to execute command for cache key '$sanitizedKey': $($_.Exception.Message)"
        throw
    }
}

<#
.SYNOPSIS
Clears cache for specific key or all cache

.PARAMETER Key
Specific cache key to clear (optional)

.PARAMETER All
Clear all cache entries

.PARAMETER DiskOnly
Only clear disk cache, keep memory cache

.EXAMPLE
Clear-WingetCache -All
Clear-WingetCache -Key "winget-list-all"
#>

function Clear-WingetCache {
    [CmdletBinding()]
    param(
        [string]$Key,
        [switch]$All,
        [switch]$DiskOnly
    )

    if ($All) {
        # Clear memory cache
        if (-not $DiskOnly) {
            $count = $script:MemoryCache.Count
            $script:MemoryCache.Clear()
            Write-Verbose "Cleared $count memory cache entries"
        }

        # Clear disk cache
        if (Test-Path $script:CacheDirectory) {
            $files = Get-ChildItem -Path $script:CacheDirectory -Filter "*.cache.json"
            foreach ($file in $files) {
                Remove-Item $file.FullName -Force
            }
            Write-Verbose "Cleared $($files.Count) disk cache files"
        }

        Write-Host "Cache cleared successfully" -ForegroundColor Green
    }
    elseif ($Key) {
        $sanitizedKey = $Key -replace '[\\/:*?"<>|]', '_'

        # Clear from memory
        if (-not $DiskOnly -and $script:MemoryCache.ContainsKey($sanitizedKey)) {
            $script:MemoryCache.Remove($sanitizedKey)
            Write-Verbose "Removed from memory cache: $sanitizedKey"
        }

        # Clear from disk
        $cacheFile = Join-Path $script:CacheDirectory "$sanitizedKey.cache.json"
        if (Test-Path $cacheFile) {
            Remove-Item $cacheFile -Force
            Write-Verbose "Removed from disk cache: $cacheFile"
        }

        Write-Host "Cache entry cleared: $Key" -ForegroundColor Green
    }
    else {
        Write-Warning "Specify -Key or -All parameter"
    }
}

<#
.SYNOPSIS
Gets cache statistics

.DESCRIPTION
Returns information about cache usage, hit rate, and storage

.EXAMPLE
Get-CacheStatistics
#>

function Get-CacheStatistics {
    [CmdletBinding()]
    param()

    $stats = [ordered]@{
        MemoryEntries = $script:MemoryCache.Count
        DiskEntries = 0
        TotalSizeKB = 0
        OldestEntry = $null
        NewestEntry = $null
        AverageAge = 0
    }

    # Get disk cache info
    if (Test-Path $script:CacheDirectory) {
        $files = Get-ChildItem -Path $script:CacheDirectory -Filter "*.cache.json"
        $stats.DiskEntries = $files.Count

        if ($files.Count -gt 0) {
            $stats.TotalSizeKB = [math]::Round(($files | Measure-Object -Property Length -Sum).Sum / 1KB, 2)
            $stats.OldestEntry = ($files | Sort-Object LastWriteTime | Select-Object -First 1).LastWriteTime
            $stats.NewestEntry = ($files | Sort-Object LastWriteTime -Descending | Select-Object -First 1).LastWriteTime
        }
    }

    # Calculate average age from memory cache
    if ($script:MemoryCache.Count -gt 0) {
        $ages = $script:MemoryCache.Values | ForEach-Object {
            ((Get-Date) - [datetime]$_.Timestamp).TotalSeconds
        }
        $stats.AverageAge = [math]::Round(($ages | Measure-Object -Average).Average, 1)
    }

    return [pscustomobject]$stats
}

<#
.SYNOPSIS
Specialized function to cache winget list output

.DESCRIPTION
Caches the output of 'winget list --source winget' with intelligent key generation

.PARAMETER Force
Force refresh cache

.PARAMETER TTL
Override default TTL

.EXAMPLE
$packages = Get-CachedWingetList
#>

function Get-CachedWingetList {
    [CmdletBinding()]
    param(
        [switch]$Force,
        [int]$TTL = 600  # 10 minutes default for list
    )

    $key = "winget-list-winget"

    return Get-CachedResult -Key $key -TTL $TTL -Force:$Force -ScriptBlock {
        $output = @()
        $exitCode = 0

        try {
            $output = @((winget list --source winget) 2>&1)
            $exitCode = $LASTEXITCODE
        }
        catch {
            $exitCode = 1
        }

        return [pscustomobject]@{
            Output = $output
            ExitCode = $exitCode
            Timestamp = Get-Date
        }
    }
}

<#
.SYNOPSIS
Specialized function to cache winget upgrade output

.DESCRIPTION
Caches the output of 'winget upgrade' with intelligent key generation

.PARAMETER Force
Force refresh cache

.PARAMETER TTL
Override default TTL (shorter for upgrade list as it changes frequently)

.EXAMPLE
$upgrades = Get-CachedWingetUpgrade
#>

function Get-CachedWingetUpgrade {
    [CmdletBinding()]
    param(
        [switch]$Force,
        [int]$TTL = 300  # 5 minutes default for upgrade list
    )

    $key = "winget-upgrade"

    return Get-CachedResult -Key $key -TTL $TTL -Force:$Force -ScriptBlock {
        $output = @()
        $exitCode = 0

        try {
            $output = @((winget upgrade) 2>&1)
            $exitCode = $LASTEXITCODE
        }
        catch {
            $exitCode = 1
        }

        return [pscustomobject]@{
            Output = $output
            ExitCode = $exitCode
            Timestamp = Get-Date
        }
    }
}

<#
.SYNOPSIS
Invalidates cache after significant operations

.DESCRIPTION
Call this after operations that change package state (install, upgrade, uninstall)

.EXAMPLE
Invoke-CacheInvalidation -Reason "winget source update"
#>

function Invoke-CacheInvalidation {
    [CmdletBinding()]
    param(
        [string]$Reason = "Manual invalidation"
    )

    Write-Verbose "Cache invalidation triggered: $Reason"

    # Invalidate winget-related caches
    $wingetKeys = $script:MemoryCache.Keys | Where-Object { $_ -like "winget-*" }

    foreach ($key in $wingetKeys) {
        $script:MemoryCache.Remove($key)
        Write-Verbose "Invalidated cache key: $key"
    }

    Write-Host "Cache invalidated: $Reason" -ForegroundColor Yellow
}

# Export public functions
Export-ModuleMember -Function `
    Initialize-WingetCache, `
    Get-CachedResult, `
    Clear-WingetCache, `
    Get-CacheStatistics, `
    Get-CachedWingetList, `
    Get-CachedWingetUpgrade, `
    Invoke-CacheInvalidation
