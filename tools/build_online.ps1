param(
    [string]$SteamApi = "E:\unreal\UE_5.4\Engine\Binaries\ThirdParty\Steamworks\Steamv157\Win64\steam_api64.dll",
    [string]$BuildDependencies = "$env:TEMP\RoweModOnline-build-deps"
)
$ErrorActionPreference = "Stop"
$repo = (Resolve-Path (Join-Path $PSScriptRoot "..")).Path
$dll = (Resolve-Path -LiteralPath $SteamApi).Path
$savedPythonPath = $env:PYTHONPATH
try {
    if (Test-Path -LiteralPath $BuildDependencies) { $env:PYTHONPATH = $BuildDependencies }
    & python -m PyInstaller --noconfirm --onefile --windowed --name RoweModOnline `
        --distpath (Join-Path $PSScriptRoot "deps") `
        --workpath (Join-Path $repo "build\online") `
        --specpath (Join-Path $repo "build\online") `
        --add-binary "$dll;deps" (Join-Path $PSScriptRoot "mp_online.py")
    if ($LASTEXITCODE -ne 0) { throw "PyInstaller failed" }
} finally {
    $env:PYTHONPATH = $savedPythonPath
}
