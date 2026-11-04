"""Read-only bank setup check inside the deployed API; never prints credentials."""
import datetime,json,subprocess
from pathlib import Path
root=Path('/opt/joba/current').resolve()
cmd=['docker','compose','--env-file','/etc/joba/production.env','-f',str(root/'infra/production/compose.yaml'),'exec','-T','api','node','-e']
source="""const fs=require('node:fs'),{loadVtbConfig,VTB_ORIGINS}=require('/app/services/api/dist/vtb-gateway');const c=loadVtbConfig();const mode=fs.statSync(process.env.JOBA_VTB_CONFIG_FILE).mode&0o777;console.log(JSON.stringify({configured:!!c,environment:c?.environment,bank_origin:c?VTB_ORIGINS[c.environment]:null,return_origin:c?.public_origin,credential_mode:mode.toString(8),api_uid:process.getuid(),currency:'KZT',auto_renew:false}));"""
r=subprocess.run(cmd+[source],capture_output=True,text=True,timeout=30)
if r.returncode:raise SystemExit('VTB setup check failed; credential details were not logged')
value=json.loads(r.stdout);value['checked_at']=datetime.datetime.now(datetime.timezone.utc).isoformat();value['read_only']=True
print(json.dumps(value))
