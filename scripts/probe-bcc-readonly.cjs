// Owner-authorized connectivity check only. Never creates purchases, captures, or refunds.
const fs=require('node:fs'),crypto=require('node:crypto');
(async()=>{
 if(process.env.JOBA_BCC_READONLY_PROBE!=='owner-authorized-production-setup')throw Error('Explicit setup context required');
 const moduleRoot=process.env.JOBA_BCC_MODULE_ROOT||'/app/services/api/dist';
 const {validateBccConfig,BCC_ENDPOINTS,bccMac,bccOrder}=require(moduleRoot+'/bcc-gateway'),{parseBccResponse}=require(moduleRoot+'/bcc-response');
 const config=validateBccConfig(JSON.parse(fs.readFileSync(process.env.JOBA_BCC_CONFIG_FILE||'/run/joba-payments/bcc.json','utf8')));
 if(config.environment!=='production')throw Error('Production setup probe cannot use sandbox credentials');
 const request=async fields=>{try{const response=await fetch(BCC_ENDPOINTS.production,{method:'POST',headers:{'content-type':'application/x-www-form-urlencoded'},body:new URLSearchParams(fields),redirect:'error',signal:AbortSignal.timeout(20000)});const result=parseBccResponse(await response.text());return {http_status:response.status,action:result.ACTION??null,rc:result.RC??null,terminal_matches:result.TERMINAL===config.terminal};}catch(error){return {transport_error:error.name};}};
 const ping=await request({TERMINAL:config.terminal,TRTYPE:'800',LANG:'ru'});
 const fields={ORDER:bccOrder(crypto.randomUUID()),TERMINAL:config.terminal,TRTYPE:'90',TRAN_TRTYPE:'1',MERCH_GMT:'0',TIMESTAMP:new Date().toISOString().replace(/\D/g,'').slice(0,14),NONCE:crypto.randomBytes(16).toString('hex').toUpperCase()};fields.P_SIGN=bccMac(fields,['ORDER','TERMINAL','TIMESTAMP','TRTYPE','NONCE'],config.mac_key);
 const status=await request(fields);
 console.log(JSON.stringify({bcc_readonly_probe:true,checked_at:new Date().toISOString(),environment:config.environment,notification_mode:config.notification_mode||'http-basic',http_callback_enabled:!!config.notify_user,terminal_ping:ping,nonexistent_order_status:status,terminal_ping_success:ping.action==='0'&&ping.rc==='00'&&ping.terminal_matches,actual_payment_tested:false,charges_created:false,refunds_created:false}));
})().catch(error=>{console.error('BCC readonly probe failed: '+error.name);process.exitCode=1;});
