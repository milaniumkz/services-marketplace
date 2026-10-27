const {paidCustomer}=require('./paid-customer-fixture.cjs');
const {test}=require('node:test'),assert=require('node:assert/strict'),{randomUUID,randomBytes}=require('node:crypto');
const {Marketplace}=require('../dist/marketplace'),{Store}=require('../dist/store'),{totp}=require('../dist/totp');
const password='Isolated policy editor password!';
const call=(a,u,method,path,body={})=>a.handle(method,path,body,'Bearer '+u.access_token,randomUUID());
test('ranking editor enforces versions and approval; published parameters drive the real regional Top',async()=>{
 const a=new Marketplace(new Store('memory://'));await a.initialize();
 try{
  const staff=[];for(const phone of ['+77000000861','+77000000862']){const u=await a.handle('POST','/auth/register',{country:'KZ',phone,password},undefined,randomUUID()),secret=randomBytes(20).toString('hex');await a.store.put({...await a.store.get(u.user.id),staff_permissions:['content'],totp_secret:secret});staff.push(await a.handle('POST','/auth/staff-login',{country:'KZ',phone,password,mfa_code:totp(secret)},undefined,randomUUID()));}
  const customer=await a.handle('POST','/auth/register',{country:'KZ',phone:'+77000000863',password},undefined,randomUUID());
  await paidCustomer(a,customer);
  const reason='Проверка параметров органического рейтинга',title='Рейтинг региона',payload={window_days:90,dislike_weight:0.75,age_days:45,formula:'log_likes_decay_v1'};
  for(const bad of [{window_days:0},{age_days:1.5},{dislike_weight:-1},{formula:'arbitrary'}])await assert.rejects(()=>call(a,staff[0],'POST','/admin/ranking-configs',{title,reason,payload:{...payload,...bad}}),e=>e.getStatus()===400);
  let r=await call(a,staff[0],'POST','/admin/ranking-configs',{title,reason,payload:{...payload,scope:'discarded'}});const path='/admin/ranking-configs/'+r.id;assert.equal(r.payload.scope,undefined);
  assert.equal((await call(a,staff[0],'GET',path)).id,r.id);
  await assert.rejects(()=>call(a,staff[1],'PATCH',path,{title,reason,payload,expected_version:1}),e=>e.getStatus()===409);
  r=await call(a,staff[0],'PATCH',path,{title,reason,payload:{...payload,age_days:60},expected_version:1});assert.equal(r.version,2);
  await assert.rejects(()=>call(a,staff[0],'POST',path+'/validate',{reason,expected_version:1}),e=>e.getStatus()===409);
  await assert.rejects(()=>call(a,staff[0],'POST',path+'/publish',{reason,expected_version:2}),e=>e.getStatus()===403);
  assert.equal((await call(a,staff[1],'POST',path+'/preview',{reason,expected_version:2})).applied,false);
  await call(a,staff[1],'POST',path+'/publish',{reason,expected_version:2});
  const top=await call(a,customer,'GET','/top-listings');assert.equal(top.meta.algorithm_id,r.id);assert.deepEqual(top.meta.parameters,{windowDays:90,dislikeWeight:0.75,ageDays:60});
  await assert.rejects(()=>call(a,staff[0],'PATCH',path,{title,reason,payload,expected_version:3}),e=>e.getStatus()===409);
  await call(a,staff[1],'POST',path+'/stop',{reason,expected_version:3});assert.equal((await call(a,customer,'GET','/top-listings')).meta.algorithm_id,null);
 }finally{await a.store.close();}
});
