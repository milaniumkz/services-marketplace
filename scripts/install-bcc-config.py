"""Atomic BCC-only configuration install/rollback. No other provider files opened.
This is a proposed utility, exercised only under a disposable audit directory.
"""
import os,json,pathlib,hashlib,tempfile,shutil,uuid,importlib.util
spec=importlib.util.spec_from_file_location('bcc_prepare',pathlib.Path(__file__).with_name('prepare-bcc-deployment.py'));module=importlib.util.module_from_spec(spec);spec.loader.exec_module(module)
def digest(data):return hashlib.sha256(data).hexdigest()
def atomic(target,data):
 target=pathlib.Path(target);target.parent.mkdir(parents=True,exist_ok=True)
 fd,name=tempfile.mkstemp(dir=target.parent,prefix='.bcc-');os.fchmod(fd,0o600)
 try:
  with os.fdopen(fd,'wb') as f:f.write(data);f.flush();os.fsync(f.fileno())
  os.replace(name,target);os.chmod(target,0o600)
 finally:
  if os.path.exists(name):os.unlink(name)
def apply(raw,target,backup_root,preflight=None):
 target=pathlib.Path(target);backup_root=pathlib.Path(backup_root)
 with tempfile.TemporaryDirectory() as temp:
  prepared=module.prepare(raw,temp);data=prepared.read_bytes()
  if preflight is not None and not preflight(json.loads(data)):raise ValueError('Bank preflight rejected; configuration untouched')
 before=target.read_bytes() if target.exists() else None
 backup_root.mkdir(parents=True,exist_ok=True,mode=0o700);os.chmod(backup_root,0o700)
 key=uuid.uuid4().hex;backup=backup_root/(key+'.previous.json');receipt=backup_root/(key+'.receipt.json')
 if before is not None:atomic(backup,before)
 atomic(receipt,json.dumps({'before_exists':before is not None,'before_sha':digest(before) if before else None,'after_sha':digest(data),'backup':backup.name}).encode())
 atomic(target,data);return receipt
def rollback(receipt,target):
 receipt=pathlib.Path(receipt);target=pathlib.Path(target);r=json.loads(receipt.read_bytes())
 if not target.exists() or digest(target.read_bytes())!=r['after_sha']:raise ValueError('BCC configuration changed since install; explicit reconciliation required')
 backup=(receipt.parent/r['backup']).resolve()
 if backup.parent!=receipt.parent.resolve():raise ValueError('Invalid backup path')
 if r['before_exists']:
  before=backup.read_bytes()
  if digest(before)!=r['before_sha']:raise ValueError('Backup integrity mismatch')
  atomic(target,before)
 else:target.unlink()

if __name__=='__main__':
 import sys
 try:
  if len(sys.argv)!=3 or sys.argv[1] not in ('apply','rollback'):raise ValueError('Invalid bank installation command')
  target=pathlib.Path('/etc/joba/payments/bcc.json')
  if sys.argv[1]=='apply':
   source=pathlib.Path(sys.argv[2]);raw=source.read_text();candidate=json.loads(raw)
   if target.exists() and json.loads(target.read_text()).get('environment')=='production' and candidate.get('environment')!='production':raise ValueError('Automatic production downgrade forbidden')
   receipt=apply(raw,target,'/var/backups/joba/bcc');os.chown(target,1000,1000)
   print('BCC configuration installed atomically; private backup receipt: '+str(receipt))
  else:
   receipt=pathlib.Path(sys.argv[2]).resolve()
   if receipt.parent!=pathlib.Path('/var/backups/joba/bcc').resolve():raise ValueError('Unexpected backup location')
   rollback(receipt,target)
   if target.exists():os.chown(target,1000,1000)
   print('BCC configuration restored from protected backup')
 except Exception:
  print('BCC installation failed; private configuration values were not logged');raise SystemExit(1)
