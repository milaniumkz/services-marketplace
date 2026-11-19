"""Encrypt diagnostics before any Actions logging or artifact publication."""
import json,os,subprocess
from pathlib import Path
source=Path('account-diagnosis.json')
payload=json.loads(source.read_text())
public=os.environ.get('JOBA_DIAGNOSTIC_PUBLIC_KEY','')
if not public:raise SystemExit('Ephemeral diagnostic public key is required; plaintext export is not published')
envelope=subprocess.run(['node','scripts/firebase-envelope.cjs'],input=json.dumps({'mode':'encrypt','public_key_der':public,'aad':'joba-mobile-crashes:'+os.environ['JOBA_DIAGNOSTIC_RUN_ID'],'payload':payload}).encode(),capture_output=True,check=True)
source.write_bytes(envelope.stdout)
print(json.dumps({'encrypted':True,'reports':len(payload.get('reports',[])),'read_only':True}))
