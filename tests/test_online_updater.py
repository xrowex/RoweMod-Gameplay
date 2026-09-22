import hashlib
import json
import sys
import tempfile
import unittest
import zipfile
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / 'tools'))
import online_updater as u


class UpdateTests(unittest.TestCase):
    def release(self, tag='v0.6.0'):
        return dict(tag_name=tag, draft=False, prerelease=False, assets=[
            dict(name=name, browser_download_url=f'https://github.com/{u.REPOSITORY}/releases/download/{tag}/{name}')
            for name in ['update.json', 'RoweMod-0.6.0.zip']])

    def test_only_newer_stable(self):
        manifest = dict(version='0.6.0', asset='RoweMod-0.6.0.zip', bytes=12, sha256='a'*64)
        self.assertIsNotNone(u.select_update(self.release(), '0.5.0', lambda *_: json.dumps(manifest).encode()))
        self.assertIsNone(u.select_update(self.release(), '0.6.0'))
        self.assertIsNone(u.select_update(self.release(), '1.0.0'))
        release = self.release(); release['prerelease'] = True
        self.assertIsNone(u.select_update(release, '0.5.0'))
        release['prerelease'] = False; release['draft'] = True
        self.assertIsNone(u.select_update(release, '0.5.0'))

    def test_reject_external_location_and_mismatched_version(self):
        release = self.release(); release['assets'][0]['browser_download_url'] = 'https://example.com/update.json'
        with self.assertRaises(ValueError): u.select_update(release, '0.5.0')
        with self.assertRaises(ValueError):
            u.select_update(self.release(), '0.5.0', lambda *_: b'{"version":"0.7.0"}')

    def archive(self, folder, extras=None):
        files = {'version.json': b'{"version":"0.6.0"}', 'install.ps1': b'installer',
                 'tools/apply_update.ps1': b'worker', 'tools/deps/RoweModOnline.exe': b'exe'}
        files.update(extras or {})
        manifest = {name: hashlib.sha256(data).hexdigest() for name, data in files.items()}
        path = Path(folder)/'download.zip'
        with zipfile.ZipFile(path, 'w') as z:
            for name, data in files.items(): z.writestr(name, data)
            z.writestr('manifest.json', json.dumps(dict(sha256=manifest)))
        return path, dict(version='0.6.0', bytes=path.stat().st_size, sha256=hashlib.sha256(path.read_bytes()).hexdigest())

    def test_verified_bundle_extracts(self):
        with tempfile.TemporaryDirectory() as folder:
            path, manifest = self.archive(folder)
            u.unpack(path, Path(folder)/'out', manifest)
            self.assertEqual((Path(folder)/'out/install.ps1').read_text(), 'installer')

    def test_corrupt_bundle_rejected_before_extract(self):
        with tempfile.TemporaryDirectory() as folder:
            path, manifest = self.archive(folder)
            manifest['sha256'] = '0'*64
            with self.assertRaises(ValueError): u.unpack(path, Path(folder)/'out', manifest)
            self.assertFalse((Path(folder)/'out').exists())

    def test_zip_traversal_and_windows_aliases_rejected(self):
        for name in ['../outside', '/absolute', 'C:/absolute', 'bad\\file', 'foo./x', 'VERSION.JSON']:
            with self.subTest(name=name), tempfile.TemporaryDirectory() as folder:
                path, manifest = self.archive(folder, {name:b'bad'})
                with self.assertRaises(ValueError): u.unpack(path, Path(folder)/'out', manifest)
                self.assertFalse((Path(folder)/'out').exists())

    def test_packaged_version_must_match_release(self):
        with tempfile.TemporaryDirectory() as folder:
            path, manifest = self.archive(folder)
            manifest['version'] = '0.7.0'
            with self.assertRaises(ValueError): u.unpack(path, Path(folder)/'out', manifest)


if __name__ == '__main__': unittest.main()
