const {test}=require('node:test');
const assert=require('node:assert/strict');
const {randomUUID}=require('node:crypto');
const {Marketplace}=require('../dist/marketplace');
const {Store}=require('../dist/store');
const rec=(kind,owner,data)=>({id:randomUUID(),kind,owner,country:'KZ',version:1,created_at:new Date().toISOString(),...data});
test('customer searches, publishes, extends and selects without a subscription; executor access stays gated',async()=>{
 const app=new Marketplace(new Store('memory://'));await app.initialize();try{
  const register=phone=>app.handle('POST','/auth/register',{country:'KZ',phone,password:'Isolated customer policy password'},undefined,randomUUID(),{},phone);
  const customer=await register('+77000000381'),executor=await register('+77000000382');
  const call=(s,m,p,b={})=>app.handle(m,p,b,'Bearer '+s.access_token,randomUUID());
  await app.store.put({...await app.store.get(executor.user.id),roles:['customer','executor'],active_role:'executor',verification:'passed'});
  assert.deepEqual((await call(customer,'GET','/contractors')).items,[]);
  assert.deepEqual((await call(customer,'GET','/billing/offers')).items,[]);
  assert.equal((await call(customer,'GET','/me/monetization-config')).subscription_enabled,false);
  await assert.rejects(()=>call(customer,'POST','/billing/verify-purchase',{provider:'fake',transaction_reference:'no charge'}),e=>e.getResponse().error.code==='EXECUTOR_ROLE_REQUIRED');
  const draft=rec('order',customer.user.id,{status:'draft',revision:1,title:'Реальный сценарий заказа',description:'Описание заказа для проверки бесплатного доступа.',city:'Алматы'});await app.store.put(draft);
  let order=await call(customer,'POST','/orders/'+draft.id+'/publish',{expected_version:1});assert.equal(order.status,'open');
  order=await call(customer,'POST','/orders/'+draft.id+'/extend',{expected_version:order.version,expires_at:new Date(Date.now()+86400000*14).toISOString()});
  const offer=rec('offer',executor.user.id,{order_id:order.id,status:'active',acknowledged_revision:order.revision});await app.store.put(offer);
  const selected=await call(customer,'POST','/orders/'+order.id+'/select',{expected_version:order.version,offer_id:offer.id,offer_version:1});assert.equal(selected.status,'assigned');
  assert.equal((await app.store.all('grant','KZ')).length,0);assert.equal((await app.store.all('entitlement_consumption','KZ')).length,0);
  await assert.rejects(()=>call(executor,'GET','/orders'),e=>e.getResponse().error.code==='ENTITLEMENT_REQUIRED');
  await app.store.put({...await app.store.get(customer.user.id),roles:['customer','executor'],active_role:'customer'});
  assert.deepEqual((await call(customer,'GET','/contractors')).items,[]);
  await app.store.put(rec('monetization_config',customer.user.id,{status:'effective',payload:{subscription_enabled:false}}));
  assert.equal((await call(executor,'GET','/me/monetization-config')).subscription_enabled,false);
  await app.store.put({...await app.store.get(customer.user.id),status:'restricted'});
  await assert.rejects(()=>call(customer,'GET','/contractors'),e=>e.getStatus()===403);
 }finally{await app.store.close();}
});
