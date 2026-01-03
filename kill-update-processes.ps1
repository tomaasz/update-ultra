# Kill-Update-Processes.ps1 - Zabija procesy związane z update-ultra

Write-Host "Szukam procesów PowerShell i winget..." -ForegroundColor Cyan

# Find PowerShell processes running the update script
$processes = Get-Process -Name pwsh,powershell,winget -ErrorAction SilentlyContinue |
    Where-Object {
        $_.CommandLine -match 'Update-WingetAll' -or
        $_.MainWindowTitle -match 'Update-WingetAll' -or
        ($_.StartTime -and ((Get-Date) - $_.StartTime).TotalMinutes -lt 60)
    }

if ($processes) {
    Write-Host "`nZnaleziono procesy do zabicia:" -ForegroundColor Yellow
    $processes | Select-Object Id, ProcessName, StartTime, @{N='CPU(s)';E={[math]::Round($_.CPU,2)}} | Format-Table -AutoSize

    $confirm = Read-Host "`nCzy chcesz zabić te procesy? (T/N)"

    if ($confirm -eq 'T' -or $confirm -eq 't' -or $confirm -eq 'Y' -or $confirm -eq 'y') {
        foreach ($proc in $processes) {
            try {
                Write-Host "Zabijam proces PID $($proc.Id) ($($proc.ProcessName))..." -ForegroundColor Gray
                Stop-Process -Id $proc.Id -Force
                Write-Host "  ✓ Zabito PID $($proc.Id)" -ForegroundColor Green
            } catch {
                Write-Host "  ✗ Błąd zabijania PID $($proc.Id): $($_.Exception.Message)" -ForegroundColor Red
            }
        }
        Write-Host "`nGotowe!" -ForegroundColor Green
    } else {
        Write-Host "Anulowano." -ForegroundColor Yellow
    }
} else {
    Write-Host "Nie znaleziono procesów do zabicia." -ForegroundColor Green
}

Write-Host "`n=== Alternatywnie - zabij wszystkie procesy winget/PowerShell ===" -ForegroundColor Cyan
Write-Host "Wszystkie procesy PowerShell i winget:" -ForegroundColor Yellow
Get-Process -Name pwsh,powershell,winget -ErrorAction SilentlyContinue |
    Select-Object Id, ProcessName, StartTime, @{N='CPU(s)';E={[math]::Round($_.CPU,2)}} |
    Format-Table -AutoSize

Write-Host "`nAby zabić wszystkie:"
Write-Host "  Get-Process -Name winget -ErrorAction SilentlyContinue | Stop-Process -Force" -ForegroundColor White
Write-Host "  Get-Process -Name pwsh -ErrorAction SilentlyContinue | Stop-Process -Force" -ForegroundColor White
