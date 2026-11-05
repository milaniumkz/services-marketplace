"""Read-only deployment process health; never prints arguments, env or accounts."""
import datetime,json,os,re,subprocess
from pathlib import Path

def run(args):
 try:
  p=subprocess.run(args,stdout=subprocess.PIPE,stderr=subprocess.PIPE,text=True,timeout=15)
  return {'exit':p.returncode,'output':p.stdout[-12000:]}
 except subprocess.TimeoutExpired:return {'timeout':True}
markers={}
for name in ['mobile-api-release']:
 p=Path('/etc/joba')/name
 if p.is_file():
  value=p.read_text().strip()
  markers[name]=value if re.fullmatch('[0-9a-f]{40}',value) else 'invalid'
print(json.dumps({'checked_at':datetime.datetime.now(datetime.timezone.utc).isoformat(),
 'read_only':True,'load':list(os.getloadavg()),'release_markers':markers,
 'processes':run(['ps','-eo','pid,ppid,etimes,pcpu,pmem,comm','--sort=-pcpu']),
 'containers':run(['docker','ps','--format','{{.Names}} {{.Status}}']),
 'deployment_locks':run(['lslocks','--noheadings','--output','PID,COMMAND,PATH']),
 'disk':run(['df','-h','/opt/joba']),
 'memory':run(['free','-m'])},ensure_ascii=False))
