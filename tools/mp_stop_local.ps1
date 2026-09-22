# Stop only RoweMod dual-local bridge processes, leaving games untouched.
$ErrorActionPreference = 'Stop'
$bridge = Join-Path $PSScriptRoot 'rowemod_mp.py'
$runs = Join-Path $env:TEMP 'RoweModMP\run-'
$found = Get-CimInstance Win32_Process | Where-Object {
    $_.Name -match '^python(?:w|3)?\.exe$' -and
    $_.CommandLine -and $_.CommandLine.Contains($bridge) -and
    $_.CommandLine.Contains($runs)
}
foreach ($process in $found) {
    Stop-Process -Id $process.ProcessId -ErrorAction SilentlyContinue
    Write-Host "Stopped RoweMod test bridge $($process.ProcessId)"
}
if (-not $found) { Write-Host 'No RoweMod dual-local bridges are running.' }
