param([string]$GameRoot = 'C:\Program Files (x86)\Steam\steamapps\common\RolloutInline\RollerSkate')
$ErrorActionPreference = 'Stop'
if (Get-Process 'RollerSkate*' -ErrorAction SilentlyContinue) { throw 'Close Rollout Inline before installing the body.' }
if (-not (Test-Path -LiteralPath (Join-Path $GameRoot 'Binaries/Win64/RollerSkate-Win64-Shipping.exe'))) { throw 'GameRoot must point to the RollerSkate folder.' }
$manifest = Get-Content -LiteralPath (Join-Path $PSScriptRoot 'manifest.json') -Raw | ConvertFrom-Json
$files = @('RoweSkeleton_P.pak','RoweSkeleton_P.utoc','RoweSkeleton_P.ucas')
foreach ($name in $files) {
    $hash = (Get-FileHash -LiteralPath (Join-Path $PSScriptRoot "files/$name") -Algorithm SHA256).Hash
    if ($hash -ne $manifest.hashes.$name) { throw "Checksum failed: $name" }
}
$target = Join-Path $GameRoot 'Content/Paks/~mods'
New-Item -ItemType Directory -Path $target -Force | Out-Null
$backup = Join-Path $env:LOCALAPPDATA ('RoweMod/Backups/Skeleton-' + [guid]::NewGuid().ToString('N'))
foreach ($name in $files) {
    $destination = Join-Path $target $name
    if (Test-Path -LiteralPath $destination) {
        New-Item -ItemType Directory -Path $backup -Force | Out-Null
        Copy-Item -LiteralPath $destination -Destination (Join-Path $backup $name)
    }
}
try {
    foreach ($name in $files) {
        $destination = Join-Path $target $name
        Copy-Item -LiteralPath (Join-Path $PSScriptRoot "files/$name") -Destination $destination -Force
        if ((Get-FileHash -LiteralPath $destination -Algorithm SHA256).Hash -ne $manifest.hashes.$name) { throw "Installed checksum failed: $name" }
    }
} catch {
    # Restore an earlier add-on if present. Never touch other mod packages.
    foreach ($name in $files) {
        $previous=Join-Path $backup $name
        if (Test-Path -LiteralPath $previous) { Copy-Item -LiteralPath $previous -Destination (Join-Path $target $name) -Force }
    }
    throw
}
Write-Host 'Skeleton installed. Start Rollout, then select Skeleton in character customization > Body.'
Write-Host 'Prototype: check skating, grabs, falls, and multiplayer before sharing as a stable release.'
