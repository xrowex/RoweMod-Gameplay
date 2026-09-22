$ErrorActionPreference='Stop'
$repo=Split-Path $PSScriptRoot
$testRoot=Join-Path $env:TEMP ('RoweMod-CleanupTest-'+[guid]::NewGuid().ToString('N'))
$saved=$env:LOCALAPPDATA
function Assert($ok,$message) { if (-not $ok) { throw $message } }
try {
 $env:LOCALAPPDATA=Join-Path $testRoot 'AppData'
 $game=Join-Path $testRoot 'Game\Win64'
 $state=Join-Path $env:LOCALAPPDATA 'RoweMod'
 . (Join-Path $repo 'tools\cleanup_versions.ps1')
 foreach ($n in 1..4) {
  $name="20260101-00000$n-abcdef"
  $backup=Join-Path $state "Backups\Install-$name"
  $stage=Join-Path $state "InstallStaging\$name"
  New-Item -ItemType Directory -Force -Path $backup,$stage | Out-Null
  @{game=$game;version='0.5.5'} | ConvertTo-Json | Set-Content -LiteralPath (Join-Path $backup 'receipt.json')
  Set-Content -LiteralPath (Join-Path $stage 'copy.txt') 'completed copy'
 }
 $other=Join-Path $state 'Backups\Install-20200101-000001-abcdef'
 $failed=Join-Path $state 'Backups\Install-20200101-000002-abcdef'
 New-Item -ItemType Directory -Force -Path $other,$failed | Out-Null
 @{game='C:\DifferentGame';version='0.5.0'} | ConvertTo-Json | Set-Content -LiteralPath (Join-Path $other 'receipt.json')
 $updates=Join-Path $state 'Updates'
 foreach ($v in @('0.5.4','0.5.5','0.5.6')) {
  $dir=Join-Path $updates "release-$v-fixture"
  New-Item -ItemType Directory -Force -Path $dir | Out-Null
  @{owner='RoweMod-Gameplay';game=$game;version=$v} | ConvertTo-Json | Set-Content -LiteralPath (Join-Path $dir '.rowemod-update.json')
 }
 $unknown=Join-Path $updates 'release-0.5.0-user-folder'
 New-Item -ItemType Directory -Force -Path $unknown | Out-Null
 $outside=Join-Path $testRoot 'KeepOutside'
 New-Item -ItemType Directory -Force -Path $outside | Out-Null
 Set-Content -LiteralPath (Join-Path $outside 'keep.txt') 'user file'
 $junction=Join-Path $updates 'release-0.5.1-junction'
 New-Item -ItemType Junction -Path $junction -Target $outside | Out-Null
 $nested=Join-Path $updates 'release-0.5.2-nested'
 New-Item -ItemType Directory -Force -Path $nested | Out-Null
 @{owner='RoweMod-Gameplay';game=$game;version='0.5.2'} | ConvertTo-Json | Set-Content -LiteralPath (Join-Path $nested '.rowemod-update.json')
 New-Item -ItemType Junction -Path (Join-Path $nested 'linked') -Target $outside | Out-Null
 # A download in progress protects the update cache, while backup pruning works.
 $lock=[IO.File]::Open((Join-Path $updates 'online.lock'),'OpenOrCreate','ReadWrite','None')
 try { Invoke-RoweModCleanup $game '0.5.5' } finally { $lock.Dispose() }
 Assert (Test-Path (Join-Path $updates 'release-0.5.4-fixture')) 'Active cache was removed'
 Assert (@(Get-ChildItem (Join-Path $state 'InstallStaging')).Count -eq 0) 'Successful staging copies remained'
 Assert (@(Get-ChildItem (Join-Path $state 'Backups')).Count -eq 4) 'Expected two recovery backups, another game and failed backup'
 Invoke-RoweModCleanup $game '0.5.5'
 Assert (-not (Test-Path (Join-Path $updates 'release-0.5.4-fixture'))) 'Old downloaded release remained'
 Assert (-not (Test-Path (Join-Path $updates 'release-0.5.5-fixture'))) 'Completed release remained'
 foreach ($keep in @($other,$failed,$unknown,$junction,$nested,(Join-Path $updates 'release-0.5.6-fixture'),(Join-Path $outside 'keep.txt'))) { Assert (Test-Path -LiteralPath $keep) "Removed protected path: $keep" }
 $rejected=$false
 try { Remove-RoweModCopy $updates $outside } catch { $rejected=$true }
 Assert $rejected 'Outside-root deletion accepted'
 Write-Host 'PASS cleanup retention, staging, completed packages, active download, future version, unknown folders, failed backups, other games and junction safety'
} finally { $env:LOCALAPPDATA=$saved }
