param([string]$GameDirectory, [switch]$Unattended)
$ErrorActionPreference = 'Stop'
$here = $PSScriptRoot
. (Join-Path $here 'tools\steam_paths.ps1')
$win64 = if ($GameDirectory) { $GameDirectory } else { Find-Win64 }
if (-not (Test-Win64 $win64)) { throw 'Rollout Inline not found. Install it on Steam first.' }
$win64 = (Resolve-Path -LiteralPath $win64).ProviderPath
foreach ($proc in Get-Process -Name 'RollerSkate-Win64-Shipping','RollerSkate','RoweModOnline' -ErrorAction SilentlyContinue) {
    if (-not $proc.Path -or $proc.Path.StartsWith($win64.TrimEnd('\') + '\', [StringComparison]::OrdinalIgnoreCase)) {
        throw 'Close Rollout Inline and RoweMod Online, then run install.cmd again.'
    }
}
$runtime = Join-Path $here 'tools\deps\ue4ss-runtime'
$manifest = Get-Content -LiteralPath (Join-Path $here 'tools\ue4ss-runtime.json') -Raw | ConvertFrom-Json
foreach ($entry in $manifest.sha256.PSObject.Properties) {
    $source = Join-Path $runtime $entry.Name
    if (-not (Test-Path -LiteralPath $source) -or (Get-FileHash -LiteralPath $source -Algorithm SHA256).Hash -ne $entry.Value) {
        throw "UE4SS bundle missing or damaged: $($entry.Name). Extract the complete RoweMod release ZIP again."
    }
}
if (-not (Test-Path -LiteralPath (Join-Path $here 'tools\deps\RoweModOnline.exe'))) {
    throw 'The Online executable is missing. Use the full release ZIP, not GitHub Source code.zip.'
}
# Elevate only when this Steam library needs administrator access.
$probe = Join-Path $win64 ('.rowemod-write-' + [guid]::NewGuid().ToString('N'))
try { [IO.File]::WriteAllText($probe, ''); Remove-Item -LiteralPath $probe -Force }
catch [UnauthorizedAccessException] {
    if ($Unattended) { throw 'Update needs administrator access. Run install.cmd from the downloaded update.' }
    $child = Start-Process powershell.exe -Verb RunAs -WindowStyle Hidden -Wait -PassThru -ArgumentList @('-NoProfile','-ExecutionPolicy','Bypass','-File',('"' + $PSCommandPath + '"'),'-GameDirectory',('"' + $win64 + '"'),'-Unattended')
    exit $child.ExitCode
}
$state = Join-Path $env:LOCALAPPDATA 'RoweMod'
$stamp = (Get-Date -Format 'yyyyMMdd-HHmmss') + '-' + [guid]::NewGuid().ToString('N').Substring(0,6)
$stage = Join-Path $state "InstallStaging\$stamp"
$backup = Join-Path $state "Backups\Install-$stamp"
New-Item -ItemType Directory -Force -Path $stage,$backup | Out-Null
$plan = @{}
function Add-Payload([string]$relative, [string]$source) {
    $dest = Join-Path $stage $relative
    New-Item -ItemType Directory -Force -Path (Split-Path $dest) | Out-Null
    Copy-Item -LiteralPath $source -Destination $dest -Force
    $plan[$relative] = $dest
}
function Add-Text([string]$relative, [string]$text) {
    $dest = Join-Path $stage $relative
    New-Item -ItemType Directory -Force -Path (Split-Path $dest) | Out-Null
    [IO.File]::WriteAllText($dest, $text, [Text.UTF8Encoding]::new($false))
    $plan[$relative] = $dest
}
foreach ($entry in $manifest.sha256.PSObject.Properties) { Add-Payload $entry.Name (Join-Path $runtime $entry.Name) }
# Preserve unrelated UE4SS settings while applying the tested Rollout overrides.
$iniPath = Join-Path $win64 'ue4ss\UE4SS-settings.ini'
if (Test-Path -LiteralPath $iniPath) {
    $ini = [IO.File]::ReadAllText($iniPath)
    foreach ($pair in @(@('General','EnableHotReloadSystem','0'),@('General','EnableAutoReloadingLuaMods','0'),@('General','bUseUObjectArrayCache','false'),@('General','DefaultExecuteInGameThreadMethod','EngineTick'),@('EngineVersionOverride','MajorVersion','5'),@('EngineVersionOverride','MinorVersion','4'))) {
        $section,$key,$value = $pair
        $pattern = '(?m)^\s*' + [regex]::Escape($key) + '\s*=.*$'
        if ($ini -match $pattern) { $ini = [regex]::Replace($ini,$pattern,"$key = $value") }
        elseif ($ini -match ('(?m)^\[' + $section + '\]\s*$')) {
            $ini = [regex]::Replace($ini,('(?m)^\[' + $section + '\]\s*$'),("[$section]`r`n$key = $value"))
        } else { $ini += "`r`n[$section]`r`n$key = $value`r`n" }
    }
    Add-Text 'ue4ss/UE4SS-settings.ini' $ini
}
$modRoot = Join-Path $here 'ue4ss\Mods\RoweModGameplay'
foreach ($file in Get-ChildItem -LiteralPath $modRoot -Recurse -File) {
    $rel = 'ue4ss/Mods/RoweModGameplay/' + $file.FullName.Substring($modRoot.Length + 1).Replace('\','/')
    if ($rel -eq 'ue4ss/Mods/RoweModGameplay/Scripts/config.lua' -and (Test-Path -LiteralPath (Join-Path $win64 $rel))) { continue }
    Add-Payload $rel $file.FullName
}
$required = @('CheatManagerEnablerMod','ConsoleCommandsMod','ConsoleEnablerMod','RoweModGameplay','Keybinds')
$modsPath = Join-Path $win64 'ue4ss/Mods/mods.txt'
$mods = if (Test-Path -LiteralPath $modsPath) { [IO.File]::ReadAllText($modsPath) } else { '' }
foreach ($name in $required) { $mods = [regex]::Replace($mods,('(?m)^\s*'+$name+'\s*:\s*[01]\s*\r?$'),'') }
$mods = $mods.TrimEnd() + "`r`n" + (($required | ForEach-Object { "$_ : 1" }) -join "`r`n") + "`r`n"
Add-Text 'ue4ss/Mods/mods.txt' $mods
$jsonPath = Join-Path $win64 'ue4ss/Mods/mods.json'
if (Test-Path -LiteralPath $jsonPath) {
    $parsed = Get-Content -LiteralPath $jsonPath -Raw | ConvertFrom-Json
    $entries = @($parsed)
    foreach ($name in $required) {
        $existing = @($entries | Where-Object { $_.mod_name -eq $name })
        if ($existing.Count) { foreach ($entry in $existing) { $entry.mod_enabled = $true } }
        else { $entries += [pscustomobject]@{mod_name=$name;mod_enabled=$true} }
    }
    Add-Text 'ue4ss/Mods/mods.json' (ConvertTo-Json -InputObject @($entries) -Depth 10)
}
foreach ($name in @('rowemod_mp.py','steamworks.py','steam_mp.py','mp_online.py','menu_control.py','online_updater.py','apply_update.ps1','start_online.vbs')) {
    Add-Payload "RoweModOnline/$name" (Join-Path $here "tools\$name")
}
Add-Payload 'RoweModOnline/RoweModOnline.exe' (Join-Path $here 'tools\deps\RoweModOnline.exe')
Add-Payload 'RoweModOnline/version.json' (Join-Path $here 'version.json')
Add-Payload 'RoweModOnline/ue4ss-runtime.json' (Join-Path $here 'tools\ue4ss-runtime.json')
Add-Text 'steam_appid.txt' "4464990`r`n"
# Snapshot every owned destination before any replacement; preserve other mods and saves.
$changed = [Collections.Generic.List[string]]::new()
$previous = @{}
foreach ($rel in $plan.Keys) {
    $target = Join-Path $win64 $rel
    $previous[$rel] = Test-Path -LiteralPath $target
    if ($previous[$rel]) {
        $copy = Join-Path $backup $rel
        New-Item -ItemType Directory -Force -Path (Split-Path $copy) | Out-Null
        Copy-Item -LiteralPath $target -Destination $copy -Force
    }
}
try {
    foreach ($rel in $plan.Keys) {
        $target = Join-Path $win64 $rel
        New-Item -ItemType Directory -Force -Path (Split-Path $target) | Out-Null
        $changed.Add($rel)
        Copy-Item -LiteralPath $plan[$rel] -Destination $target -Force
        if ((Get-FileHash -LiteralPath $target).Hash -ne (Get-FileHash -LiteralPath $plan[$rel]).Hash) { throw "Copy verification failed: $rel" }
    }
} catch {
    $failure = $_
    $restoreErrors = @()
    foreach ($rel in $changed) {
        $target = Join-Path $win64 $rel
        try {
            if ($previous[$rel]) {
                $saved = Join-Path $backup $rel
                if (-not (Test-Path -LiteralPath $target) -or (Get-FileHash -LiteralPath $target).Hash -ne (Get-FileHash -LiteralPath $saved).Hash) {
                    Copy-Item -LiteralPath $saved -Destination $target -Force
                }
            } elseif (Test-Path -LiteralPath $target) { Remove-Item -LiteralPath $target -Force }
        } catch { $restoreErrors += $rel }
    }
    if ($restoreErrors.Count) { Write-Warning "Some files are locked; restore them from $backup : $($restoreErrors -join ', ')" }
    throw $failure
}
$version = (Get-Content -LiteralPath (Join-Path $here 'version.json') -Raw | ConvertFrom-Json).version
@{version=$version;game=$win64;ue4ss=$manifest.build;backup=$backup;files=@($plan.Keys)} | ConvertTo-Json -Depth 4 | Set-Content -LiteralPath (Join-Path $backup 'receipt.json') -Encoding UTF8
Write-Host "Installed RoweMod $version with UE4SS $($manifest.build)."
Write-Host "Backup: $backup"
Write-Host 'Launch Rollout from Steam. F5 opens gameplay and multiplayer.'
Write-Host 'Updates check automatically at launch and install after the game and companion close.'
