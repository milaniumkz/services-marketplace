"""Read-only deployment process health; never prints arguments, env or accounts."""
import datetime,json,os,re,signal,subprocess,sys
from pathlib import Path

def run(args):
 try:
  p=subprocess.run(args,stdout=subprocess.PIPE,stderr=subprocess.PIPE,text=True,timeout=15)
  return {'exit':p.returncode,'output':p.stdout[-12000:]}
 except subprocess.TimeoutExpired:return {'timeout':True}
stopped=[]
if len(sys.argv)>1:
 commit=sys.argv[1]
 if not re.fullmatch('[0-9a-f]{40}',commit):raise SystemExit('Invalid source commit')
 source='/opt/joba/mobile-releases/'+commit
 # Only stop an overdue fetch for this exact release, never a deployment shell,
 # checkout, database or service. Fetch has not changed the running release.
 for entry in Path('/proc').iterdir():
  if not entry.name.isdigit():continue
  try:
   args=(entry/'cmdline').read_bytes().split(b'\0')[:-1]
   args=[a.decode() for a in args]
   expected=['git','-C',source,'fetch','--depth=1','origin',commit]
   if args!=expected:continue
   age=int(subprocess.check_output(['ps','-o','etimes=','-p',entry.name],text=True).strip())
   if age<600:continue
   # Descendants are fetch helpers. Select ancestry before signalling, so PID
   # matches cannot reach other admin operations or application containers.
   rows=subprocess.check_output(['ps','-eo','pid=,ppid='],text=True).splitlines()
   tree=[(int(a),int(b)) for a,b in (row.split() for row in rows)]
   owned={int(entry.name)}
   while True:
    expanded=owned|{pid for pid,parent in tree if parent in owned}
    if expanded==owned:break
    owned=expanded
   for pid in sorted(owned-{int(entry.name)},reverse=True):
    try:os.kill(pid,signal.SIGTERM)
    except ProcessLookupError:pass
   try:os.kill(int(entry.name),signal.SIGTERM)
   except ProcessLookupError:pass
   stopped.append({'pid':int(entry.name),'age_seconds':age,'commit':commit})
  except (FileNotFoundError,ProcessLookupError,PermissionError):continue
markers={}
for name in ['mobile-api-release']:
 p=Path('/etc/joba')/name
 if p.is_file():
  value=p.read_text().strip()
  markers[name]=value if re.fullmatch('[0-9a-f]{40}',value) else 'invalid'
print(json.dumps({'checked_at':datetime.datetime.now(datetime.timezone.utc).isoformat(),
 'read_only':len(sys.argv)==1,'stopped_stale_fetches':stopped,'load':list(os.getloadavg()),'release_markers':markers,
 'processes':run(['ps','-eo','pid,ppid,etimes,pcpu,pmem,comm','--sort=-pcpu']),
 'containers':run(['docker','ps','--format','{{.Names}} {{.Status}}']),
 'deployment_locks':run(['lslocks','--noheadings','--output','PID,COMMAND,PATH']),
 'disk':run(['df','-h','/opt/joba']),
 'memory':run(['free','-m'])},ensure_ascii=False))
