const {test}=require('node:test');
const assert=require('node:assert/strict');
const {randomUUID}=require('node:crypto');
const {Marketplace}=require('../dist/marketplace');
const {Store}=require('../dist/store');
const {pricePayload}=require('../dist/price-payload');
const row=(kind,owner,data)=>({id:randomUUID(),kind,owner,country:'KZ',version:1,created_at:new Date().toISOString(),...data});
test('customer 500/30-day subscription requires identity, unlocks only customer rights and preserves existing work on expiry',async()=>{
 const api=new Marketplace(new Store('memory://'));await api.initialize();
 try{
  const session=await api.handle('POST','/auth/register',{country:'KZ',phone:'+77000000692',password:'Isolated customer subscription!'},undefined,randomUUID());
  const call=(m,p,b={},q={})=>api.handle(m,p,b,'Bearer '+session.access_token,randomUUID(),q);
  const offers=await call('GET','/billing/offers');assert.deepEqual(offers.plans.map(p=>p.code),['customer']);assert.equal(offers.plans[0].amount_minor,50000);assert.equal(offers.plans[0].duration_days,30);
  const draft=await api.store.put(row('order',session.user.id,{status:'draft',revision:1,category_id:(await api.store.all('category','KZ'))[0].id,title:'Заказ для проверки доступа',description:'Описание изолированного заказа для проверки доступа.',city:'Алматы'}));
  const publish=()=>call('POST','/orders/'+draft.id+'/publish',{expected_version:1});
  await assert.rejects(publish,e=>e.getResponse().error.code==='VERIFICATION_REQUIRED');
  await api.store.put({...await api.store.get(session.user.id),verification:'passed'});
  await assert.rejects(publish,e=>e.getResponse().error.code==='ENTITLEMENT_REQUIRED');
  await assert.rejects(()=>call('GET','/contractors'),e=>e.getResponse().error.code==='ENTITLEMENT_REQUIRED');
  for(const [path,query] of [['/top-listings',{}],['/promoted-listings',{placement_id:'home.promoted.services'}],['/contractors/map',{}]])await assert.rejects(()=>call('GET',path,{},query),e=>e.getResponse().error.code==='ENTITLEMENT_REQUIRED');
  const payload=pricePayload({product_type:'subscription',plan:'customer',role:'customer',provider:'isolated',product_id:'customer-30',amount_minor:50000,currency:'KZT',period:'days',duration_days:30,time_zone:'Asia/Almaty'},'KZ');
  await api.store.put(row('price_version',session.user.id,{status:'effective',payload}));
  const purchase={user_id:session.user.id,country:'KZ',provider:'isolated',product_id:'customer-30',transaction_id:'customer-paid',original_transaction_id:'customer-paid',environment:'sandbox',amount_minor:50000,currency:'KZT',revision:1,state:'active',valid_until:new Date(Date.now()+30*86400000).toISOString()};
  const result=await api.commerce.apply(purchase);const grant=(await api.store.all('grant','KZ')).find(g=>g.source_id===result.subscription.id);
  assert.equal(grant.role,'customer');assert.deepEqual(grant.capabilities,['view_contractors','publish_order']);assert.equal(grant.capabilities.includes('top100'),false);
  assert.equal((await publish()).status,'open');assert.deepEqual((await call('GET','/contractors')).items,[]);
  const existing=await api.store.get(draft.id);assert.equal((await call('GET','/orders/'+draft.id)).id,draft.id);
  await api.store.put({...await api.store.get(session.user.id),roles:['customer','executor'],active_role:'executor'});
  await assert.rejects(()=>call('GET','/orders'),e=>e.getResponse().error.code==='ENTITLEMENT_REQUIRED');
  await api.store.put({...await api.store.get(session.user.id),active_role:'customer'});
  await api.commerce.apply({...purchase,revision:2,state:'expired'});
  await assert.rejects(()=>call('GET','/contractors'),e=>e.getResponse().error.code==='ENTITLEMENT_REQUIRED');
  assert.equal((await call('GET','/orders/'+existing.id)).id,existing.id);assert.equal((await call('GET','/me')).id,session.user.id);
  await assert.rejects(()=>call('POST','/billing/verify-purchase',{provider:'missing',transaction_reference:'not a payment'}),e=>e.getResponse().error.code==='PROVIDER_UNAVAILABLE');
 }finally{await api.store.close();}
});
