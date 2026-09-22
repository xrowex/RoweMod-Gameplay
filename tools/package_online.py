"""Create a reproducible-input friend test ZIP; excludes logs and user state."""
import argparse
import hashlib
import json
import os
import sys
import zipfile
from pathlib import Path


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--out', type=Path, required=True)
    parser.add_argument('--build-deps', type=Path, default=Path(os.environ['TEMP']) / 'RoweModOnline-build-deps')
    args = parser.parse_args()
    repo = Path(__file__).resolve().parents[1]
    names = ['version.json', 'tools/steam_paths.ps1', 'tools/ue4ss-runtime.json', 'tools/online_updater.py', 'tools/apply_update.ps1', 'install.cmd', 'install.ps1', 'START ONLINE.cmd', 'LICENSE',
             'tools/deps/RoweModOnline.exe', 'tools/mp_online.cmd', 'tools/start_online.vbs',
             'tools/menu_control.py', 'tools/mp_online.py', 'tools/steam_mp.py', 'tools/steamworks.py', 'tools/rowemod_mp.py',
             'docs/steam-online.md', 'docs/multiplayer.md', 'docs/steam-friend-test.md',
             'docs/auto-updates.md', 'docs/in-game-menu.md', 'docs/slider-audit.md', 'docs/licenses/ModMenu.txt', 'docs/third-party-online.md', 'docs/proofs/steam-probe-20260921.json',
             'docs/proofs/steam-native-20260921.json']
    files = {name: repo / name for name in names}
    runtime = json.loads((repo/'tools/ue4ss-runtime.json').read_text())
    for name, digest in runtime['sha256'].items():
        rel = 'tools/deps/ue4ss-runtime/' + name
        path = repo / rel
        if hashlib.sha256(path.read_bytes()).hexdigest() != digest:
            raise RuntimeError('Pinned runtime checksum mismatch: ' + name)
        files[rel] = path
    for path in (repo / 'ue4ss/Mods/RoweModGameplay').rglob('*'):
        if path.is_file() and path.suffix == '.lua':
            files[path.relative_to(repo).as_posix()] = path
    files['README FIRST.md'] = repo / 'docs/steam-friend-test.md'
    python = Path(sys.base_prefix)
    files.update({'licenses/Python.txt': python / 'LICENSE.txt',
                  'licenses/Tcl.txt': repo / 'docs/licenses/Tcl.txt',
                  'licenses/Tk.txt': python / 'tcl/tk8.6/license.terms'})
    licenses = list(args.build_deps.glob('pyinstaller-*.dist-info/licenses/COPYING.txt'))
    if len(licenses) != 1:
        raise RuntimeError('Expected one PyInstaller runtime license')
    files['licenses/PyInstaller.txt'] = licenses[0]
    for name, path in files.items():
        if not path.is_file():
            raise FileNotFoundError(str(path))
    args.out.parent.mkdir(parents=True, exist_ok=True)
    manifest = {}
    # Exclusive creation prevents replacing a package already sent for testing.
    with zipfile.ZipFile(args.out, 'x', zipfile.ZIP_DEFLATED) as archive:
        for name, path in sorted(files.items()):
            data = path.read_bytes()
            archive.writestr(name, data)
            manifest[name] = hashlib.sha256(data).hexdigest()
        archive.writestr('manifest.json', json.dumps({'protocol': 'steam-1', 'sha256': manifest}, indent=2))
    with zipfile.ZipFile(args.out) as archive:
        assert archive.testzip() is None
        for name, digest in manifest.items():
            assert hashlib.sha256(archive.read(name)).hexdigest() == digest
    version = json.loads((repo/'version.json').read_text())['version']
    update = dict(version=version, asset=args.out.name, bytes=args.out.stat().st_size,
                  sha256=hashlib.sha256(args.out.read_bytes()).hexdigest())
    # Put each release in its own output directory; never replace an already-published manifest.
    update_path = args.out.parent/'update.json'
    with update_path.open('x', encoding='utf-8') as f:
        json.dump(update, f, indent=2)
    print(json.dumps({'zip': str(args.out.resolve()), 'files': len(files),
                      'bytes': args.out.stat().st_size,
                      'sha256': hashlib.sha256(args.out.read_bytes()).hexdigest()}, indent=2))


if __name__ == '__main__':
    main()
