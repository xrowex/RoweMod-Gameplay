param(
    [string]$GameRoot = 'C:\Program Files (x86)\Steam\steamapps\common\RolloutInline\RollerSkate',
    [string]$ClothingTools = "$env:USERPROFILE\rolloutrowemod",
    [string]$UnrealRoot = 'E:\unreal\UE_5.4',
    [string]$Blender = 'C:\Program Files\Blender Foundation\Blender 4.4\blender.exe'
)
$ErrorActionPreference = 'Stop'
$root = (Resolve-Path (Join-Path $PSScriptRoot '../..')).Path
$build = Join-Path $root 'build'
$paks = Join-Path $GameRoot 'Content/Paks'
$cue = Join-Path $ClothingTools 'tools/CUE4Parse.CLI/cue4parse.exe'
$retoc = Join-Path $ClothingTools 'tools/retoc/retoc.exe'
$mappings = Join-Path $ClothingTools 'dumps/mappings.usmap'
$editor = Join-Path $UnrealRoot 'Engine/Binaries/Win64/UnrealEditor-Cmd.exe'
$unrealPak = Join-Path $UnrealRoot 'Engine/Binaries/Win64/UnrealPak.exe'
$reference = Join-Path $build 'skeleton-reference'
$source = Join-Path $build 'skeleton-source'
$project = Join-Path $build 'skeleton-ue'
$uproject = Join-Path $project 'RollerSkate.uproject'
$stamp = [guid]::NewGuid().ToString('N')
$stage = Join-Path $build "skeleton-package-$stamp"
$patchStage = Join-Path $stage 'table-work'
$payload = Join-Path $stage 'payload'
$dist = Join-Path $root "dist/RoweSkeleton-prototype-$stamp"
function Run([string]$Exe, [string[]]$Arguments) {
    & $Exe @Arguments
    if ($LASTEXITCODE -ne 0) { throw "$Exe failed with exit code $LASTEXITCODE" }
}
function RunLogged([string]$Exe, [string[]]$Arguments, [string]$Log) {
    & $Exe @Arguments *> $Log
    if ($LASTEXITCODE -ne 0) { throw "$Exe failed. See $Log" }
}
foreach ($file in @($cue,$retoc,$mappings,$editor,$unrealPak,$Blender)) {
    if (-not (Test-Path -LiteralPath $file)) { throw "Missing build dependency: $file" }
}
New-Item -ItemType Directory -Path $build,$source,$reference,$stage,$dist -Force | Out-Null
Run python @((Join-Path $PSScriptRoot 'fetch_skeleton.py'))
$body = '*/body/male/male-01/male-body-01.uasset'
$rig = '*/body/main-rig/main-rig.uasset'
RunLogged $cue @('-i',$paks,'-o',$reference,'-g','GAME_UE5_4','-m',$mappings,'--mesh-format','Gltf2','-p',$body,'-y') (Join-Path $source 'extract-mesh.log')
RunLogged $cue @('-i',$paks,'-o',$reference,'-g','GAME_UE5_4','-m',$mappings,'-f','json','-p',$rig,'-p','RollerSkate/Content/MainFolder/UI/customization/data/DT-bodytypes.uasset','-y') (Join-Path $source 'extract-data.log')
RunLogged $Blender @('--factory-startup','-b','-t','2','--python-exit-code','1','--python',(Join-Path $PSScriptRoot 'build_skeleton.py')) (Join-Path $source 'build.log')
Run $Blender @('--factory-startup','-b','-t','2','--python-exit-code','1','--python',(Join-Path $PSScriptRoot 'prepare_bind.py'))
# Fresh imports prevent UE from retaining a previous reference pose. Preserve
# previous projects as backups, and verify both absolute paths before moving.
if (Test-Path -LiteralPath $project) {
    $old = (Resolve-Path $project).Path
    $backup = [IO.Path]::GetFullPath((Join-Path $build "skeleton-ue-backup-$stamp"))
    $prefix = (Resolve-Path $build).Path + '\'
    if (-not $old.StartsWith($prefix,[StringComparison]::OrdinalIgnoreCase) -or -not $backup.StartsWith($prefix,[StringComparison]::OrdinalIgnoreCase)) { throw 'Invalid build backup path' }
    Move-Item -LiteralPath $old -Destination $backup
}
New-Item -ItemType Directory -Path (Join-Path $project 'Config'),(Join-Path $project 'Content') -Force | Out-Null
@{FileVersion=3;EngineAssociation='5.4';Plugins=@(@{Name='PythonScriptPlugin';Enabled=$true},@{Name='EditorScriptingUtilities';Enabled=$true},@{Name='InterchangeEditor';Enabled=$true})} | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath $uproject -Encoding utf8
@'
[/Script/UnrealEd.ProjectPackagingSettings]
bUseIoStore=False
bShareMaterialShaderCode=False
bSharedMaterialNativeLibraries=False
'@ | Set-Content -LiteralPath (Join-Path $project 'Config/DefaultGame.ini')
@'
[/Script/EngineSettings.GameMapsSettings]
GameDefaultMap=/Engine/Maps/Entry
EditorStartupMap=/Engine/Maps/Entry
'@ | Set-Content -LiteralPath (Join-Path $project 'Config/DefaultEngine.ini')
RunLogged $editor @($uproject,'-run=pythonscript',('-script='+ (Join-Path $PSScriptRoot 'import_skeleton.py')),'-unattended','-NullRHI','-nosound','-UTF8Output') (Join-Path $source 'unreal-import-console.log')
RunLogged $editor @($uproject,'-run=Cook','-TargetPlatform=Windows','-CookDir=/Game/RoweMod/Characters/Skeleton','-unattended','-NullRHI','-nosound','-UTF8Output') (Join-Path $source 'cook-console.log')
$cooked = Join-Path $project 'Saved/Cooked/Windows/RollerSkate/Content/RoweMod/Characters/Skeleton'
$proof = Join-Path $stage 'proof.pak'
$response = Join-Path $stage 'proof-files.txt'
Get-ChildItem -LiteralPath $cooked -File | ForEach-Object { '"'+$_.FullName+'" "../../../RollerSkate/Content/RoweMod/Characters/Skeleton/'+$_.Name+'"' } | Set-Content -LiteralPath $response -Encoding utf8
RunLogged $unrealPak @($proof,('-Create='+$response)) (Join-Path $source 'proof-pack.log')
$proofJson = Join-Path $stage 'proof-json'
RunLogged $cue @('--pak',$proof,'-o',$proofJson,'-g','GAME_UE5_4','-f','json','-p','*Skeleton*','-y') (Join-Path $source 'proof-export.log')
Run python @((Join-Path $ClothingTools 'tools/verify_boot_pose.py'),(Join-Path $reference 'RollerSkate/Content/MainFolder/Character/body/main-rig/main-rig.json'),(Join-Path $proofJson 'RollerSkate/Content/RoweMod/Characters/Skeleton/SK_RoweSkeleton_gamebind_Skeleton.json'))
$legacy = Join-Path $patchStage 'dumps/legacy'
New-Item -ItemType Directory -Path $legacy,(Join-Path $patchStage 'items'),(Join-Path $patchStage 'tools') -Force | Out-Null
Set-Content -LiteralPath (Join-Path $patchStage '.rowemod-skeleton-staging') -Value 'isolated body table'
Copy-Item -LiteralPath $mappings -Destination (Join-Path $patchStage 'dumps/mappings.usmap')
Run $retoc @('to-legacy',$paks,$legacy,'--filter','DT-bodytypes','--version','UE5_4')
$ready = Join-Path $patchStage 'ue/RollerSkate/Saved/Cooked/Windows/RollerSkate/Content/RoweMod/Characters/Skeleton'
New-Item -ItemType Directory -Path $ready -Force | Out-Null
Copy-Item -Path (Join-Path $cooked '*') -Destination $ready
Run dotnet @('run','--project',(Join-Path $PSScriptRoot 'PatchBodyTable'),'-c','Release',('-p:RoweClothingRoot='+$ClothingTools),'--',$patchStage,(Join-Path $PSScriptRoot 'skeleton.item.json'))
$custom = Join-Path $payload 'RollerSkate/Content/RoweMod/Characters/Skeleton'
$table = Join-Path $payload 'RollerSkate/Content/MainFolder/UI/customization/data'
New-Item -ItemType Directory -Path $custom,$table,(Join-Path $dist 'files') -Force | Out-Null
foreach ($name in @('SK_RoweSkeleton','M_Bone','MI_Bone','T_SkeletonPreview')) {
    Copy-Item -Path (Join-Path $cooked ($name+'.*')) -Destination $custom
}
Copy-Item -Path (Join-Path $patchStage 'dumps/patched/DT-bodytypes.*') -Destination $table
Run $retoc @('to-zen',$payload,(Join-Path $dist 'files/RoweSkeleton_P.utoc'),'--version','UE5_4')
Run $retoc @('verify',(Join-Path $dist 'files/RoweSkeleton_P.utoc'))
Copy-Item -LiteralPath (Join-Path $PSScriptRoot 'Install-Skeleton.ps1'),(Join-Path $PSScriptRoot 'Install-Skeleton.cmd') -Destination $dist
Copy-Item -LiteralPath (Join-Path $root 'docs/skeleton-body.md') -Destination (Join-Path $dist 'README.md')
Copy-Item -LiteralPath (Join-Path $root 'docs/licenses/Skeleton.txt') -Destination (Join-Path $dist 'ATTRIBUTION.txt')
Copy-Item -LiteralPath (Join-Path $source 'License.txt') -Destination (Join-Path $dist 'SOURCE-LICENSE.txt')
Copy-Item -LiteralPath (Join-Path $source 'skeleton-preview.png') -Destination $dist
$hashes = @{}
Get-ChildItem -LiteralPath (Join-Path $dist 'files') -File | ForEach-Object { $hashes[$_.Name] = (Get-FileHash -LiteralPath $_.FullName -Algorithm SHA256).Hash }
Copy-Item -LiteralPath (Join-Path $source 'chest-fit.json') -Destination $dist
@{name='Rowe Skeleton';version='prototype-2-chest-fit';status='Cooked and rig-verified; native chest/clothing retest pending';hashes=$hashes} | ConvertTo-Json -Depth 4 | Set-Content -LiteralPath (Join-Path $dist 'manifest.json') -Encoding utf8
Compress-Archive -Path (Join-Path $dist '*') -DestinationPath ($dist+'.zip')
Write-Host "PACKAGE: $dist"
Write-Host "ZIP: $dist.zip"
