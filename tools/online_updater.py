"""Stable GitHub release updates: verify, stage, then install after the game exits."""
import hashlib
import json
import os
import re
import subprocess
import tempfile
import time
import urllib.error
import urllib.request
import zipfile
from pathlib import Path, PurePosixPath

REPOSITORY = 'xrowex/RoweMod-Gameplay'
LATEST = 'https://api.github.com/repos/' + REPOSITORY + '/releases/latest'
MAX_ZIP = 150 * 1024 * 1024


def version(value):
    if not isinstance(value, str) or not re.fullmatch(r'v?\d{1,5}\.\d{1,5}\.\d{1,5}', value):
        raise ValueError('Invalid update version')
    return tuple(int(part) for part in value.lstrip('v').split('.'))


def fetch(url, limit):
    request = urllib.request.Request(url, headers={'User-Agent': 'RoweMod-Updater', 'Accept': 'application/vnd.github+json' if 'api.github.com' in url else 'application/octet-stream'})
    with urllib.request.urlopen(request, timeout=20) as response:
        data = response.read(limit + 1)
    if len(data) > limit:
        raise ValueError('Update download exceeds size limit')
    return data


def asset_url(release, name):
    tag = release['tag_name']
    version(tag)
    matches = [a for a in release.get('assets', []) if a.get('name') == name]
    if len(matches) != 1:
        raise ValueError('Release is missing ' + name)
    url = matches[0]['browser_download_url']
    expected = 'https://github.com/' + REPOSITORY + '/releases/download/' + tag + '/' + name
    if url != expected:
        raise ValueError('Unexpected update download location')
    return url


def select_update(release, current, read=fetch):
    if release.get('draft') or release.get('prerelease') or version(release['tag_name']) <= version(current):
        return None
    manifest = json.loads(read(asset_url(release, 'update.json'), 8192))
    if version(manifest['version']) != version(release['tag_name']):
        raise ValueError('Update tag and manifest disagree')
    name = manifest['asset']
    if not re.fullmatch(r'RoweMod-[A-Za-z0-9._-]+\.zip', name):
        raise ValueError('Invalid update asset name')
    if not re.fullmatch(r'[a-f0-9]{64}', manifest['sha256']) or not 0 < manifest['bytes'] <= MAX_ZIP:
        raise ValueError('Invalid update checksum or size')
    manifest['url'] = asset_url(release, name)
    return manifest


def unpack(archive, target, expected):
    raw = archive.read_bytes()
    if len(raw) != expected['bytes'] or hashlib.sha256(raw).hexdigest() != expected['sha256']:
        raise ValueError('Update archive checksum mismatch')
    with zipfile.ZipFile(archive) as z:
        seen, total = set(), 0
        for info in z.infolist():
            name = info.filename
            path = PurePosixPath(name)
            if not name or '\\' in name or ':' in name or path.is_absolute() or any(p in ('..', '') or p.endswith(('.', ' ')) for p in path.parts):
                raise ValueError('Unsafe update archive path')
            if name.lower() in seen or ((info.external_attr >> 16) & 0o170000) == 0o120000:
                raise ValueError('Duplicate path or symlink in update')
            seen.add(name.lower())
            total += info.file_size
            if total > 400 * 1024 * 1024 or len(seen) > 2000:
                raise ValueError('Update archive expands beyond limit')
        manifest = json.loads(z.read('manifest.json'))['sha256']
        for info in z.infolist():
            if info.is_dir() or info.filename == 'manifest.json':
                continue
            if hashlib.sha256(z.read(info)).hexdigest() != manifest.get(info.filename):
                raise ValueError('Update file checksum mismatch: ' + info.filename)
        for name in ('install.ps1', 'tools/apply_update.ps1', 'version.json', 'tools/deps/RoweModOnline.exe'):
            if name not in manifest:
                raise ValueError('Incomplete update bundle')
        if version(json.loads(z.read('version.json'))['version']) != version(expected['version']):
            raise ValueError('Packaged version mismatch')
        z.extractall(target)


def check(game, read=fetch):
    game = Path(game).resolve()
    root = Path(os.environ['LOCALAPPDATA']) / 'RoweMod/Updates'
    root.mkdir(parents=True, exist_ok=True)
    current = json.loads((game/'RoweModOnline/version.json').read_text())['version']
    status_path = root/'status.json'

    def status(message, **extra):
        data = dict(message=message, checked=int(time.time()), current=current, **extra)
        status_path.write_text(json.dumps(data, indent=2), encoding='utf-8')
        return data

    try:
        # A cross-process check lock also covers launches from both Steam and the companion.
        from mp_online import InstanceLock
        lock = InstanceLock(root)
        if not lock.file:
            return {'message': 'Another update check is running'}
        try:
            release = json.loads(read(LATEST, 1024*1024))
            update = select_update(release, current, read)
            if not update:
                return status('Up to date')
            stage = Path(tempfile.mkdtemp(prefix='release-' + update['version'] + '-', dir=str(root)))
            archive = stage/'download.zip'
            archive.write_bytes(read(update['url'], MAX_ZIP))
            package = stage/'package'
            unpack(archive, package, update)
            # Use the currently installed helper, not a program started from the downloaded ZIP.
            helper = game/'RoweModOnline/apply_update.ps1'
            powershell = Path(os.environ['SystemRoot'])/'System32/WindowsPowerShell/v1.0/powershell.exe'
            child_env = dict(os.environ)
            # Do not inherit a PowerShell 7 module path into Windows PowerShell 5.
            for key in list(child_env):
                if key.upper() == 'PSMODULEPATH': del child_env[key]
            child_env['PSModulePath'] = str(powershell.parent/'Modules')
            subprocess.Popen([str(powershell), '-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', str(helper),
                              '-PackageRoot', str(package), '-GameDirectory', str(game), '-ParentId', str(os.getpid())],
                             creationflags=subprocess.CREATE_NO_WINDOW, close_fds=True, env=child_env)
            return status('Update ready; close Rollout and RoweMod Online to install', available=update['version'], package=str(package))
        finally:
            lock.close()
    except urllib.error.HTTPError as error:
        return status('No published update release yet' if error.code == 404 else 'Update check unavailable; playing is unaffected')
    except Exception as error:
        return status('Update could not be prepared; playing is unaffected', detail=str(error))
