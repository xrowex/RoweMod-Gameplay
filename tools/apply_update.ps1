param([Parameter(Mandatory=$true)][string]$PackageRoot,
      [Parameter(Mandatory=$true)][string]$GameDirectory,
      [int]$ParentId)
$ErrorActionPreference = 'Stop'
$updateRoot = Join-Path $env:LOCALAPPDATA 'RoweMod\Updates'
$package = (Resolve-Path -LiteralPath $PackageRoot).ProviderPath
$root = (Resolve-Path -LiteralPath $updateRoot).ProviderPath.TrimEnd('\') + '\'
if (-not $package.StartsWith($root,[StringComparison]::OrdinalIgnoreCase)) { throw 'Update package outside staging folder' }
$lock = $null
try {
    # One pending installer per Windows user. A later launch can retry after a failure.
    try { $lock = [IO.File]::Open((Join-Path $updateRoot 'apply.lock'),'OpenOrCreate','ReadWrite','None') }
    catch [IO.IOException] { exit 0 }
    while ($true) {
        $busy = $false
        if ($ParentId -and (Get-Process -Id $ParentId -ErrorAction SilentlyContinue)) { $busy=$true }
        foreach ($proc in Get-Process -Name 'RollerSkate-Win64-Shipping','RollerSkate','RoweModOnline' -ErrorAction SilentlyContinue) {
            if (-not $proc.Path -or $proc.Path.StartsWith($GameDirectory.TrimEnd('\')+'\',[StringComparison]::OrdinalIgnoreCase)) { $busy=$true }
        }
        if (-not $busy) { break }
        Start-Sleep -Seconds 5
    }
    $incoming = [version](Get-Content -LiteralPath (Join-Path $package 'version.json') -Raw | ConvertFrom-Json).version
    $installed = [version](Get-Content -LiteralPath (Join-Path $GameDirectory 'RoweModOnline\version.json') -Raw | ConvertFrom-Json).version
    if ($incoming -le $installed) { exit 0 }
    $manifest = Get-Content -LiteralPath (Join-Path $package 'manifest.json') -Raw | ConvertFrom-Json
    foreach ($entry in $manifest.sha256.PSObject.Properties) {
        $file = [IO.Path]::GetFullPath((Join-Path $package $entry.Name))
        if (-not $file.StartsWith($package.TrimEnd('\')+'\',[StringComparison]::OrdinalIgnoreCase) -or
            (Get-FileHash -LiteralPath $file -Algorithm SHA256).Hash -ne $entry.Value) { throw 'Staged update files changed before installation' }
    }
    & (Join-Path $package 'install.ps1') -GameDirectory $GameDirectory -Unattended *>&1 |
        Out-File -LiteralPath (Join-Path $updateRoot 'install.log') -Encoding UTF8
    @{message="Installed RoweMod $incoming";installed=$incoming.ToString();checked=[DateTimeOffset]::UtcNow.ToUnixTimeSeconds()} |
        ConvertTo-Json | Set-Content -LiteralPath (Join-Path $updateRoot 'status.json') -Encoding UTF8
} catch {
    @{message='Automatic install failed; run install.cmd from the downloaded update';package=$package;detail=$_.Exception.Message} |
        ConvertTo-Json | Set-Content -LiteralPath (Join-Path $updateRoot 'status.json') -Encoding UTF8
} finally { if ($lock) { $lock.Dispose() } }
