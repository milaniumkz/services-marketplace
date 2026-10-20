const {test}=require('node:test'),assert=require('node:assert/strict'),{randomUUID,randomBytes}=require('node:crypto');
const {Marketplace}=require('../dist/marketplace'),{Store}=require('../dist/store'),{totp}=require('../dist/totp');
const password='Isolated monetization editor password!';
const call=(a,u,method,path,body={})=>a.handle(method,path,body,'Bearer '+u.access_token,randomUUID());
test('monetization drafts edit with versions, publish independently, preserve regional singleton and expose actual limits without customer subscriptions',async()=>{
 const a=new Marketplace(new Store('memory://'));await a.initialize();
 try{
  const staff=[];for(const phone of ['+77000000911','+77000000912']){const u=await a.handle('POST','/auth/register',{country:'KZ',phone,password},undefined,randomUUID()),secret=randomBytes(20).toString('hex');await a.store.put({...await a.store.get(u.user.id),staff_permissions:['billing'],totp_secret:secret});staff.push(await a.handle('POST','/auth/staff-login',{country:'KZ',phone,password,mfa_code:totp(secret)},undefined,randomUUID()));}
  const member=await a.handle('POST','/auth/register',{country:'KZ',phone:'+77000000913',password},undefined,randomUUID());
  const title='Настройки рекламного доступа',reason='Проверка редактирования монетизации страны',payload={subscription_enabled:true,banner_ads_enabled:false,rewarded_access_enabled:false};
  for(const invalid of [{...payload,daily_cap:0},{...payload,daily_cap:1.5},{...payload,cooldown_seconds:-1},{...payload,role:'customer'},{...payload,banner_placements:['chat.inline']},{...payload,reward_policy:{kind:'duration',duration_seconds:3600,capabilities:['publish_order']}}])await assert.rejects(()=>call(a,staff[0],'POST','/admin/monetization-configs',{title,reason,payload:invalid}),e=>e.getStatus()===422);
  let d=await call(a,staff[0],'POST','/admin/monetization-configs',{title,reason,payload:{...payload,ignored:true}});const path='/admin/monetization-configs/'+d.id;assert.equal(d.payload.daily_cap,5);assert.equal(d.payload.ignored,undefined);
  await assert.rejects(()=>call(a,member,'GET',path),e=>e.getStatus()===403);
  await assert.rejects(()=>call(a,staff[1],'PATCH',path,{title,reason,payload,expected_version:1}),e=>e.getStatus()===409);
  d=await call(a,staff[0],'PATCH',path,{title,reason,payload:{...payload,daily_cap:2,cooldown_seconds:120},expected_version:1});assert.equal(d.version,2);
  for(const action of ['validate','preview','publish'])await assert.rejects(()=>call(a,staff[1],'POST',path+'/'+action,{reason,expected_version:1}),e=>e.getStatus()===409);
  await assert.rejects(()=>call(a,staff[0],'POST',path+'/publish',{reason,expected_version:2}),e=>e.getStatus()===403);
  const preview=await call(a,staff[0],'POST',path+'/preview',{reason,expected_version:2});assert.equal(preview.applied,false);
  d=await call(a,staff[1],'POST',path+'/publish',{reason,expected_version:2});assert.equal(d.status,'effective');
  await assert.rejects(()=>call(a,staff[0],'PATCH',path,{title,reason,payload,expected_version:3}),e=>e.getStatus()===409);
  let config=await call(a,member,'GET','/me/monetization-config');assert.equal(config.subscription_enabled,false);assert.equal(config.reward_usage.daily_cap,2);assert.deepEqual(config.offers,[]);
  const now=new Date();await a.store.put({id:randomUUID(),kind:'ad_session',owner:member.user.id,country:'KZ',version:1,created_at:now.toISOString(),status:'created'});config=await call(a,member,'GET','/me/monetization-config');assert.equal(config.reward_usage.remaining_today,1);assert.equal(Date.parse(config.reward_usage.cooldown_until)-now.getTime(),120000);
  // A replacement supersedes even a legacy scoped head; the runtime reads one regional policy.
  await a.store.put({...await a.store.get(d.id),payload:{...d.payload,role:'executor'}});
  const next=await call(a,staff[0],'POST','/admin/monetization-configs',{title,reason,payload});await call(a,staff[1],'POST','/admin/monetization-configs/'+next.id+'/publish',{reason,expected_version:1});assert.equal((await a.store.all('monetization_config','KZ')).filter(x=>x.status==='effective').length,1);assert.equal((await a.store.get(d.id)).status,'superseded');assert.equal((await call(a,staff[0],'GET','/admin/monetization-summary')).current.id,next.id);
  const enabled=await call(a,staff[0],'POST','/admin/monetization-configs',{title,reason,payload:{...payload,banner_ads_enabled:true}});await assert.rejects(()=>call(a,staff[1],'POST','/admin/monetization-configs/'+enabled.id+'/publish',{reason,expected_version:1}),e=>e.getResponse().error.code==='BANNER_PROVIDER_UNAVAILABLE');assert.equal((await a.store.get(enabled.id)).status,'draft');
 }finally{await a.store.close();}
});
