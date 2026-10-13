const {test}=require('node:test');
const assert=require('node:assert/strict');
const {randomUUID}=require('node:crypto');
const {Store}=require('../dist/store');
const {Marketplace}=require('../dist/marketplace');
const {totp}=require('../dist/totp');
test('regional controls require independent approval and stop registration and new work while preserving existing work',async()=>{
 const api=new Marketplace(new Store('memory://'));await api.initialize();
 const password='Isolated country-control password!';
 const register=phone=>api.handle('POST','/auth/register',{country:'KZ',phone,password},undefined,undefined,{},phone);
 const call=(user,method,path,body={})=>api.handle(method,path,body,'Bearer '+user.access_token,randomUUID(),{},'country-controls-test');
 try{
  const customer=await register('+77000000096'),executor=await register('+77000000097'),author=await register('+77000000098'),approver=await register('+77000000099');
  const staff=[];
  for(const session of [author,approver]){
   const user=await api.store.get(session.user.id),secret='00112233445566778899aabbccddeeff00112233';
   await api.store.put({...user,staff_permissions:['administrator'],totp_secret:secret});
   staff.push(await api.handle('POST','/auth/staff-login',{country:'KZ',phone:user.phone,password,mfa_code:totp(secret)},undefined,undefined,{},user.phone+'staff'));
  }
  const user=await api.store.get(executor.user.id);await api.store.put({...user,roles:['customer','executor'],verification:'passed'});
  for(const session of [customer,executor])await api.store.put({id:randomUUID(),kind:'grant',owner:session.user.id,country:'KZ',version:1,created_at:new Date().toISOString(),valid_until:new Date(Date.now()+86400000).toISOString(),capabilities:['publish_order','search_full','send_offer','select_offer'],source:'isolated-country-fixture'});
  const draft=await call(customer,'POST','/orders',{title:'Работа до приостановки',description:'Достаточно подробное описание для проверки рабочей цепочки.',category_id:'1',city:'Алматы',budget_amount:10000});
  const order=await call(customer,'POST','/orders/'+draft.id+'/publish',{expected_version:draft.version});
  const offer=await call(executor,'POST','/orders/'+order.id+'/offers',{text:'Выполню работу',amount:10000,acknowledged_revision:order.revision});
  const selected=await call(customer,'POST','/orders/'+order.id+'/select',{expected_version:order.version,offer_id:offer.id,offer_version:offer.version});
  const started=await call(executor,'POST','/orders/'+order.id+'/start',{expected_version:selected.version});
  const control=await call(staff[0],'POST','/admin/country-controls',{title:'Приостановка новых действий',reason:'Изолированная проверка режима страны',payload:{registration_enabled:false,stop_new_business:true}});
  await assert.rejects(()=>call(staff[0],'POST','/admin/country-controls/'+control.id+'/publish',{expected_version:1,reason:'Попытка самостоятельного подтверждения'}),e=>e.getResponse().error.code==='SECOND_APPROVAL_REQUIRED');
  const effective=await call(staff[1],'POST','/admin/country-controls/'+control.id+'/publish',{expected_version:1,reason:'Независимое подтверждение режима страны'});
  await assert.rejects(()=>register('+77000000100'),e=>e.getResponse().error.code==='COUNTRY_DISABLED');
  const next=await call(customer,'POST','/orders',{title:'Новый свободный черновик',description:'Черновик сохраняется, но новое размещение приостановлено.',category_id:'1',city:'Алматы'});
  await assert.rejects(()=>call(customer,'POST','/orders/'+next.id+'/publish',{expected_version:1}),e=>e.getResponse().error.code==='COUNTRY_BUSINESS_PAUSED');
  const completed=await call(executor,'POST','/orders/'+order.id+'/complete',{expected_version:started.version});
  assert.equal((await call(customer,'POST','/orders/'+order.id+'/confirm-completion',{expected_version:completed.version})).status,'completed');
  const config=await api.handle('GET','/public/config');assert.equal(config.countries.find(c=>c.code==='KZ').registration_enabled,false);assert.equal(config.countries.find(c=>c.code==='RS').registration_enabled,true);
  await assert.rejects(()=>call(staff[0],'POST','/admin/country-controls/'+control.id+'/stop',{expected_version:effective.version,reason:'Нельзя обойти второе подтверждение'}),e=>e.getResponse().error.code==='SECOND_APPROVAL_REQUIRED');
 }finally{await api.store.close();}
});
