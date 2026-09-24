# Automatic updates

The complete release ZIP bundles the UE4SS runtime from commit `f6d5f942`, its MIT license, the RoweMod scripts, standalone Online executable, and skeleton body. Extract it and run `install.cmd`; no Python or separate UE4SS setup is required. The installer can request administrator access if the Steam library requires it.

On game launch, a windowless updater checks the latest stable release from `xrowex/RoweMod-Gameplay`. It does not load Steam or open the companion UI. Only newer three-part versions are accepted; drafts, prereleases and downgrades are ignored. The first public installer release is 0.5.1.

The checker downloads `update.json` and its named ZIP from that same repository's release. It validates the ZIP's SHA-256, size, every packaged file hash, archive paths and packaged version. This trusts the repository's published release over HTTPS; these checks detect damage and mismatched packages, but are not a separate publisher signature.

Starting with 0.5.7, the same verified release download includes the skeleton mesh, materials and body-selector entry. The installer updates the three owned `RoweSkeleton_P` files in `Content/Paks/~mods`; no second download or installation is needed. Other clothing packages remain untouched.

A separate worker waits until Rollout and RoweMod Online exit. It then runs the staged installer. It never terminates the game. The background companion launched from the in-game menu exits when Rollout closes; if you opened the desktop companion, close it too. An offline or failed update check does not block gameplay.

The installer snapshots every destination file before replacement, preserves existing `config.lua`, saved menu settings and unrelated mods, and attempts rollback on a copy failure. An installation needing elevation is not silently elevated by the updater: run the staged `install.cmd` once if its status says administrator access is needed. The game directory must remain closed during installation.

After a successful installation, RoweMod removes its completed installation copies and updater-owned downloads/extracted packages. It retains the **two newest successful recovery backups per game installation**, plus failed/incomplete backups. Cleanup skips newer pending updates, active downloads, unknown folders and linked directories. It never scans Downloads, deletes your manually extracted ZIPs, or removes GitHub releases, other mods, saves or settings.

Repeated update checks reuse an already verified pending package instead of downloading it again. The cache ownership markers start with 0.5.5; older unmarked download folders are left alone. Older successful installation-staging copies are recognized through their backup receipts.

Status and recovery:

- `%LOCALAPPDATA%\RoweMod\Updates\status.json`: checked/current/available version, pending package or failure details.
- `%LOCALAPPDATA%\RoweMod\Updates\install.log`: installer output.
- `%LOCALAPPDATA%\RoweMod\Backups\Install-*`: previous files and receipt. Restore these with the game closed if needed. Runtime paths restore under `Binaries/Win64`; entries under `GameContent/Paks/~mods` restore under the game's `Content/Paks/~mods`. The receipt records their destinations.

## Publishing an update

1. Update `version.json` to a higher `major.minor.patch` version; commit and push the release source.
2. Run `tools/build_online.ps1`, the test suites, and `tools/package_online.py --out dist/<version>/RoweMod-<version>.zip`.
3. Publish a stable GitHub Release tagged `v<version>` against that source commit. Attach both the generated ZIP and the adjacent `update.json`. These two files must stay together and must not be modified after publishing. Mark it as the latest release.

The updater reads GitHub Releases, not arbitrary changes pushed to a branch. UE4SS changes only when a RoweMod release intentionally bundles a newly tested runtime; it does not follow UE4SS's moving experimental-latest download. The runtime file hashes and source commit are recorded in `tools/ue4ss-runtime.json`.

Release packaging includes the licensed anatomical skeleton and its selector-table patch, but excludes original game meshes/textures, private saved settings, logs, crash dumps, and personal clothing mods. Runtime binaries are ignored by Git and distributed as release assets.
