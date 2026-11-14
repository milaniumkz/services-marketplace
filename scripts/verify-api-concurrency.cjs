// Starts and destroys its own PostgreSQL; never accepts a user database URL.
const {execFileSync}=require('node:child_process');
const {mkdtemp,writeFile,rm}=require('node:fs/promises');
const {tmpdir}=require('node:os');
const {join}=require('node:path');
const {randomBytes,randomUUID}=require('node:crypto');
const assert=require('node:assert/strict');
let stage='setup';
const sleep=ms=>new Promise(resolve=>setTimeout(resolve,ms));
const dockerEnvironment={...process.env};
for(const key of ['DOCKER_HOST','DOCKER_CONTEXT','DOCKER_TLS','DOCKER_TLS_VERIFY','DOCKER_CERT_PATH'])delete dockerEnvironment[key];
const docker=(args)=>execFileSync('docker',['--host=unix:///var/run/docker.sock',...args],{env:dockerEnvironment,encoding:'utf8',stdio:['ignore','pipe','pipe']}).trim();
async function main(){
 const dir=await mkdtemp(join(tmpdir(),'joba-concurrency-')),name='joba-concurrency-'+randomBytes(6).toString('hex');
 const password=randomBytes(32).toString('base64url');let started=false;const instances=[];
 try{
  const envFile=join(dir,'postgres.env');await writeFile(envFile,'POSTGRES_USER=joba_test\nPOSTGRES_DB=joba_test\nPOSTGRES_PASSWORD='+password+'\n',{mode:0o600});
  docker(['run','-d','--rm','--name',name,'--env-file',envFile,'-p','127.0.0.1::5432','postgres:16@sha256:ca0bd484cb98bf4b24eb1010e73fb3fcbd6714d240fbc1a10eea5b7dbecb641d']);started=true;
  const port=docker(['inspect',name,'--format','{{(index (index .NetworkSettings.Ports "5432/tcp") 0).HostPort}}']);
  let ready=false;for(let i=0;i<100;i++){try{docker(['exec',name,'pg_isready','-U','joba_test','-d','joba_test']);ready=true;break;}catch{await sleep(200);}}
  if(!ready)throw Error('Temporary PostgreSQL did not become ready');
  const url=new URL('postgresql://127.0.0.1:'+port+'/joba_test');url.username='joba_test';url.password=password;process.env.DATABASE_URL=url.toString();
  stage='TCP readiness';
  const {Client}=require('pg');let reachable=false;
  for(let i=0;i<100;i++){const client=new Client({connectionString:url.toString(),connectionTimeoutMillis:1000});try{await client.connect();await client.query('SELECT 1');reachable=true;break;}catch(error){if(!['57P03','ECONNREFUSED','ECONNRESET'].includes(error.code)&&error.message!=='Connection terminated unexpectedly')throw error;await sleep(200);}finally{await client.end().catch(()=>{});}}
  if(!reachable)throw Error('Temporary PostgreSQL TCP connection did not become ready');
  stage='API instances';
  const {Store}=require('../services/api/dist/store'),{Marketplace}=require('../services/api/dist/marketplace'),{PrivateFiles}=require('../services/api/dist/private-files'),{Providers}=require('../services/api/dist/providers');
  const make=async()=>{const api=new Marketplace(new Store(),new Providers(),new PrivateFiles(join(dir,'encrypted')));await api.initialize();instances.push(api);return api;};
  const first=await make(),second=await make();
  stage='registration';
  const credentials=await first.handle('POST','/auth/register',{country:'KZ',phone:'+77000000701',password:'Isolated concurrent API password!'},undefined,undefined,{},'isolated-register');
  const auth='Bearer '+credentials.access_token;
  const category=(await first.handle('GET','/catalog/categories',{},auth)).items[0].id;
  const body={title:'Изолированная параллельная команда',description:'Проверка двух независимых процессов API на настоящем PostgreSQL.',city:'Алматы',category_id:category};
  stage='duplicate commands';
  const key=randomUUID();const saved=await Promise.all([first,second].map(api=>api.handle('POST','/orders',body,auth,key)));
  assert.equal(saved[0].id,saved[1].id);assert.equal((await first.store.all('order')).length,1);
  stage='competing revisions';
  const edits=await Promise.allSettled([first,second].map((api,index)=>api.handle('PATCH','/orders/'+saved[0].id,{expected_version:1,title:'Конкурирующая правка '+index},auth,randomUUID())));
  assert.equal(edits.filter(r=>r.status==='fulfilled').length,1);assert.equal(edits.find(r=>r.status==='rejected').reason.getResponse().error.code,'STATE_CONFLICT');
  stage='invitation pair and daily limits';
  const executor=await first.handle('POST','/auth/register',{country:'KZ',phone:'+77000000702',password:'Isolated executor invitation password!'},undefined,undefined,{},'isolated-executor-register');
  const executorUser=await first.store.get(executor.user.id);await first.store.put({...executorUser,roles:['executor'],verification:'passed',version:executorUser.version+1});
  const until=new Date(Date.now()+86400000).toISOString(),now=new Date().toISOString();
  const put=(kind,owner,data)=>first.store.put({id:randomUUID(),kind,owner,country:'KZ',version:1,created_at:now,...data});
  const customerGrant=await put('grant',credentials.user.id,{capabilities:['publish_order'],valid_until:until,balance:2});
  await put('grant',executor.user.id,{capabilities:['send_offer'],valid_until:until,balance:2});
  const profile=await put('contractor',executor.user.id,{status:'published',availability:'available'});
  const opened=await first.store.get(saved[0].id);await first.store.put({...opened,status:'open',expires_at:until,version:opened.version+1});
  const inviteBody={contractor_id:profile.id,message:'Параллельная проверка приглашений.'};
  const pair=await Promise.allSettled([first,second].map(api=>api.handle('POST','/orders/'+opened.id+'/invites',inviteBody,auth,randomUUID())));
  assert.equal(pair.filter(r=>r.status==='fulfilled').length,1);assert.equal(pair.find(r=>r.status==='rejected').reason.getResponse().error.code,'STATE_CONFLICT');
  assert.equal((await first.store.get(customerGrant.id)).balance,2);
  for(let i=0;i<8;i++)await put('invite',credentials.user.id,{order_id:randomUUID(),recipient_id:executor.user.id,status:'declined'});
  const dailyOrders=[];for(let i=0;i<2;i++)dailyOrders.push(await put('order',credentials.user.id,{title:'Проверка дневного лимита '+i,status:'open',revision:1,expires_at:until}));
  const daily=await Promise.allSettled([first,second].map((api,i)=>api.handle('POST','/orders/'+dailyOrders[i].id+'/invites',inviteBody,auth,randomUUID())));
  assert.equal(daily.filter(r=>r.status==='fulfilled').length,1);assert.equal(daily.find(r=>r.status==='rejected').reason.getResponse().error.code,'RATE_LIMITED');
  stage='duplicate safety reports';
  const reportBody={target_type:'order',target_id:opened.id,reason_code:'agreement',description:'Проверка единственного дела при параллельных запросах.'};
  const reports=await Promise.allSettled([first,second].map(api=>api.handle('POST','/cases',reportBody,auth,randomUUID())));
  assert.equal(reports.filter(r=>r.status==='fulfilled').length,1);assert.equal(reports.find(r=>r.status==='rejected').reason.getResponse().error.code,'STATE_CONFLICT');
  stage='session rotation';
  const rotation=await Promise.allSettled([first,second].map(api=>api.handle('POST','/auth/refresh',{refresh_token:credentials.refresh_token},undefined,undefined,{},'isolated-refresh')));
  assert.equal(rotation.filter(r=>r.status==='fulfilled').length,1);assert.equal(rotation.find(r=>r.status==='rejected').reason.getResponse().error.code,'REFRESH_REPLAY');
  const rotated=rotation.find(r=>r.status==='fulfilled').value;
  await assert.rejects(()=>first.handle('GET','/me',{},'Bearer '+rotated.access_token),error=>error.getStatus()===401);
  stage='failed login counters';
  for(let i=0;i<10;i++)await assert.rejects(()=>(i%2?first:second).handle('POST','/auth/login',{country:'KZ',phone:'+77000000701',password:'Incorrect but sufficiently long password'},undefined,undefined,{},'failed-login-'+i),error=>error.getResponse().error.code==='INVALID_CREDENTIALS');
  stage='new API process';
  const third=await make();await assert.rejects(()=>third.handle('POST','/auth/login',{country:'KZ',phone:'+77000000701',password:'Isolated concurrent API password!'},undefined,undefined,{},'new-process-new-ip'),error=>error.getResponse().error.code==='RATE_LIMITED');
  const scopes=(await first.store.db.query('SELECT scope_hash FROM rate_limits')).rows;assert.ok(scopes.length);assert.ok(scopes.every(row=>/^[0-9a-f]{64}$/.test(row.scope_hash)));
  console.log('PostgreSQL concurrency: one result per idempotency key, one winning revision, refresh replay family revocation, shared persistent failed-login limits, hashed scopes, invitation active pairs and daily limits, free invitation credits and duplicate safety reports passed.');
 }finally{
  for(const api of instances)await api.store.close();
  if(started)docker(['stop',name]);await rm(dir,{recursive:true,force:true});
 }
}
main().catch(error=>{console.error('Concurrency validation failed at '+stage+':',error.getResponse?.()?.error?.code||error.code||error.message);process.exitCode=1;});
