"""Fetch pinned first-party browser inference assets, verifying every byte hash."""
import base64,hashlib,io,json,tarfile,urllib.request
from pathlib import Path
ROOT=Path(__file__).resolve().parents[1]
manifest=json.loads((ROOT/'scripts/face-browser-assets.json').read_text())
destination=ROOT/'apps/mobile/web/face-models'/manifest['version']
archive=None
for asset in manifest['files']:
 target=destination/asset['file']
 if target.exists() and target.stat().st_size==asset['bytes'] and hashlib.sha256(target.read_bytes()).hexdigest()==asset['sha256']:continue
 if asset['source'].startswith('npm:'):
  if archive is None:
   with urllib.request.urlopen(manifest['npm']['tarball'],timeout=90) as response:packed=response.read()
   assert 'sha512-'+base64.b64encode(hashlib.sha512(packed).digest()).decode()==manifest['npm']['integrity'],'Package integrity mismatch'
   archive=tarfile.open(fileobj=io.BytesIO(packed),mode='r:gz')
  raw=archive.extractfile('package/'+asset['file']).read()
 else:
  with urllib.request.urlopen(asset['source'],timeout=90) as response:raw=response.read()
 assert len(raw)==asset['bytes'] and hashlib.sha256(raw).hexdigest()==asset['sha256'],'Face asset integrity mismatch'
 target.parent.mkdir(parents=True,exist_ok=True);target.write_bytes(raw)
print('Pinned automatic face tracker assets ready')
