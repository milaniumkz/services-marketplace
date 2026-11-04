"""Read-only bank setup check inside the deployed API; never prints credentials."""
import datetime,json,subprocess
from pathlib import Path
root=Path('/opt/joba/current').resolve()
cmd=['docker','compose','--env-file','/etc/joba/production.env','-f',str(root/'infra/production/compose.yaml'),'exec','-T','api','node','-e']
source="""const fs=require('node:fs'),crypto=require('node:crypto'),{loadVtbConfig,VTB_ORIGINS,VtbGateway,VtbGatewayError}=require('/app/services/api/dist/vtb-gateway');(async()=>{const c=loadVtbConfig();if(!c)throw Error('Not configured');const mode=fs.statSync(process.env.JOBA_VTB_CONFIG_FILE).mode&0o777;let bankApi=false,bankError=null;try{await new VtbGateway(c,{}).status({orderNumber:crypto.randomUUID()});bankApi=true;}catch(e){bankApi=e instanceof VtbGatewayError&&e.code==='6';if(!bankApi)bankError=e instanceof VtbGatewayError&&/^[0-9]{1,3}$/.test(e.code)?e.code:'UNAVAILABLE';}console.log(JSON.stringify({configured:true,environment:c.environment,bank_origin:VTB_ORIGINS[c.environment],return_origin:c.public_origin,credential_mode:mode.toString(8),api_uid:process.getuid(),currency:'KZT',auto_renew:false,bank_api_verified:bankApi,bank_error:bankError}));})().catch(()=>process.exit(1));"""
r=subprocess.run(cmd+[source],capture_output=True,text=True,timeout=35)
if r.returncode:raise SystemExit('VTB setup check failed; credential details were not logged')
value=json.loads(r.stdout);value['checked_at']=datetime.datetime.now(datetime.timezone.utc).isoformat();value['read_only']=True
print(json.dumps(value))
