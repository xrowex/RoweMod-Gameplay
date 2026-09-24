"""Download the pinned anatomical source, retaining its supplied attribution."""
import hashlib
import urllib.request
from pathlib import Path

ROOT=Path(__file__).resolve().parents[2]
BASE='https://raw.githubusercontent.com/LluisV/Z-Anatomy/6c7f9016bd5899ac8edafd31b9900c151df42ed6/Resources/Models/'
FILES={
    'FBX/SkeletalSystem100.fbx': '294a649765cd060a62a4095da52b9c8ef2d97769aa447e196448aa5f7d596dea',
    'License.txt': 'af62c06f620b9da20138e4c22a3f56565482dd058266540994ace97a4e24b693',
    'Readme.txt': '43eab2cd13ad8be51d20227cad78d427e6078cd91e66a24ae7f947811524c810',
}
def main():
    out=ROOT/'build/skeleton-source';out.mkdir(parents=True,exist_ok=True)
    for remote,digest in FILES.items():
        dest=out/Path(remote).name
        if dest.exists():
            assert hashlib.sha256(dest.read_bytes()).hexdigest()==digest,'Source checksum mismatch: '+str(dest)
            continue
        data=urllib.request.urlopen(BASE+remote,timeout=60).read()
        assert hashlib.sha256(data).hexdigest()==digest,'Downloaded checksum mismatch: '+remote
        dest.write_bytes(data)
    print('Pinned skeleton source verified:',out)
if __name__=='__main__':main()
