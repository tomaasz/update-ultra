# DeltaUpdateManager.psm1
# Moduł do inteligentnych delta updates - aktualizuje tylko zmienione pakiety

<#
.SYNOPSIS
Moduł zarządzania delta updates dla Update-Ultra

.DESCRIPTION
Umożliwia inteligentne aktualizacje tylko zmienionych pakietów poprzez:
- Zapisywanie baseline state (snapshoty zainstalowanych pakietów)
- Porównywanie z poprzednim stanem
- Aktualizację tylko pakietów które się zmieniły

.NOTES
Wymaga: PowerShell 5.1+
Kompatybilność: Windows 10/11, Windows Server 2016+
Baseline directory: %APPDATA%\update-ultra\delta-state
#>

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

#region Module State
$script:ModuleVersion = "1.0.0"
$script:ModuleName = "DeltaUpdateManager"
$script:DeltaStateDir = Join-Path $env:APPDATA "update-ultra\delta-state"
$script:BaselineMaxAge = 30  # dni
$script:CurrentBaseline = $null
#endregion

#region Private Functions

function Write-Log {
    param(
        [string]$Message,
        [ValidateSet('INFO', 'WARN', 'ERROR', 'DEBUG')]
        [string]$Level = 'INFO'
    )

    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $color = switch ($Level) {
        'INFO'  { 'White' }
        'WARN'  { 'Yellow' }
        'ERROR' { 'Red' }
        'DEBUG' { 'DarkGray' }
    }

    Write-Host "[$timestamp] [$Level] $Message" -ForegroundColor $color
}

function Get-LatestBaseline {
    <#
    .SYNOPSIS
    Pobiera najnowszy baseline file
    #>
    if (-not (Test-Path $script:DeltaStateDir)) {
        return $null
    }

    $baselines = Get-ChildItem -Path $script:DeltaStateDir -Filter "baseline-*.json" |
        Sort-Object LastWriteTime -Descending |
        Select-Object -First 1

    return $baselines
}

function Test-BaselineAge {
    <#
    .SYNOPSIS
    Sprawdza czy baseline nie jest za stary
    #>
    param([System.IO.FileInfo]$BaselineFile)

    if (-not $BaselineFile) {
        return $false
    }

    $age = (Get-Date) - $BaselineFile.LastWriteTime
    return ($age.Days -le $script:BaselineMaxAge)
}

function ConvertTo-PackageKey {
    <#
    .SYNOPSIS
    Konwertuje package info do klucza (Id lub Name)
    #>
    param($Package)

    if ($Package.Id) {
        return $Package.Id
    }
    elseif ($Package.Name) {
        return $Package.Name
    }
    else {
        return $null
    }
}

#endregion

#region Public Functions

function Initialize-DeltaUpdateManager {
    <#
    .SYNOPSIS
    Inicjalizuje system delta updates

    .DESCRIPTION
    Tworzy katalog dla baseline state jeśli nie istnieje.
    Katalog: %APPDATA%\update-ultra\delta-state

    .EXAMPLE
    Initialize-DeltaUpdateManager
    #>
    [CmdletBinding()]
    param()

    Write-Log "Inicjalizacja DeltaUpdateManager v$script:ModuleVersion" -Level DEBUG

    if (-not (Test-Path $script:DeltaStateDir)) {
        New-Item -ItemType Directory -Path $script:DeltaStateDir -Force | Out-Null
        Write-Log "Utworzono katalog delta state: $script:DeltaStateDir" -Level INFO
    }

    Write-Log "Delta state directory: $script:DeltaStateDir" -Level DEBUG
}

function Get-CurrentPackageState {
    <#
    .SYNOPSIS
    Zbiera aktualny stan pakietów ze wszystkich źródeł

    .DESCRIPTION
    Wykonuje komendy winget/npm/pip aby pobrać listę zainstalowanych pakietów
    i ich wersje. Zwraca hashtable z kluczami: Winget, npm, pip

    .PARAMETER Sources
    Lista źródeł do sprawdzenia (domyślnie: Winget, npm, pip)

    .EXAMPLE
    $state = Get-CurrentPackageState -Sources @('Winget', 'npm')

    .OUTPUTS
    Hashtable z pakietami per source
    #>
    [CmdletBinding()]
    param(
        [string[]]$Sources = @('Winget', 'npm', 'pip')
    )

    Write-Log "Zbieranie aktualnego stanu pakietów..." -Level INFO

    $state = @{}

    foreach ($source in $Sources) {
        Write-Log "Sprawdzanie źródła: $source" -Level DEBUG

        $packages = @()

        switch ($source) {
            'Winget' {
                if (Get-Command winget -ErrorAction SilentlyContinue) {
                    try {
                        $output = @((winget list) 2>&1)

                        foreach ($line in $output) {
                            # Parse winget list output (format: Name  Id  Version  Available  Source)
                            # Skip headers, separators, and summary lines
                            if ($line -match '^\s*-+\s*$' -or
                                $line -match '^Name\s+' -or
                                $line -match 'upgrades available' -or
                                [string]::IsNullOrWhiteSpace($line)) {
                                continue
                            }

                            # Match lines with package info (ID.format like Vendor.Product)
                            if ($line -match '\s{2,}([A-Za-z0-9\.\-_]+\.[A-Za-z0-9\.\-_]+)\s{2,}([\d\.]+)') {
                                $packages += @{
                                    Id = $Matches[1]
                                    Version = $Matches[2]
                                }
                            }
                        }

                        Write-Log "Znaleziono $($packages.Count) pakietów Winget" -Level DEBUG
                    }
                    catch {
                        Write-Log "Błąd podczas zbierania pakietów Winget: $($_.Exception.Message)" -Level WARN
                    }
                }
            }

            'npm' {
                if (Get-Command npm -ErrorAction SilentlyContinue) {
                    try {
                        $output = @((npm list -g --depth=0 --json) 2>&1 | Out-String)
                        $json = $output | ConvertFrom-Json

                        if ($json.dependencies) {
                            foreach ($pkg in $json.dependencies.PSObject.Properties) {
                                $packages += @{
                                    Name = $pkg.Name
                                    Version = $pkg.Value.version
                                }
                            }
                        }

                        Write-Log "Znaleziono $($packages.Count) pakietów npm" -Level DEBUG
                    }
                    catch {
                        Write-Log "Błąd podczas zbierania pakietów npm: $($_.Exception.Message)" -Level WARN
                    }
                }
            }

            'pip' {
                if (Get-Command pip -ErrorAction SilentlyContinue) {
                    try {
                        $output = @((pip list --format=json) 2>&1 | Out-String)
                        $json = $output | ConvertFrom-Json

                        foreach ($pkg in $json) {
                            $packages += @{
                                Name = $pkg.name
                                Version = $pkg.version
                            }
                        }

                        Write-Log "Znaleziono $($packages.Count) pakietów pip" -Level DEBUG
                    }
                    catch {
                        Write-Log "Błąd podczas zbierania pakietów pip: $($_.Exception.Message)" -Level WARN
                    }
                }
            }
        }

        $state[$source] = $packages
    }

    return $state
}

function Compare-PackageState {
    <#
    .SYNOPSIS
    Porównuje current state z previous baseline

    .DESCRIPTION
    Wykrywa różnice między aktualnym stanem pakietów a poprzednim baseline:
    - Added: nowe pakiety
    - Removed: usunięte pakiety
    - Updated: pakiety z inną wersją

    .PARAMETER CurrentState
    Hashtable z aktualnym stanem (z Get-CurrentPackageState)

    .PARAMETER BaselineState
    Hashtable z baseline stanem (z pliku JSON)

    .EXAMPLE
    $diff = Compare-PackageState -CurrentState $current -BaselineState $baseline

    .OUTPUTS
    Hashtable z diff per source (Added, Removed, Updated)
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [hashtable]$CurrentState,

        [Parameter(Mandatory)]
        [hashtable]$BaselineState
    )

    Write-Log "Porównywanie stanów pakietów..." -Level INFO

    $diff = @{}

    foreach ($source in $CurrentState.Keys) {
        Write-Log "Porównywanie źródła: $source" -Level DEBUG

        $currentPkgs = $CurrentState[$source]
        $baselinePkgs = if ($BaselineState.ContainsKey($source)) { $BaselineState[$source] } else { @() }

        # Build lookup tables
        $currentLookup = @{}
        foreach ($pkg in $currentPkgs) {
            $key = ConvertTo-PackageKey $pkg
            if ($key) {
                $currentLookup[$key] = $pkg
            }
        }

        $baselineLookup = @{}
        foreach ($pkg in $baselinePkgs) {
            $key = ConvertTo-PackageKey $pkg
            if ($key) {
                $baselineLookup[$key] = $pkg
            }
        }

        # Find added packages
        $added = @()
        foreach ($key in $currentLookup.Keys) {
            if (-not $baselineLookup.ContainsKey($key)) {
                $added += $key
            }
        }

        # Find removed packages
        $removed = @()
        foreach ($key in $baselineLookup.Keys) {
            if (-not $currentLookup.ContainsKey($key)) {
                $removed += $key
            }
        }

        # Find updated packages (version changed)
        $updated = @()
        foreach ($key in $currentLookup.Keys) {
            if ($baselineLookup.ContainsKey($key)) {
                $currentVer = $currentLookup[$key].Version
                $baselineVer = $baselineLookup[$key].Version

                if ($currentVer -ne $baselineVer) {
                    $updated += @{
                        Id = $key
                        OldVersion = $baselineVer
                        NewVersion = $currentVer
                    }
                }
            }
        }

        $diff[$source] = @{
            Added = $added
            Removed = $removed
            Updated = $updated
        }

        Write-Log "  $source: +$($added.Count) -$($removed.Count) ~$($updated.Count)" -Level DEBUG
    }

    return $diff
}

function Get-DeltaUpdateTargets {
    <#
    .SYNOPSIS
    Na podstawie diff zwraca listę pakietów do aktualizacji

    .DESCRIPTION
    Zwraca tylko pakiety Updated (które mają dostępną nowszą wersję).
    Opcjonalnie może też zwrócić Added (nowo zainstalowane pakiety).

    .PARAMETER Diff
    Diff object z Compare-PackageState

    .PARAMETER Source
    Nazwa źródła (Winget, npm, pip)

    .PARAMETER IncludeNew
    Czy dołączyć nowo dodane pakiety

    .EXAMPLE
    $targets = Get-DeltaUpdateTargets -Diff $diff -Source "Winget"

    .OUTPUTS
    Lista ID/nazw pakietów do aktualizacji
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [hashtable]$Diff,

        [Parameter(Mandatory)]
        [string]$Source,

        [switch]$IncludeNew
    )

    if (-not $Diff.ContainsKey($Source)) {
        Write-Log "Źródło $Source nie istnieje w diff" -Level WARN
        return @()
    }

    $targets = @()

    # Always include updated packages
    foreach ($update in $Diff[$Source].Updated) {
        $targets += $update.Id
    }

    # Optionally include new packages
    if ($IncludeNew) {
        foreach ($added in $Diff[$Source].Added) {
            $targets += $added
        }
    }

    Write-Log "Delta targets dla $Source`: $($targets.Count) pakietów" -Level INFO

    return $targets
}

function Save-PackageStateBaseline {
    <#
    .SYNOPSIS
    Zapisuje current state jako nowy baseline

    .DESCRIPTION
    Zapisuje stan pakietów jako JSON w formacie:
    %APPDATA%\update-ultra\delta-state\baseline-{timestamp}.json

    .PARAMETER State
    Hashtable ze stanem pakietów (z Get-CurrentPackageState)

    .PARAMETER KeepLast
    Ile ostatnich baseline'ów zachować (starsze są usuwane)

    .EXAMPLE
    Save-PackageStateBaseline -State $state -KeepLast 10

    .OUTPUTS
    Ścieżka do zapisanego baseline file
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [hashtable]$State,

        [int]$KeepLast = 10
    )

    # Ensure delta state directory exists
    if (-not (Test-Path $script:DeltaStateDir)) {
        New-Item -ItemType Directory -Path $script:DeltaStateDir -Force | Out-Null
    }

    $timestamp = Get-Date -Format "yyyyMMdd_HHmmss"
    $baselinePath = Join-Path $script:DeltaStateDir "baseline-$timestamp.json"

    Write-Log "Zapisywanie baseline: $baselinePath" -Level INFO

    try {
        # Add metadata
        $baseline = @{
            Timestamp = (Get-Date).ToString("o")
            Version = $script:ModuleVersion
            State = $State
        }

        $json = $baseline | ConvertTo-Json -Depth 10
        $json | Out-File -FilePath $baselinePath -Encoding UTF8

        Write-Log "Baseline zapisany pomyślnie" -Level INFO

        # Cleanup old baselines
        $allBaselines = Get-ChildItem -Path $script:DeltaStateDir -Filter "baseline-*.json" |
            Sort-Object LastWriteTime -Descending

        if ($allBaselines.Count -gt $KeepLast) {
            $toRemove = $allBaselines | Select-Object -Skip $KeepLast

            foreach ($old in $toRemove) {
                Write-Log "Usuwanie starego baseline: $($old.Name)" -Level DEBUG
                Remove-Item $old.FullName -Force
            }
        }

        return $baselinePath
    }
    catch {
        Write-Log "Błąd podczas zapisywania baseline: $($_.Exception.Message)" -Level ERROR
        throw
    }
}

function Get-BaselineState {
    <#
    .SYNOPSIS
    Wczytuje ostatni baseline state

    .DESCRIPTION
    Wczytuje najnowszy baseline JSON i zwraca stan pakietów.
    Jeśli baseline nie istnieje lub jest za stary, zwraca null.

    .PARAMETER MaxAge
    Maksymalny wiek baseline w dniach (domyślnie: 30)

    .EXAMPLE
    $baseline = Get-BaselineState -MaxAge 7

    .OUTPUTS
    Hashtable ze stanem pakietów lub null
    #>
    [CmdletBinding()]
    param(
        [int]$MaxAge = 30
    )

    $baselineFile = Get-LatestBaseline

    if (-not $baselineFile) {
        Write-Log "Brak baseline - pierwszy run" -Level INFO
        return $null
    }

    # Check age
    $age = (Get-Date) - $baselineFile.LastWriteTime

    if ($age.Days -gt $MaxAge) {
        Write-Log "Baseline za stary ($($age.Days) dni) - wykonaj full update" -Level WARN
        return $null
    }

    Write-Log "Wczytywanie baseline: $($baselineFile.Name) (wiek: $($age.Days) dni)" -Level INFO

    try {
        $json = Get-Content $baselineFile.FullName -Raw | ConvertFrom-Json

        if ($json.State) {
            # Convert PSCustomObject to hashtable
            $state = @{}
            foreach ($prop in $json.State.PSObject.Properties) {
                $state[$prop.Name] = $prop.Value
            }

            return $state
        }
        else {
            Write-Log "Baseline ma nieprawidłową strukturę" -Level WARN
            return $null
        }
    }
    catch {
        Write-Log "Błąd podczas wczytywania baseline: $($_.Exception.Message)" -Level ERROR
        return $null
    }
}

function Invoke-DeltaUpdate {
    <#
    .SYNOPSIS
    Główna funkcja orchestrująca delta update process

    .DESCRIPTION
    Wykonuje pełny cykl delta update:
    1. Wczytuje previous baseline
    2. Zbiera current state
    3. Porównuje i generuje diff
    4. Zwraca listę pakietów do aktualizacji
    5. (Po aktualizacji) Zapisuje nowy baseline

    .PARAMETER Sources
    Lista źródeł do sprawdzenia

    .PARAMETER IncludeNew
    Czy aktualizować nowo dodane pakiety

    .PARAMETER SaveBaseline
    Czy zapisać nowy baseline po zebraniu stanu

    .EXAMPLE
    $result = Invoke-DeltaUpdate -Sources @('Winget', 'npm')

    .OUTPUTS
    PSCustomObject z właściwościami:
    - HasBaseline: czy baseline istniał
    - CurrentState: aktualny stan pakietów
    - Diff: różnice vs baseline
    - Targets: hashtable z listami pakietów do aktualizacji per source
    #>
    [CmdletBinding()]
    param(
        [string[]]$Sources = @('Winget', 'npm', 'pip'),
        [switch]$IncludeNew,
        [switch]$SaveBaseline
    )

    Write-Log "Rozpoczynam delta update process..." -Level INFO

    # Step 1: Load previous baseline
    $baselineState = Get-BaselineState

    # Step 2: Get current state
    $currentState = Get-CurrentPackageState -Sources $Sources

    # Step 3: Compare (if baseline exists)
    $hasBaseline = ($null -ne $baselineState)
    $diff = $null
    $targets = @{}

    if ($hasBaseline) {
        $diff = Compare-PackageState -CurrentState $currentState -BaselineState $baselineState

        # Step 4: Get update targets per source
        foreach ($source in $Sources) {
            $targets[$source] = Get-DeltaUpdateTargets -Diff $diff -Source $source -IncludeNew:$IncludeNew
        }
    }
    else {
        Write-Log "Brak baseline - wykonaj full update wszystkich pakietów" -Level WARN

        # No baseline = full update
        foreach ($source in $Sources) {
            if ($currentState.ContainsKey($source)) {
                $targets[$source] = $currentState[$source] | ForEach-Object {
                    ConvertTo-PackageKey $_
                } | Where-Object { $_ -ne $null }
            }
        }
    }

    # Step 5: Save new baseline (if requested)
    if ($SaveBaseline) {
        Save-PackageStateBaseline -State $currentState | Out-Null
    }

    # Return result
    return [PSCustomObject]@{
        HasBaseline = $hasBaseline
        CurrentState = $currentState
        Diff = $diff
        Targets = $targets
    }
}

function Clear-DeltaBaselines {
    <#
    .SYNOPSIS
    Usuwa wszystkie baseline files

    .DESCRIPTION
    Czyści katalog delta state - usuwa wszystkie baseline JSON files.
    Użyteczne do reset delta update system.

    .EXAMPLE
    Clear-DeltaBaselines
    #>
    [CmdletBinding(SupportsShouldProcess)]
    param()

    if (-not (Test-Path $script:DeltaStateDir)) {
        Write-Log "Katalog delta state nie istnieje" -Level WARN
        return
    }

    $baselines = Get-ChildItem -Path $script:DeltaStateDir -Filter "baseline-*.json"

    if ($baselines.Count -eq 0) {
        Write-Log "Brak baseline files do usunięcia" -Level INFO
        return
    }

    if ($PSCmdlet.ShouldProcess("$($baselines.Count) baseline files", "Usunięcie")) {
        foreach ($file in $baselines) {
            Remove-Item $file.FullName -Force
            Write-Log "Usunięto: $($file.Name)" -Level DEBUG
        }

        Write-Log "Usunięto $($baselines.Count) baseline files" -Level INFO
    }
}

#endregion

#region Module Initialization

Write-Verbose "DeltaUpdateManager v$script:ModuleVersion loaded"
Write-Verbose "Delta state directory: $script:DeltaStateDir"

#endregion

# Export functions
Export-ModuleMember -Function @(
    'Initialize-DeltaUpdateManager',
    'Get-CurrentPackageState',
    'Compare-PackageState',
    'Get-DeltaUpdateTargets',
    'Save-PackageStateBaseline',
    'Get-BaselineState',
    'Invoke-DeltaUpdate',
    'Clear-DeltaBaselines'
)
