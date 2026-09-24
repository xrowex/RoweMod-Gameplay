"""Exercise the real deferred PowerShell installer with a local release fixture."""
import json
import hashlib
import os
import shutil
import subprocess
import sys
import tempfile
import time
from pathlib import Path

repo = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(repo/'tools'))
import online_updater as updater


def main():
    target_version = json.loads((repo/'version.json').read_text())['version']
    root = Path(tempfile.mkdtemp(prefix='RoweMod-UpdateProof-'))
    game = root/'Game With Spaces/Binaries/Win64'
    game.mkdir(parents=True)
    (game/'RollerSkate-Win64-Shipping.exe').write_text('test fixture; never executed')
    (game/'RoweModOnline').mkdir()
    (game/'RoweModOnline/version.json').write_text('{"version":"0.4.0"}')
    shutil.copy2(repo/'tools/apply_update.ps1', game/'RoweModOnline/apply_update.ps1')
    env = dict(os.environ, LOCALAPPDATA=str(root/'AppData'))
    runner = root/'runner.py'
    runner.write_text('''import sys,json,time
from pathlib import Path
sys.path.insert(0,sys.argv[1])
import online_updater as u
game,release,ready,done=map(Path,sys.argv[2:])
manifest=json.loads((release/'update.json').read_text())
tag='v'+manifest['version']
base='https://github.com/'+u.REPOSITORY+'/releases/download/'+tag+'/'
metadata=dict(tag_name=tag,draft=False,prerelease=False,assets=[dict(name=n,browser_download_url=base+n) for n in ['update.json',manifest['asset']]])
downloads=[]
def fetch(url,limit):
    if url.endswith(".zip"): downloads.append(url)
    if url==u.LATEST: return json.dumps(metadata).encode()
    return (release/url.rsplit('/',1)[-1]).read_bytes()
result=u.check(game,fetch)
again=u.check(game,fetch)
assert result.get('package')==again.get('package'), (result,again)
assert len(downloads)==1, downloads
ready.write_text(json.dumps(result))
while not done.exists(): time.sleep(.1)
''')
    ready, done = root/'ready.json', root/'close-parent'
    release_dir = Path(sys.argv[1]) if len(sys.argv)>1 else repo/('dist/'+target_version)
    process = subprocess.Popen([sys.executable, str(runner), str(repo/'tools'), str(game), str(release_dir.resolve()), str(ready), str(done)], env=env)
    try:
        deadline = time.monotonic()+40
        while not ready.exists() and time.monotonic()<deadline:
            if process.poll() is not None: raise RuntimeError('Update check process exited unexpectedly')
            time.sleep(.1)
        status = json.loads(ready.read_text())
        assert 'Update ready' in status['message'], status
        staged_package=Path(status['package'])
        # Hold the updater's parent alive. The deferred worker must not install.
        time.sleep(6)
        assert json.loads((game/'RoweModOnline/version.json').read_text())['version']=='0.4.0'
        done.touch();process.wait(timeout=10)
        deadline = time.monotonic()+35
        status_path=root/'AppData/RoweMod/Updates/status.json'
        while time.monotonic()<deadline:
            try:
                status=json.loads(status_path.read_text(encoding='utf-8-sig'))
                if status.get('installed')==target_version: break
                if 'failed' in status.get('message','').lower(): raise RuntimeError(status)
            except (FileNotFoundError,json.JSONDecodeError): pass
            time.sleep(.25)
        assert status.get('installed')==target_version,status
        assert not staged_package.parent.exists(), 'Completed download/extraction cache remained'
        assert not list((root/'AppData/RoweMod/InstallStaging').iterdir()), 'Completed install staging remained'
        assert (game/'ue4ss/UE4SS.dll').is_file()
        assert (game/'ue4ss/Mods/RoweModGameplay/Scripts/rowe_menu.lua').is_file()
        body_hashes = json.loads((repo/'assets/skeleton/manifest.json').read_text())['sha256']
        for name, digest in body_hashes.items():
            installed = game.parent.parent/'Content/Paks/~mods'/name
            assert hashlib.sha256(installed.read_bytes()).hexdigest() == digest, name
        assert list((root/'AppData/RoweMod/Backups').glob('Install-*/receipt.json'))
        # Run the packaged standalone updater against the actual GitHub endpoint.
        # A current/newer fixture must not downgrade to the public stable release.
        exe=game/'RoweModOnline/RoweModOnline.exe'
        run=subprocess.run([str(exe),'--check-updates','--game',str(game/'RollerSkate-Win64-Shipping.exe')],env=env,timeout=60)
        assert run.returncode==0
        live=json.loads(status_path.read_text(encoding='utf-8-sig'))
        assert live['message'] in ('No published update release yet','Up to date'),live
        proof=dict(root=str(root),held_parent_prevented_install=True,deferred_install='0.4.0 -> '+target_version,
                   ue4ss_installed=True,skeleton_automatically_installed=True,backup_receipt=True,pending_download_reused=True,completed_caches_removed=True,packaged_exe_live_check=live)
        (repo/('docs/proofs/auto-update-'+target_version+'.json')).write_text(json.dumps(proof,indent=2)+'\n')
        print(json.dumps(proof,indent=2))
    finally:
        done.touch()
        process.wait(timeout=10)


if __name__=='__main__': main()
