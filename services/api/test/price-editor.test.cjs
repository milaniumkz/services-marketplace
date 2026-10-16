const {test}=require('node:test'),assert=require('node:assert/strict'),{randomUUID,randomBytes}=require('node:crypto');
const {Marketplace}=require('../dist/marketplace'),{Store}=require('../dist/store'),{totp}=require('../dist/totp'),{pricePayload}=require('../dist/price-payload');
const payload={product_type:'subscription',provider:'isolated-price',product_id:'monthly-access',amount_minor:123456,currency:'KZT',period:'month',time_zone:'Asia/Almaty'};
const call=(a,u,method,path,body={})=>a.handle(method,path,body,'Bearer '+u.access_token,randomUUID());
test('price fields enforce country currency, exact money, executor-only subscriptions and approved duration',()=>{
 assert.throws(()=>pricePayload({...payload,currency:undefined,time_zone:undefined},'RS'));
 assert.equal(pricePayload(payload,'KZ').role,'executor');assert.equal(pricePayload({...payload,product_type:'boost',period:'days',duration_days:7},'KZ').duration_days,7);
 for(const patch of [{currency:'KGS'},{amount_minor:1.1},{amount_minor:Number.MAX_SAFE_INTEGER+1},{role:'customer'},{period:'days'},{product_type:'boost',period:'days',duration_days:0},{time_zone:'UTC'},{product_id:''}])assert.throws(()=>pricePayload({...payload,...patch},'KZ'));
 assert.equal(pricePayload({...payload,currency:'KGS',time_zone:'Asia/Bishkek'},'KG').currency,'KGS');
});
test('price drafts are versioned, independently published only after exact provider evidence and separated from boost offers',async()=>{
 const a=new Marketplace(new Store('memory://'));await a.initialize();
 try{
  const password='Isolated price editor password!',staff=[];
  for(const phone of ['+77000000861','+77000000862']){const u=await a.handle('POST','/auth/register',{country:'KZ',phone,password},undefined,randomUUID()),secret=randomBytes(20).toString('hex');await a.store.put({...await a.store.get(u.user.id),staff_permissions:['billing'],totp_secret:secret});staff.push(await a.handle('POST','/auth/staff-login',{country:'KZ',phone,password,mfa_code:totp(secret)},undefined,randomUUID()));}
  const reason='Проверка версии и синхронизации цены',title='Месяц доступа';let r=await call(a,staff[0],'POST','/admin/price-versions',{title,reason,payload}),path='/admin/price-versions/'+r.id;
  assert.equal(r.payload.role,'executor');assert.equal((await call(a,staff[0],'GET',path)).id,r.id);
  await assert.rejects(()=>call(a,staff[1],'PATCH',path,{expected_version:1,title,reason,payload}),e=>e.getStatus()===409);
  r=await call(a,staff[0],'PATCH',path,{expected_version:1,title,reason,payload:{...payload,amount_minor:100025}});assert.equal(r.version,2);
  await assert.rejects(()=>call(a,staff[0],'POST',path+'/validate',{expected_version:1,reason}),e=>e.getStatus()===409);
  await assert.rejects(()=>call(a,staff[1],'POST',path+'/publish',{expected_version:2,reason}),e=>e.getResponse().error.code==='PROVIDER_UNAVAILABLE');assert.equal((await a.store.get(r.id)).status,'draft');
  a.providers.billing.set('isolated-price',{name:'isolated-price',validateProduct:async()=>({product_id:'wrong-sku',amount_minor:100025,currency:'KZT'})});
  await assert.rejects(()=>call(a,staff[1],'POST',path+'/publish',{expected_version:2,reason}),e=>e.getResponse().error.code==='PRICE_MISMATCH');
  a.providers.billing.set('isolated-price',{name:'isolated-price',validateProduct:async id=>({product_id:id,amount_minor:100025,currency:'KZT'})});
  await assert.rejects(()=>call(a,staff[0],'POST',path+'/publish',{expected_version:2,reason}),e=>e.getStatus()===403);
  const effective=await call(a,staff[1],'POST',path+'/publish',{expected_version:2,reason});assert.equal(effective.status,'effective');assert.equal(effective.preview.provider_verified,true);
  await assert.rejects(()=>call(a,staff[0],'PATCH',path,{expected_version:3,title,reason,payload}),e=>e.getStatus()===409);
  await a.store.put({...effective,id:randomUUID(),payload:{...effective.payload,product_type:'boost',product_id:'isolated-boost'}});
  const filtered=await a.handle('GET','/admin/price-versions',{},'Bearer '+staff[0].access_token,undefined,{product_type:'boost',q:'isolated-boost'});assert.equal(filtered.items.length,1);assert.equal(filtered.items[0].payload.product_type,'boost');
  await call(a,staff[0],'POST',path+'/validate',{expected_version:3,reason});assert.ok((await a.store.all('audit','KZ')).some(x=>x.action==='prices.validated'&&x.target_id===r.id));
  const offers=await a.commerce.offers('KZ');assert.deepEqual(offers.items.map(x=>x.product_type),['subscription']);
  const stopped=await call(a,staff[1],'POST',path+'/stop',{expected_version:3,reason});assert.equal(stopped.status,'stopped');assert.deepEqual((await a.commerce.offers('KZ')).items,[]);
  const rollback=await call(a,staff[0],'POST',path+'/rollback',{expected_version:4,reason});assert.equal(rollback.status,'draft');assert.equal(rollback.rollback_of,r.id);assert.notEqual(rollback.id,r.id);
 }finally{await a.store.close();}
});
