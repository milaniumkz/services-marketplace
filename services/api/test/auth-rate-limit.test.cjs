const {test}=require('node:test'),assert=require('node:assert/strict');
const {mkdtemp,rm}=require('node:fs/promises'),{tmpdir}=require('node:os'),{join}=require('node:path');
const {Marketplace}=require('../dist/marketplace'),{Store}=require('../dist/store');
test('rejected login counters survive rejection; retry delay follows a fixed database window without revealing account existence',async()=>{
 const a=new Marketplace(new Store('memory://'));await a.initialize();try{
  const body={country:'KZ',phone:'+77000000791',password:'Isolated incorrect password!'};
  for(let i=0;i<10;i++)await assert.rejects(()=>a.handle('POST','/auth/login',body,undefined,undefined,{},'isolated-rate-ip'),e=>e.getStatus()===401&&e.getResponse().error.code==='INVALID_CREDENTIALS');
  let first;await assert.rejects(()=>a.handle('POST','/auth/login',body,undefined,undefined,{},'isolated-rate-ip'),e=>{first=e.getResponse().error.details.retry_after_seconds;return e.getStatus()===429&&Number.isInteger(first)&&first>=1&&first<=60;});
  const rows=(await a.store.db.query('SELECT window_start,attempts FROM rate_limits')).rows;assert.equal(rows.length,2);assert.ok(rows.every(r=>r.attempts>=10));
  await a.store.db.query("UPDATE rate_limits SET window_start=CURRENT_TIMESTAMP-INTERVAL '35 seconds'");
  await assert.rejects(()=>a.handle('POST','/auth/login',body,undefined,undefined,{},'isolated-rate-ip'),e=>{const error=e.getResponse().error;assert.deepEqual(Object.keys(error.details),['retry_after_seconds']);return e.getStatus()===429&&error.details.retry_after_seconds<=25&&error.details.retry_after_seconds>=1;});
  await a.store.db.query("UPDATE rate_limits SET window_start=CURRENT_TIMESTAMP-INTERVAL '61 seconds'");
  await assert.rejects(()=>a.handle('POST','/auth/login',body,undefined,undefined,{},'isolated-rate-ip'),e=>e.getStatus()===401&&e.getResponse().error.code==='INVALID_CREDENTIALS');
  assert.ok((await a.store.db.query('SELECT attempts FROM rate_limits')).rows.every(r=>r.attempts===1));
 }finally{await a.store.close();}
});
test('real HTTP rate-limit response exposes the same bounded retry delay in JSON and Retry-After',async()=>{
 const dir=await mkdtemp(join(tmpdir(),'joba-auth-rate-'));process.env.JOBA_DATA_DIR='memory://';process.env.JOBA_UPLOAD_DIR=dir;delete process.env.DATABASE_URL;
 const {NestFactory}=require('@nestjs/core'),{AppModule,getMarketplace}=require('../dist/app.module');const app=await NestFactory.create(AppModule,{logger:false});
 try{
  await app.listen(0,'127.0.0.1');const base=await app.getUrl();
  const login=()=>fetch(base+'/api/v1/auth/login',{method:'POST',headers:{'content-type':'application/json'},body:JSON.stringify({country:'KZ',phone:'+77000000792',password:'Isolated invalid HTTP password!'})});
  for(let i=0;i<10;i++){const r=await login();assert.equal(r.status,401);await r.json();}
  const r=await login(),data=await r.json();assert.equal(r.status,429);assert.equal(r.headers.get('retry-after'),String(data.error.details.retry_after_seconds));assert.equal(r.headers.get('cache-control'),'no-store');assert.ok(data.error.request_id);assert.ok(data.error.details.retry_after_seconds>=1&&data.error.details.retry_after_seconds<=60);
 }finally{await app.close();await (await getMarketplace()).store.close();await rm(dir,{recursive:true,force:true});}
});
