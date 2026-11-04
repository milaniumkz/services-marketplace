"""Read production diagnostics through a protected workflow; never publish plaintext."""
import argparse,base64,datetime,json,os,subprocess,tempfile,time
from pathlib import Path
p=argparse.ArgumentParser();p.add_argument('--ref',default='feat/joba-implementation');p.add_argument('--output',required=True);args=p.parse_args()
root=Path(__file__).resolve().parents[1]
def run(command,input=None):return subprocess.check_output(command,input=input,cwd=root,stderr=subprocess.PIPE)
started=datetime.datetime.now(datetime.timezone.utc).replace(microsecond=0)
with tempfile.TemporaryDirectory(prefix='joba-crash-reader-') as temporary:
 folder=Path(temporary);private=folder/'reader.pem'
 subprocess.run(['openssl','genpkey','-algorithm','RSA','-pkeyopt','rsa_keygen_bits:2048','-out',str(private)],check=True,capture_output=True);private.chmod(0o600)
 public=base64.b64encode(run(['openssl','pkey','-in',str(private),'-pubout','-outform','DER'])).decode()
 repo=json.loads(run(['gh','repo','view','--json','nameWithOwner']))['nameWithOwner']
 run(['gh','api','--method','POST',f'repos/{repo}/actions/workflows/server-diagnostics.yml/dispatches','--input','-'],json.dumps({'ref':args.ref,'inputs':{'mobile_crashes':True,'diagnostic_public_key':public}}).encode())
 selected=None
 for attempt in range(24):
  rows=json.loads(run(['gh','run','list','--workflow','server-diagnostics.yml','--branch',args.ref,'--event','workflow_dispatch','--limit','10','--json','databaseId,createdAt']))
  matches=[r for r in rows if datetime.datetime.fromisoformat(r['createdAt'].replace('Z','+00:00'))>=started]
  if matches:selected=max(matches,key=lambda r:r['databaseId']);break
  time.sleep(2)
 if not selected:raise SystemExit('Workflow run was not found')
 run_id=str(selected['databaseId']);print(f'Reading protected diagnostics: https://github.com/{repo}/actions/runs/{run_id}',flush=True)
 run(['gh','run','watch',run_id,'--exit-status','--interval','5'])
 run(['gh','run','download',run_id,'--name','account-diagnosis','--dir',str(folder/'artifact')])
 envelope=json.loads((folder/'artifact/account-diagnosis.json').read_text());aad='joba-mobile-crashes:'+run_id
 if envelope.get('aad')!=aad:raise SystemExit('Diagnostic export context mismatch')
 plain=run(['node','scripts/firebase-envelope.cjs'],json.dumps({'mode':'decrypt','private_path':str(private),'aad':aad,'envelope':envelope}).encode())
 data=json.loads(plain);target=Path(args.output);target.parent.mkdir(parents=True,exist_ok=True)
 fd=os.open(target,os.O_WRONLY|os.O_CREAT|os.O_TRUNC,0o600)
 with os.fdopen(fd,'wb') as stream:stream.write(plain)
 target.chmod(0o600)
 print(json.dumps({'read_only':True,'reports':len(data.get('reports',[])),'output':str(target)}))
