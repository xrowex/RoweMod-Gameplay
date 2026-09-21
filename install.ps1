# Copy RoweModGameplay into the game's UE4SS Mods folder.
$ErrorActionPreference = "Stop"
$here = $PSScriptRoot

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
        foreach ($guess in @("${env:ProgramFiles(x86)}\Steam", "$env:ProgramFiles\Steam", "C:\Program Files (x86)\Steam")) {
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
        if (Test-Path (Join-Path $dir "RollerSkate.exe")) { return (Resolve-Path $dir).Path }
    }
    $fallback = "C:\Program Files (x86)\Steam\steamapps\common\RolloutInline\RollerSkate\Binaries\Win64"
    if (Test-Path (Join-Path $fallback "RollerSkate.exe")) { return (Resolve-Path $fallback).Path }
    return $null
}

$win64 = Find-Win64
if (-not $win64) { throw "Rollout Inline not found. Install it on Steam, then run this again." }

$ue4ss = Join-Path $win64 "ue4ss"
$dwmapi = Join-Path $win64 "dwmapi.dll"
if (-not (Test-Path $ue4ss) -or -not (Test-Path $dwmapi)) {
    throw "UE4SS is not in the game folder yet.`nInstall it first (RoweMod kit tools\install_ue4ss.ps1, or UE4SS for UE 5.4), then run this again.`nLooked in: $win64"
}

$src = Join-Path $here "ue4ss\Mods\RoweModGameplay"
$dst = Join-Path $ue4ss "Mods\RoweModGameplay"
New-Item -ItemType Directory -Force -Path (Split-Path $dst -Parent) | Out-Null
Copy-Item $src $dst -Recurse -Force

$modsTxt = Join-Path $ue4ss "Mods\mods.txt"
if (Test-Path $modsTxt) {
    $text = Get-Content $modsTxt -Raw
    if ($text -notmatch "RoweModGameplay") {
        $line = "RoweModGameplay : 1"
        if ($text -match "(?m)^Keybinds") {
            $text = $text -replace "(?m)^Keybinds", "$line`r`nKeybinds"
        } else {
            $text = $text.TrimEnd() + "`r`n$line`r`n"
        }
        Set-Content -Path $modsTxt -Value ($text.TrimEnd() + "`r`n") -Encoding ASCII
    }
} else {
    Set-Content -Path $modsTxt -Value "RoweModGameplay : 1`r`nKeybinds : 1`r`n" -Encoding ASCII
}

$modsJson = Join-Path $ue4ss "Mods\mods.json"
if (Test-Path $modsJson) {
    $json = Get-Content $modsJson -Raw | ConvertFrom-Json
    $names = @($json | ForEach-Object { $_.mod_name })
    if ($names -notcontains "RoweModGameplay") {
        $entry = [pscustomobject]@{ mod_name = "RoweModGameplay"; mod_enabled = $true }
        $json = @($json) + $entry
        $json | ConvertTo-Json | Set-Content -Path $modsJson -Encoding UTF8
    }
}

Set-Content (Join-Path $win64 "steam_appid.txt") "4464990" -Encoding ASCII
Write-Host "Installed RoweModGameplay -> $dst"
Write-Host "Launch Rollout Inline. Numpad +/- changes speed. Edit Scripts\config.lua then press F8."
