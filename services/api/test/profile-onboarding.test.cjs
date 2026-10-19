const {test}=require('node:test'),assert=require('node:assert/strict');
const {randomUUID}=require('node:crypto');
const {Marketplace}=require('../dist/marketplace'),{Store}=require('../dist/store');
test('onboarding profile validates bounds, rejects stale versions, and never buys access when choosing a role',async()=>{
 const api=new Marketplace(new Store('memory://'));await api.initialize();
 try{
  const session=await api.handle('POST','/auth/register',{country:'KZ',phone:'+77000000767',password:'Isolated onboarding password'},undefined,randomUUID(),{},'onboarding-profile');
  const call=(method,body={})=>api.handle(method,'/me',body,'Bearer '+session.access_token,randomUUID());
  let profile=await call('GET');
  await assert.rejects(()=>call('PATCH',{expected_version:profile.version,display_name:'x'.repeat(61)}),e=>e.getStatus()===400&&e.getResponse().error.code==='VALIDATION_ERROR');
  assert.equal((await call('GET')).version,profile.version);
  profile=await call('PATCH',{expected_version:profile.version,display_name:' Марина ',roles:['customer'],active_role:'customer'});
  assert.equal(profile.display_name,'Марина');assert.deepEqual(profile.roles,['customer']);
  assert.equal((await api.store.all('subscription','KZ')).length,0);
  const stale=profile.version;
  profile=await call('PATCH',{expected_version:profile.version,display_name:'Изменено на другом устройстве'});
  await assert.rejects(()=>call('PATCH',{expected_version:stale,display_name:'Новый ввод',roles:['customer','executor'],active_role:'executor'}),e=>e.getStatus()===409&&e.getResponse().error.code==='STATE_CONFLICT'&&e.getResponse().error.details.current_version===profile.version);
  const current=await call('GET');assert.equal(current.display_name,'Изменено на другом устройстве');assert.equal(current.active_role,'customer');
  profile=await call('PATCH',{expected_version:current.version,display_name:'Новый ввод',roles:['customer','executor'],active_role:'executor'});
  assert.equal(profile.active_role,'executor');assert.equal(profile.verification,'not_started');assert.deepEqual(profile.roles,['customer','executor']);
  assert.equal((await api.store.all('subscription','KZ')).length,0);assert.equal((await api.store.all('purchase','KZ')).length,0);
 }finally{await api.store.close();}
});
