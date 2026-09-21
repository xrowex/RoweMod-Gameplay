# Launch two local Rollout Inline windows + two MP bridges (same PC).
# Requires: Steam install, UE4SS + RoweModGameplay already installed (install.ps1).
# Steam often blocks a second library launch — we start the shipping exe directly.
#
# Usage:
#   powershell -ExecutionPolicy Bypass -File tools\mp_dual_local.ps1
#   tools\mp_dual_local.cmd

$ErrorActionPreference = "Stop"
$toolsDir = $PSScriptRoot
$here = (Resolve-Path (Join-Path $toolsDir "..")).Path

function Get-SteamLibraries {
    $libs = [System.Collections.Generic.List[string]]::new()
    $steam = $null
    foreach ($key in @("HKCU:\Software\Valve\Steam", "HKLM:\SOFTWARE\WOW6432Node\Valve\Steam")) {
        if (Test-Path $key) {
            $steam = (Get-ItemProperty $key -ErrorAction SilentlyContinue).SteamPath
            if ($steam) { break }
        }
    }
    if (-not $steam) {
        foreach ($guess in @("${env:ProgramFiles(x86)}\Steam", "$env:ProgramFiles\Steam")) {
            if (Test-Path (Join-Path $guess "steam.exe")) { $steam = $guess; break }
        }
    }
    if ($steam) { $libs.Add((Resolve-Path $steam).Path) }
    $vdf = Join-Path $steam "steamapps\libraryfolders.vdf"
    if ($steam -and (Test-Path $vdf)) {
        foreach ($line in Get-Content $vdf) {
            if ($line -match '"path"\s+"([^"]+)"') {
                $p = $Matches[1] -replace '\\\\', '\'
                if (Test-Path $p) { $libs.Add($p) }
            }
        }
    }
    return $libs | Select-Object -Unique
}

function Find-Win64 {
    $rel = "steamapps\common\RolloutInline\RollerSkate\Binaries\Win64"
    foreach ($lib in Get-SteamLibraries) {
        $dir = Join-Path $lib $rel
        if (Test-Path $dir) { return (Resolve-Path $dir).Path }
    }
    return $null
}

$win64 = Find-Win64
if (-not $win64) { throw "Rollout Inline Win64 folder not found. Install the game on Steam first." }

$exe = $null
foreach ($name in @("RollerSkate-Win64-Shipping.exe", "RollerSkate.exe")) {
    $candidate = Join-Path $win64 $name
    if (Test-Path $candidate) { $exe = $candidate; break }
}
if (-not $exe) { throw "Shipping exe not found in $win64" }

$ue4ss = Join-Path $win64 "ue4ss\Mods\RoweModGameplay"
if (-not (Test-Path $ue4ss)) {
    Write-Warning "RoweModGameplay not installed in UE4SS. Run install.ps1 first."
}

# Unique mailboxes so two game processes do not share one inbox.
$mailA = Join-Path $env:TEMP "RoweModMP\A"
$mailB = Join-Path $env:TEMP "RoweModMP\B"
New-Item -ItemType Directory -Force -Path $mailA, $mailB | Out-Null

$port = 27045
$py = Get-Command python -ErrorAction SilentlyContinue
if (-not $py) { $py = Get-Command python3 -ErrorAction SilentlyContinue }
if (-not $py) { throw "Python not found on PATH (needed for tools/rowemod_mp.py)." }

$bridge = Join-Path $here "tools\rowemod_mp.py"
Write-Host "Mailboxes:`n  A (host) $mailA`n  B (join) $mailB"
Write-Host "Starting bridges on UDP $port ..."

$hostProc = Start-Process -FilePath $py.Source -ArgumentList @(
    $bridge, "host", "--port", "$port", "--mailbox", $mailA, "--name", "PlayerA", "--map", "DualLocal"
) -PassThru -WindowStyle Normal

Start-Sleep -Milliseconds 400

$joinProc = Start-Process -FilePath $py.Source -ArgumentList @(
    $bridge, "join", "--host", "127.0.0.1", "--port", "$port", "--mailbox", $mailB, "--name", "PlayerB", "--map", "DualLocal"
) -PassThru -WindowStyle Normal

Start-Sleep -Milliseconds 600

function Start-GameInstance([string]$Mailbox, [string]$Name, [string]$Role, [int]$X, [int]$Y) {
    $args = @(
        "-windowed",
        "-ResX=1280",
        "-ResY=720",
        "-WinX=$X",
        "-WinY=$Y"
    )
    # cmd so env vars are scoped to this child only
    $cmd = "set `"ROUEMOD_MP_MAILBOX=$Mailbox`" && set `"ROUEMOD_MP_NAME=$Name`" && set `"ROUEMOD_MP_ROLE=$Role`" && `"$exe`" $($args -join ' ')"
    Write-Host "Launching $Name ($Role) ..."
    Start-Process -FilePath "cmd.exe" -ArgumentList @("/c", $cmd) -WorkingDirectory $win64
}

# steam_appid helps some offline launches
Set-Content (Join-Path $win64 "steam_appid.txt") "4464990" -Encoding ASCII -ErrorAction SilentlyContinue

Start-GameInstance -Mailbox $mailA -Name "PlayerA" -Role "host" -X 40 -Y 40
Start-Sleep -Milliseconds 1500
Start-GameInstance -Mailbox $mailB -Name "PlayerB" -Role "join" -X 700 -Y 80

Write-Host ""
Write-Host "Two game windows should open. In EACH window:"
Write-Host "  1) Load the SAME map"
Write-Host "  2) Press F9  (or console: rowemod mp on)"
Write-Host "  3) Check: rowemod mp status   → connected=1 map ok=true"
Write-Host ""
Write-Host "Bridge PIDs: host=$($hostProc.Id) join=$($joinProc.Id)"
Write-Host "If Steam blocked the second exe, run the shipping exe manually twice with those env vars."
Write-Host "Press Ctrl+C in the bridge windows (or End-Process) when done."
