# ParallelExecution.psm1
# Module for parallel execution of independent update tasks

<#
.SYNOPSIS
Executes multiple update steps in parallel using PowerShell jobs

.DESCRIPTION
Groups independent update steps and runs them concurrently to improve performance.
Falls back to sequential execution if ThreadJob module is not available.

.PARAMETER StepGroups
Array of step group definitions. Each group contains Name, ScriptBlock, and Skip parameters.

.EXAMPLE
$groups = @(
    @{ Name = "Winget"; Body = { ... }; Skip = $false },
    @{ Name = "Pip"; Body = { ... }; Skip = $false }
)
Invoke-ParallelSteps -StepGroups $groups
#>

function Invoke-ParallelSteps {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [array]$StepGroups,

        [Parameter()]
        [int]$MaxParallel = 4,

        [Parameter()]
        [switch]$Sequential
    )

    $results = New-Object System.Collections.Generic.List[object]

    # Check if ThreadJob module is available
    $hasThreadJob = $null -ne (Get-Module -ListAvailable -Name ThreadJob)

    if ($Sequential -or -not $hasThreadJob) {
        if (-not $hasThreadJob) {
            Write-Host "  ThreadJob module nie jest dostępny - uruchamianie sekwencyjne" -ForegroundColor Yellow
            Write-Host "  Zainstaluj ThreadJob: Install-Module -Name ThreadJob -Scope CurrentUser" -ForegroundColor DarkGray
        }

        # Sequential fallback
        foreach ($group in $StepGroups) {
            $result = Invoke-Step -Name $group.Name -Body $group.Body -Skip:$group.Skip
            $results.Add($result)
        }
        return $results
    }

    # Import ThreadJob if needed
    if (-not (Get-Module ThreadJob)) {
        Import-Module ThreadJob -ErrorAction SilentlyContinue
    }

    # Create jobs for each non-skipped group
    $jobs = @()
    $skippedGroups = @()

    foreach ($group in $StepGroups) {
        if ($group.Skip) {
            $skippedGroups += $group
            continue
        }

        Write-Host "  Uruchamianie w tle: $($group.Name)..." -ForegroundColor Cyan

        # Start background job
        $job = Start-ThreadJob -ScriptBlock {
            param($GroupName, $GroupBody, $ModulePath)

            # Import required functions in job context
            if ($ModulePath -and (Test-Path $ModulePath)) {
                . $ModulePath
            }

            # Execute step
            try {
                $result = & $GroupBody
                return $result
            }
            catch {
                return @{
                    Name = $GroupName
                    Status = "FAIL"
                    Error = $_.Exception.Message
                }
            }
        } -ArgumentList $group.Name, $group.Body, $script:MainScriptPath

        $jobs += @{
            Job = $job
            Name = $group.Name
        }
    }

    # Wait for jobs with progress indicator
    Write-Host ""
    Write-Host "  Oczekiwanie na zakończenie zadań równoległych..." -ForegroundColor Gray

    $completed = 0
    $total = $jobs.Count

    while ($jobs.Count -gt 0) {
        $finished = @()

        foreach ($jobInfo in $jobs) {
            if ($jobInfo.Job.State -eq 'Completed' -or $jobInfo.Job.State -eq 'Failed') {
                $completed++
                $percent = [math]::Round(($completed / $total) * 100)
                Write-Progress -Activity "Równoległe aktualizacje" -Status "Ukończono: $completed / $total" -PercentComplete $percent

                # Receive job results
                $result = Receive-Job -Job $jobInfo.Job -ErrorAction Continue
                Remove-Job -Job $jobInfo.Job -Force

                if ($result) {
                    $results.Add($result)
                    Write-Host "  ✓ Ukończono: $($jobInfo.Name)" -ForegroundColor Green
                } else {
                    Write-Host "  ✗ Błąd: $($jobInfo.Name)" -ForegroundColor Red
                }

                $finished += $jobInfo
            }
        }

        # Remove finished jobs from tracking list
        foreach ($f in $finished) {
            $jobs = @($jobs | Where-Object { $_.Job.Id -ne $f.Job.Id })
        }

        if ($jobs.Count -gt 0) {
            Start-Sleep -Milliseconds 500
        }
    }

    Write-Progress -Activity "Równoległe aktualizacje" -Completed
    Write-Host "  Wszystkie zadania równoległe zakończone" -ForegroundColor Green
    Write-Host ""

    # Process skipped groups sequentially
    foreach ($group in $skippedGroups) {
        $result = Invoke-Step -Name $group.Name -Body $group.Body -Skip:$true
        $results.Add($result)
    }

    return $results
}

<#
.SYNOPSIS
Groups update steps by dependency to optimize parallel execution

.DESCRIPTION
Analyzes dependencies between update steps and creates optimal groups for parallel execution.
Returns array of step groups where each group can run independently.

.EXAMPLE
$groups = Get-OptimalStepGroups -AllSteps $allSteps
#>

function Get-OptimalStepGroups {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [hashtable]$Steps
    )

    # Define step groups by independence
    # Group 1: Package managers (fully independent)
    $packageManagers = @('Winget', 'Chocolatey', 'Scoop', 'MS Store Apps')

    # Group 2: Language-specific tools (independent from package managers)
    $languageTools = @('Python/Pip', 'npm (global)', 'pipx', 'Cargo (Rust)', 'Ruby Gems', 'Composer (PHP)', 'Yarn (global)', 'pnpm (global)', 'Go Tools')

    # Group 3: Development tools (independent)
    $devTools = @('VS Code Extensions', 'PowerShell Modules')

    # Group 4: System services (need sequential due to potential conflicts)
    $systemServices = @('Docker Images', 'WSL', 'WSL Distros (apt/yum/pacman)')

    # Group 5: Git repos (need sequential due to file locks)
    $sequential = @('Git Repos')

    return @{
        PackageManagers = $packageManagers
        LanguageTools = $languageTools
        DevTools = $devTools
        SystemServices = $systemServices
        Sequential = $sequential
    }
}

<#
.SYNOPSIS
Estimates time savings from parallel execution

.DESCRIPTION
Analyzes previous execution times and estimates potential time savings from parallelization.

.EXAMPLE
$savings = Get-ParallelTimeSavings -PreviousResults $results
#>

function Get-ParallelTimeSavings {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [array]$PreviousResults,

        [Parameter()]
        [int]$MaxParallel = 4
    )

    if ($PreviousResults.Count -eq 0) {
        return @{
            SequentialTime = 0
            ParallelTime = 0
            TimeSaved = 0
            PercentSaved = 0
        }
    }

    # Calculate total sequential time
    $sequentialTime = ($PreviousResults | Measure-Object -Property DurationS -Sum).Sum

    # Group by optimal groups
    $groups = Get-OptimalStepGroups -Steps @{}

    $groupTimes = @{
        PackageManagers = 0
        LanguageTools = 0
        DevTools = 0
        SystemServices = 0
        Sequential = 0
    }

    foreach ($result in $PreviousResults) {
        $groupFound = $false
        foreach ($groupName in $groupTimes.Keys) {
            if ($groups[$groupName] -contains $result.Name) {
                # In parallel group, use max time (bottleneck)
                if ($result.DurationS -gt $groupTimes[$groupName]) {
                    $groupTimes[$groupName] = $result.DurationS
                }
                $groupFound = $true
                break
            }
        }
    }

    # Calculate parallel time (sum of group max times)
    $parallelTime = ($groupTimes.Values | Measure-Object -Sum).Sum
    $timeSaved = $sequentialTime - $parallelTime
    $percentSaved = if ($sequentialTime -gt 0) { [math]::Round(($timeSaved / $sequentialTime) * 100, 1) } else { 0 }

    return @{
        SequentialTime = $sequentialTime
        ParallelTime = $parallelTime
        TimeSaved = $timeSaved
        PercentSaved = $percentSaved
    }
}

Export-ModuleMember -Function Invoke-ParallelSteps, Get-OptimalStepGroups, Get-ParallelTimeSavings
