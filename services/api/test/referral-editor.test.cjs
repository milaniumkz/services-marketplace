const {test}=require('node:test'),assert=require('node:assert/strict'),{randomUUID,randomBytes}=require('node:crypto');
const {Marketplace}=require('../dist/marketplace'),{Store}=require('../dist/store'),{totp}=require('../dist/totp');
const password='Isolated policy editor password!';
const call=(a,u,method,path,body={})=>a.handle(method,path,body,'Bearer '+u.access_token,randomUUID());
test('referral editor validates privileges, versions, ownership and independent publication',async()=>{
 const a=new Marketplace(new Store('memory://'));await a.initialize();
 try{
  const staff=[];for(const phone of ['+77000000851','+77000000852']){const u=await a.handle('POST','/auth/register',{country:'KZ',phone,password},undefined,randomUUID()),secret=randomBytes(20).toString('hex');await a.store.put({...await a.store.get(u.user.id),staff_permissions:['campaign'],totp_secret:secret});staff.push(await a.handle('POST','/auth/staff-login',{country:'KZ',phone,password,mfa_code:totp(secret)},undefined,randomUUID()));}
  const reason='Проверка условий реферальной кампании',title='Приглашения исполнителя',payload={threshold:2,budget_units:10,reward_duration_seconds:3600,qualifying_event:'completed_order',capabilities:['search_full']};
  for(const bad of [{attribution_window_days:0},{attribution_window_days:366},{attribution_window_days:1.5},{capabilities:[]},{capabilities:['administrator']},{budget_units:1.5},{reward_duration_seconds:Infinity},{threshold:0},{cash_payout:true}])await assert.rejects(()=>call(a,staff[0],'POST','/admin/referral-campaigns',{title,reason,payload:{...payload,...bad}}),e=>e.getStatus()===422);
  let r=await call(a,staff[0],'POST','/admin/referral-campaigns',{title,reason,payload});const path='/admin/referral-campaigns/'+r.id;
  assert.equal((await call(a,staff[0],'GET',path)).metrics.budget_used,0);
  await assert.rejects(()=>call(a,staff[1],'PATCH',path,{title,reason,payload,expected_version:1}),e=>e.getStatus()===409);
  r=await call(a,staff[0],'PATCH',path,{title,reason,payload:{...payload,threshold:3,attribution_window_days:30},expected_version:1});assert.equal(r.version,2);assert.equal(r.payload.attribution_window_days,30);
  await assert.rejects(()=>call(a,staff[0],'POST',path+'/validate',{reason,expected_version:1}),e=>e.getStatus()===409);
  await assert.rejects(()=>call(a,staff[0],'POST',path+'/publish',{reason,expected_version:2}),e=>e.getStatus()===403);
  assert.equal((await call(a,staff[1],'POST',path+'/preview',{reason,expected_version:2})).applied,false);
  assert.equal((await call(a,staff[1],'POST',path+'/publish',{reason,expected_version:2})).status,'effective');
  await assert.rejects(()=>call(a,staff[0],'PATCH',path,{title,reason,payload,expected_version:3}),e=>e.getStatus()===409);
 }finally{await a.store.close();}
});
