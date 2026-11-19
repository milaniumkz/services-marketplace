const {test}=require('node:test'),assert=require('node:assert/strict'),{randomUUID}=require('node:crypto');
const {Store}=require('../dist/store');
const {Marketplace}=require('../dist/marketplace');
const {crashReport,mobileCrashes}=require('../dist/mobile-crashes');
const report=()=>({id:randomUUID(),kind:'flutter',platform:'android',fatal:true,occurred_at:new Date().toISOString(),app_version:'1.0.3',build:'5',device_model:'Test phone',os_version:'14',screen:'create',message:'Failure password=never_log_me +77479275358 test@example.com https://private.test?token=secret Bearer abcdef',stack:'Exception\n#0 createOrder (package:services_marketplace/screens/marketplace.dart:12:3)',breadcrumbs:[{screen:'create',at:new Date().toISOString()}]});
test('diagnostic payload redacts secrets and contacts, rejects oversized and invalid timestamps, and drops unknown fields',()=>{
 const raw=report();const value=crashReport({...raw,password:'sensitive',user:{phone:'secret'},photos:['private']});
 assert.equal(value.password,undefined);assert.equal(value.user,undefined);assert.equal(value.photos,undefined);
 assert.doesNotMatch(value.message,/never_log_me|77479275358|test@example|private\.test|abcdef/);assert.match(value.stack,/marketplace.dart:12:3/);
 assert.throws(()=>crashReport({...raw,stack:'x'.repeat(26000)}));assert.throws(()=>crashReport({...raw,occurred_at:'invalid'}));assert.throws(()=>crashReport({...raw,occurred_at:'2000-01-01'}));assert.throws(()=>crashReport({...raw,kind:'arbitrary'}));
});
test('public delivery persists without a login, retries are idempotent, and reading logs requires staff access',async()=>{
 const api=new Marketplace(new Store('memory://'));await api.initialize();
 try{
  const body=report();const first=await api.handle('POST','/public/mobile-crashes',body);assert.equal(first.accepted,true);assert.equal(first.duplicate,false);
  const second=await api.handle('POST','/public/mobile-crashes',{...body,message:'duplicate must not overwrite'});assert.equal(second.duplicate,true);
  const saved=await mobileCrashes(api.store,{id:body.id});assert.equal(saved.items.length,1);assert.notEqual(saved.items[0].report.message,'duplicate must not overwrite');assert.equal(saved.retention_days,30);
  await assert.rejects(()=>api.handle('GET','/admin/mobile-crashes'));
  const user=await api.handle('POST','/auth/register',{country:'KZ',phone:'+77000000847',password:'Isolated diagnostic test!'});
  await assert.rejects(()=>api.handle('GET','/admin/mobile-crashes',{},'Bearer '+user.access_token));
  for(let i=0;i<120;i++)await api.handle('POST','/public/mobile-crashes',body,undefined,undefined,{},'rate-test');
  await assert.rejects(()=>api.handle('POST','/public/mobile-crashes',body,undefined,undefined,{},'rate-test'),e=>e.getStatus()===429);
 }finally{await api.store.close();}
});
