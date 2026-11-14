const {test}=require('node:test'),assert=require('node:assert/strict'),{randomUUID,randomBytes}=require('node:crypto');
const {Marketplace}=require('../dist/marketplace'),{Store}=require('../dist/store'),{totp}=require('../dist/totp');
const password='Isolated policy editor password!';
const call=(a,u,method,path,body={})=>a.handle(method,path,body,'Bearer '+u.access_token,randomUUID());
const record=(kind,owner,data)=>({id:randomUUID(),kind,owner,country:'KZ',version:1,created_at:new Date().toISOString(),...data});
test('placement editor protects overlapping promises including reservations, preserves disjoint capacity and feeds actual reservations',async()=>{
 const a=new Marketplace(new Store('memory://'));await a.initialize();
 try{
  const staff=[];for(const phone of ['+77000000881','+77000000882']){const u=await a.handle('POST','/auth/register',{country:'KZ',phone,password},undefined,randomUUID()),secret=randomBytes(20).toString('hex');await a.store.put({...await a.store.get(u.user.id),staff_permissions:['promotion'],totp_secret:secret});staff.push(await a.handle('POST','/auth/staff-login',{country:'KZ',phone,password,mfa_code:totp(secret)},undefined,randomUUID()));}
  const reason='Проверка ёмкости места с принятыми обязательствами',title='Продвижение заказов',placement='search.orders.promoted',payload={placement_id:placement,capacity:1};
  for(const invalid of [{placement_id:'unknown',capacity:1},{...payload,capacity:0},{...payload,capacity:1.5}])await assert.rejects(()=>call(a,staff[0],'POST','/admin/placement-policies',{title,reason,payload:invalid}),e=>e.getStatus()===422);
  let r=await call(a,staff[0],'POST','/admin/placement-policies',{title,reason,payload:{...payload,ignored:true}});const path='/admin/placement-policies/'+r.id;assert.equal(r.payload.ignored,undefined);
  await assert.rejects(()=>call(a,staff[1],'PATCH',path,{title,reason,payload,expected_version:1}),e=>e.getStatus()===409);
  r=await call(a,staff[0],'PATCH',path,{title,reason,payload:{...payload,capacity:2},expected_version:1});assert.equal(r.version,2);
  await assert.rejects(()=>call(a,staff[0],'POST',path+'/validate',{reason,expected_version:1}),e=>e.getStatus()===409);
  await assert.rejects(()=>call(a,staff[0],'POST',path+'/publish',{reason,expected_version:2}),e=>e.getStatus()===403);
  await call(a,staff[1],'POST',path+'/publish',{reason,expected_version:2});
  const now=Date.now(),date=hours=>new Date(now+hours*3600000).toISOString();
  const first=record('boost',staff[0].user.id,{placement_id:placement,status:'scheduled',starts_at:date(1),ends_at:date(2)}),second=record('boost',staff[0].user.id,{placement_id:placement,status:'scheduled',starts_at:date(2),ends_at:date(3)});
  await a.store.put(first);await a.store.put(second);
  let next=await call(a,staff[0],'POST','/admin/placement-policies',{title,reason,payload});const nextPath='/admin/placement-policies/'+next.id;
  assert.equal((await call(a,staff[0],'POST',nextPath+'/preview',{reason,expected_version:1})).promised_peak,1);
  const reserve=record('boost',staff[0].user.id,{placement_id:placement,status:'reserved',starts_at:date(0),ends_at:date(4),reservation_expires_at:date(1)});await a.store.put(reserve);
  await assert.rejects(()=>call(a,staff[1],'POST',nextPath+'/publish',{reason,expected_version:1}),e=>e.getResponse().error.code==='CAPACITY_PROMISE_CONFLICT');
  await assert.rejects(()=>call(a,staff[1],'POST',path+'/stop',{reason,expected_version:3}),e=>e.getResponse().error.code==='PLACEMENT_PROMISES_ACTIVE');
  await a.store.put({...reserve,reservation_expires_at:date(-1)});
  await call(a,staff[1],'POST',nextPath+'/publish',{reason,expected_version:1});assert.equal((await a.store.get(r.id)).status,'superseded');
  for(const item of [first,second])await a.store.put({...item,status:'revoked'});
  const user=await a.handle('POST','/auth/register',{country:'KZ',phone:'+77000000883',password},undefined,randomUUID());
  const order=record('order',user.user.id,{status:'open',expires_at:date(240)}),price=record('price_version','system',{status:'effective',payload:{product_type:'boost',period:'week'}});await a.store.put(order);await a.store.put(price);
  const live=await a.growth.reserveBoost(user.user.id,'KZ',{target_id:order.id,placement_id:placement,price_id:price.id});assert.equal(live.status,'reserved');
  await assert.rejects(()=>call(a,staff[1],'POST',nextPath+'/stop',{reason,expected_version:2}),e=>e.getResponse().error.code==='PLACEMENT_PROMISES_ACTIVE');
  const detail=await call(a,staff[0],'GET',nextPath);assert.equal(detail.metrics.live_reservations,1);assert.equal(detail.metrics.promised_peak,1);
  await a.store.put({...live,reservation_expires_at:date(-1)});assert.equal((await call(a,staff[1],'POST',nextPath+'/stop',{reason,expected_version:2})).status,'stopped');
 }finally{await a.store.close();}
});
