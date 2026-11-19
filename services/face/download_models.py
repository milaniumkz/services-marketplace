import hashlib,json,urllib.request
from pathlib import Path
root=Path(__file__).parent
for model in json.loads((root/'models.json').read_text()):
 target=root/'models'/model['file'];target.parent.mkdir(exist_ok=True)
 if not target.exists() or hashlib.sha256(target.read_bytes()).hexdigest()!=model['sha256']:
  with urllib.request.urlopen(model['url'],timeout=120) as r:data=r.read()
  if len(data)!=model['bytes'] or hashlib.sha256(data).hexdigest()!=model['sha256']:raise RuntimeError('Model integrity check failed')
  target.write_bytes(data)
