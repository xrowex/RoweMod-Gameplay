$ErrorActionPreference='Stop'
$repo = Split-Path $PSScriptRoot
$testRoot = Join-Path $env:TEMP ('RoweMod-InstallTest-' + [guid]::NewGuid().ToString('N'))
$savedLocalAppData=$env:LOCALAPPDATA
function Assert($condition,$message) { if (-not $condition) { throw $message } }
try {
    $env:LOCALAPPDATA=Join-Path $testRoot 'AppData'
    $gameRoot=Join-Path $testRoot 'Game With Spaces'
    $game=Join-Path $gameRoot 'Binaries\Win64'
    New-Item -ItemType Directory -Force -Path $game | Out-Null
    Set-Content -LiteralPath (Join-Path $game 'RollerSkate-Win64-Shipping.exe') 'fake fixture; never executed'
    $global:roweTestDamagedBody=Join-Path $repo 'assets/skeleton/RoweSkeleton_P.ucas'
    function global:Get-FileHash {
        param([string]$LiteralPath,[string]$Algorithm='SHA256')
        if ($LiteralPath -eq $global:roweTestDamagedBody) { return [pscustomobject]@{Hash='damaged'} }
        Microsoft.PowerShell.Utility\Get-FileHash -LiteralPath $LiteralPath -Algorithm $Algorithm
    }
    $rejected=$false
    try { & (Join-Path $repo 'install.ps1') -GameDirectory $game -Unattended }
    catch { $rejected=$_.Exception.Message -match 'Skeleton bundle missing or damaged' }
    finally { Remove-Item Function:\Get-FileHash }
    Assert $rejected 'Damaged skeleton was not rejected'
    Assert (-not (Test-Path (Join-Path $game 'ue4ss'))) 'Files changed before body checksum validation'
    & (Join-Path $repo 'install.ps1') -GameDirectory $game -Unattended
    $runtime=Get-Content -LiteralPath (Join-Path $repo 'tools\ue4ss-runtime.json') -Raw | ConvertFrom-Json
    foreach ($entry in $runtime.sha256.PSObject.Properties) {
        Assert ((Get-FileHash -LiteralPath (Join-Path $game $entry.Name)).Hash -eq $entry.Value) "Fresh runtime mismatch: $($entry.Name)"
    }
    Assert (Test-Path -LiteralPath (Join-Path $game 'RoweModOnline\RoweModOnline.exe')) 'Missing companion'
    $bodyManifest=Get-Content (Join-Path $repo 'assets/skeleton/manifest.json') -Raw | ConvertFrom-Json
    $paks=Join-Path $gameRoot 'Content/Paks/~mods'
    foreach ($entry in $bodyManifest.sha256.PSObject.Properties) {
        Assert ((Get-FileHash -LiteralPath (Join-Path $paks $entry.Name)).Hash -eq $entry.Value) "Fresh skeleton mismatch: $($entry.Name)"
    }
    Set-Content -LiteralPath (Join-Path $paks 'OtherClothing_P.pak') 'unrelated clothing'
    Set-Content -LiteralPath (Join-Path $paks 'RoweSkeleton_P.ucas') 'older prototype'
    $config=Join-Path $game 'ue4ss\Mods\RoweModGameplay\Scripts\config.lua'
    Set-Content -LiteralPath $config '-- personal configuration'
    $other=Join-Path $game 'ue4ss\Mods\OtherMod\Scripts'
    New-Item -ItemType Directory -Force -Path $other | Out-Null
    Set-Content -LiteralPath (Join-Path $other 'main.lua') '-- other mod'
    Add-Content -LiteralPath (Join-Path $game 'ue4ss\Mods\mods.txt') 'OtherMod : 1'
    Set-Content -LiteralPath (Join-Path $game 'ue4ss\Mods\mods.json') '[{"mod_name":"OtherMod","mod_enabled":true}]'
    Add-Content -LiteralPath (Join-Path $game 'ue4ss\UE4SS-settings.ini') "`r`n[Personal]`r`nKeepMe = yes"
    & (Join-Path $repo 'install.ps1') -GameDirectory $game -Unattended
    Assert ((Get-Content -LiteralPath $config -Raw).Trim() -eq '-- personal configuration') 'Personal config replaced'
    Assert ((Get-Content -LiteralPath (Join-Path $paks 'OtherClothing_P.pak') -Raw).Trim() -eq 'unrelated clothing') 'Unrelated clothing changed'
    foreach ($entry in $bodyManifest.sha256.PSObject.Properties) {
        Assert ((Get-FileHash -LiteralPath (Join-Path $paks $entry.Name)).Hash -eq $entry.Value) "Updated skeleton mismatch: $($entry.Name)"
    }
    Assert (Test-Path -LiteralPath (Join-Path $other 'main.lua')) 'Other mod removed'
    $mods=Get-Content -LiteralPath (Join-Path $game 'ue4ss\Mods\mods.txt') -Raw
    Assert ($mods -match 'OtherMod : 1') 'Other mod disabled'
    Assert (([regex]::Matches($mods,'RoweModGameplay : 1')).Count -eq 1) 'Duplicate mod registration'
    Assert ($mods.TrimEnd().EndsWith('Keybinds : 1')) 'Keybinds must load last'
    Assert ((Get-Content -LiteralPath (Join-Path $game 'ue4ss\UE4SS-settings.ini') -Raw) -match 'KeepMe = yes') 'Unrelated UE4SS setting lost'
    Assert (-not (Test-Path -LiteralPath (Join-Path $game 'ue4ss\Mods\RoweModGameplay\RoweModGameplay'))) 'Nested installation'
    Assert ((Get-ChildItem -LiteralPath (Join-Path $env:LOCALAPPDATA 'RoweMod\Backups') -Filter receipt.json -Recurse).Count -eq 2) 'Missing backup receipts'
    $before=@{}
    foreach ($file in Get-ChildItem -LiteralPath $gameRoot -File -Recurse) { $before[$file.FullName]=(Get-FileHash -LiteralPath $file.FullName).Hash }
    $global:roweTestGame=$gameRoot
    $global:roweTestCopies=0
    function global:Copy-Item {
        param([string]$LiteralPath,[string]$Destination,[switch]$Force)
        if ($Destination.StartsWith($global:roweTestGame,[StringComparison]::OrdinalIgnoreCase)) {
            $global:roweTestCopies++
            if ($global:roweTestCopies -eq 3) { throw 'intentional copy failure' }
        }
        Microsoft.PowerShell.Management\Copy-Item -LiteralPath $LiteralPath -Destination $Destination -Force:$Force
    }
    $failed=$false
    try { & (Join-Path $repo 'install.ps1') -GameDirectory $game -Unattended }
    catch { Write-Host ('Injected run: '+$_.Exception.Message); $failed=$_.Exception.Message -match 'intentional copy failure' }
    finally { Remove-Item Function:\Copy-Item }
    Assert $failed 'Failure injection did not execute'
    foreach ($path in $before.Keys) { Assert ((Get-FileHash -LiteralPath $path).Hash -eq $before[$path]) "Rollback mismatch: $path" }
    Write-Host 'PASS injected copy failure rolled back without changing any installed file'
    $global:roweTestPaks=$paks
    $global:roweTestContentCopies=0
    function global:Copy-Item {
        param([string]$LiteralPath,[string]$Destination,[switch]$Force)
        if ($Destination.StartsWith($global:roweTestPaks,[StringComparison]::OrdinalIgnoreCase)) {
            $global:roweTestContentCopies++
            if ($global:roweTestContentCopies -eq 2) { throw 'intentional content failure' }
        }
        Microsoft.PowerShell.Management\Copy-Item -LiteralPath $LiteralPath -Destination $Destination -Force:$Force
    }
    $failed=$false
    try { & (Join-Path $repo 'install.ps1') -GameDirectory $game -Unattended }
    catch { $failed=$_.Exception.Message -match 'intentional content failure' }
    finally { Remove-Item Function:\Copy-Item }
    Assert $failed 'Content failure injection did not execute'
    foreach ($path in $before.Keys) { Assert ((Get-FileHash -LiteralPath $path).Hash -eq $before[$path]) "Content rollback mismatch: $path" }
    Write-Host 'PASS skeleton upgrade, other clothing preservation and content rollback'
    Write-Host "PASS fresh install, re-install, exact UE4SS hashes, settings/other-mod preservation, backups: $testRoot"
} finally { $env:LOCALAPPDATA=$savedLocalAppData }
