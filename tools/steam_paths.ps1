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
    $vdf = if ($steam) { Join-Path $steam "steamapps\libraryfolders.vdf" } else { $null }
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

function Test-Win64($dir) {
    if (-not $dir -or -not (Test-Path $dir)) { return $false }
    return (Test-Path (Join-Path $dir "RollerSkate-Win64-Shipping.exe")) -or
        (Test-Path (Join-Path $dir "RollerSkate.exe"))
}

function Find-Win64 {
    $rel = "steamapps\common\RolloutInline\RollerSkate\Binaries\Win64"
    foreach ($lib in Get-SteamLibraries) {
        $dir = Join-Path $lib $rel
        if (Test-Win64 $dir) { return (Resolve-Path $dir).Path }
    }
    foreach ($fallback in @(
            "C:\Program Files (x86)\Steam\steamapps\common\RolloutInline\RollerSkate\Binaries\Win64",
            "C:\program files (x86)\steam\steamapps\common\RolloutInline\RollerSkate\Binaries\Win64"
        )) {
        if (Test-Win64 $fallback) { return (Resolve-Path $fallback).Path }
    }
    return $null
}

