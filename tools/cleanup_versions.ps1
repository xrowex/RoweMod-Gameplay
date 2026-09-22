# Cleanup only successful RoweMod-owned copies. Never sweep Downloads or game files.
param([string]$GameDirectory, [string]$InstalledVersion)

function Test-RoweModTree([string]$Path) {
    $item = Get-Item -LiteralPath $Path -Force -ErrorAction Stop
    if ($item.Attributes -band [IO.FileAttributes]::ReparsePoint) { return $false }
    if ($item.PSIsContainer) {
        foreach ($child in Get-ChildItem -LiteralPath $Path -Force) {
            if (-not (Test-RoweModTree $child.FullName)) { return $false }
        }
    }
    return $true
}
function Remove-RoweModCopy([string]$Root, [string]$Candidate) {
    # Require an immediate child of an explicit cache root; reject junctions
    # anywhere in the root chain or candidate before recursive deletion.
    $base = [IO.Path]::GetFullPath($Root).TrimEnd('\')
    $target = [IO.Path]::GetFullPath($Candidate).TrimEnd('\')
    if (-not [string]::Equals((Split-Path $target),$base,[StringComparison]::OrdinalIgnoreCase)) { throw 'Cleanup outside owned cache root' }
    $ancestor = $base
    while ($ancestor) {
        $item = Get-Item -LiteralPath $ancestor -Force
        if ($item.Attributes -band [IO.FileAttributes]::ReparsePoint) { return $false }
        $ancestor = Split-Path $ancestor
    }
    if (-not (Test-RoweModTree $target)) { return $false }
    $resolved = (Resolve-Path -LiteralPath $target).ProviderPath
    if (-not [string]::Equals($resolved.TrimEnd('\'),$target,[StringComparison]::OrdinalIgnoreCase)) { throw 'Cleanup target changed' }
    Remove-Item -LiteralPath $resolved -Recurse -Force -ErrorAction Stop
    return $true
}
function Invoke-RoweModCleanup([string]$GameDirectory, [string]$InstalledVersion) {
    $game = [IO.Path]::GetFullPath($GameDirectory).TrimEnd('\')
    $version = [version]$InstalledVersion
    $state = Join-Path $env:LOCALAPPDATA 'RoweMod'
    $backups = Join-Path $state 'Backups'
    $staging = Join-Path $state 'InstallStaging'
    $updates = Join-Path $state 'Updates'
    $removed = 0
    $eligible = @()
    foreach ($dir in @(Get-ChildItem -LiteralPath $backups -Directory -ErrorAction SilentlyContinue)) {
        if ($dir.Name -notmatch '^Install-\d{8}-\d{6}-[a-f0-9]{6}$' -or ($dir.Attributes -band [IO.FileAttributes]::ReparsePoint)) { continue }
        if (-not (Test-Path -LiteralPath (Join-Path $dir.FullName 'receipt.json'))) { continue }
        try {
            $receipt = Get-Content -LiteralPath (Join-Path $dir.FullName 'receipt.json') -Raw | ConvertFrom-Json
            if (-not [string]::Equals($receipt.game,$game,[StringComparison]::OrdinalIgnoreCase) -or [version]$receipt.version -gt $version) { continue }
            $eligible += $dir
            # Successful receipt proves this corresponding install copy finished.
            $copy = Join-Path $staging $dir.Name.Substring(8)
            if (Test-Path -LiteralPath $copy) {
                if (Remove-RoweModCopy $staging $copy) { $removed++ }
            }
        } catch { Write-Warning "Kept cleanup candidate $($dir.Name): $($_.Exception.Message)" }
    }
    foreach ($dir in @($eligible | Sort-Object CreationTimeUtc,Name -Descending | Select-Object -Skip 2)) {
        try { if (Remove-RoweModCopy $backups $dir.FullName) { $removed++ } }
        catch { Write-Warning "Kept backup $($dir.Name): $($_.Exception.Message)" }
    }
    # The checker holds this same file while preparing a package. Skip cleanup
    # if it is busy; never race a download, extraction or pending-status write.
    $cacheLock = $null
    if (Test-Path -LiteralPath $updates) {
        try {
            $cacheLock = [IO.File]::Open((Join-Path $updates 'online.lock'),'OpenOrCreate','ReadWrite','None')
            foreach ($dir in @(Get-ChildItem -LiteralPath $updates -Directory)) {
                if ($dir.Name -notmatch '^release-\d+\.\d+\.\d+-[a-zA-Z0-9_-]+$' -or ($dir.Attributes -band [IO.FileAttributes]::ReparsePoint)) { continue }
                try {
                    $owner = Get-Content -LiteralPath (Join-Path $dir.FullName '.rowemod-update.json') -Raw -ErrorAction Stop | ConvertFrom-Json
                    if ($owner.owner -ne 'RoweMod-Gameplay' -or -not [string]::Equals($owner.game,$game,[StringComparison]::OrdinalIgnoreCase) -or [version]$owner.version -gt $version) { continue }
                    if (Remove-RoweModCopy $updates $dir.FullName) { $removed++ }
                } catch { Write-Verbose "Kept update cache $($dir.Name): $($_.Exception.Message)" }
            }
        } catch [IO.IOException] { Write-Verbose 'Update cache is in use; cleanup will retry after another install.' }
        finally { if ($cacheLock) { $cacheLock.Dispose() } }
    }
    Write-Host "Cleanup removed $removed completed copies; kept the two newest recovery backups."
}
if ($GameDirectory -and $InstalledVersion) { Invoke-RoweModCleanup $GameDirectory $InstalledVersion }
