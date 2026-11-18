"""Capture only read-only BCC diagnostic HTTP bodies; caller encrypts before publication."""
import json,subprocess
from pathlib import Path
root=Path('/opt/joba/current').resolve()
source=r"""const fs=require('node:fs'),crypto=require('node:crypto'),{loadBccConfig,BccGateway}=require('/app/services/api/dist/bcc-gateway'),{parseBccResponse}=require('/app/services/api/dist/bcc-response');
(async()=>{const c=loadBccConfig();if(!c||c.environment!=='production')throw Error('Not configured');const wire=[];const bank=new BccGateway(c,{},async(url,options)=>{const started=new Date().toISOString();const r=await fetch(url,options),raw=await r.text(),fields=parseBccResponse(raw);wire.push({started_at:started,method:options.method,url,request_headers:options.headers,request_body:String(options.body),http_status:r.status,response_content_type:r.headers.get('content-type'),response_fields:fields,response_sha256:crypto.createHash('sha256').update(raw).digest('hex')});return new Response(raw,{status:r.status,headers:{'content-type':r.headers.get('content-type')||'text/html'}});});await bank.api({TERMINAL:c.terminal,TRTYPE:'800',LANG:'ru'});await bank.status({orderId:'10917286642734770830851119657'});console.log(JSON.stringify({checked_at:new Date().toISOString(),source:'production-api-container',environment:c.environment,wire,read_only:true,financial_commands:false,secret_key_included:false,card_data_included:false}));})().catch(()=>{console.error('Read-only BCC wire diagnosis failed; no private details logged');process.exitCode=1});"""
cmd=['docker','compose','--env-file','/etc/joba/production.env','-f',str(root/'infra/production/compose.yaml'),'exec','-T','api','node','-e',source]
r=subprocess.run(cmd,capture_output=True,text=True,timeout=80)
if r.returncode:raise SystemExit('Read-only BCC wire diagnosis failed; no private details logged')
print(json.dumps(json.loads(r.stdout)))
