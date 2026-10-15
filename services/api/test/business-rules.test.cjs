const {test}=require('node:test');
const assert=require('node:assert/strict');
const {randomUUID}=require('node:crypto');
const {Store}=require('../dist/store');
const {Marketplace}=require('../dist/marketplace');
const {promoEnd}=require('../dist/configuration');
const {matchesRule}=require('../dist/moderation');
const create=(api,phone,name='Участник теста')=>api.handle('POST','/auth/register',{country:'KZ',phone,password:'a long safe test password',display_name:name},undefined,undefined,{},phone);
const command=(api,u,method,path,body={},q={})=>api.handle(method,path,body,'Bearer '+u.access_token,randomUUID(),q);
const record=(kind,owner,extra={})=>({id:randomUUID(),kind,owner,country:'KZ',version:1,created_at:new Date().toISOString(),...extra});

test('promotion boundaries use IANA zones, including DST; exceptions cannot bypass another forbidden match',()=>{
  assert.equal(promoEnd('2026-10-25','Europe/Belgrade'),'2026-10-25T23:00:00Z');
  assert.equal(promoEnd('2026-10-12','Asia/Almaty'),'2026-10-12T19:00:00Z');
  assert.equal(matchesRule('учебный маркер','маркер','exact_word',['учебный маркер']),false);
  assert.equal(matchesRule('учебный маркер и запрещённый маркер','маркер','exact_word',['учебный маркер']),true);
});

test('referral attribution, single-level qualification and reward retry never duplicate benefits',async()=>{
  const api=new Marketplace(new Store('memory://'));await api.initialize();
  try{
    const a=await create(api,'+77000000201'),b=await create(api,'+77000000202');
    await api.store.put(record('referral_campaign','system',{status:'effective',payload:{threshold:1,budget_units:1,reward_duration_seconds:3600,qualifying_event:'completed_order',capabilities:['search_full']}}));
    const referral=await command(api,a,'GET','/me/referrals');
    await assert.rejects(()=>command(api,a,'POST','/referrals/attribute',{code:referral.code}),e=>e.getResponse().error.code==='REFERRAL_INELIGIBLE');
    await command(api,b,'POST','/referrals/attribute',{code:referral.code});
    await assert.rejects(()=>command(api,b,'POST','/referrals/attribute',{code:referral.code}),e=>e.getResponse().error.code==='ATTRIBUTION_ALREADY_SET');
    await api.growth.qualify(b.user.id,'KZ','completed_order',randomUUID());
    await api.growth.qualify(b.user.id,'KZ','completed_order',randomUUID());
    const rewards=(await command(api,a,'GET','/me/referrals')).rewards;assert.equal(rewards.length,1);
    const redeemed=await command(api,a,'POST',`/me/referral-rewards/${rewards[0].id}/redeem`);
    const retry=await command(api,a,'POST',`/me/referral-rewards/${rewards[0].id}/redeem`);assert.equal(retry.grant_id,redeemed.grant_id);
    assert.equal((await api.store.all('grant','KZ')).length,1);
  }finally{await api.store.close();}
});

test('boost reservations preserve capacity and reject a duration beyond the order expiry',async()=>{
  const api=new Marketplace(new Store('memory://'));await api.initialize();
  try {
    const u=await create(api,'+77000000201');
    const first=record('order',u.user.id,{status:'open',title:'Тест размещения',expires_at:new Date(Date.now()+10*86400000).toISOString()});
    const second=record('order',u.user.id,{status:'open',title:'Другой тест размещения',expires_at:new Date(Date.now()+10*86400000).toISOString()});
    await api.store.put(first);await api.store.put(second);
    const policy=record('placement_policy','system',{status:'effective',payload:{placement_id:'search.orders.promoted',capacity:1}});await api.store.put(policy);
    const price=record('price_version','system',{status:'effective',payload:{duration_days:7,amount_minor:100,product_type:'boost'}});await api.store.put(price);
    await api.store.put(record('grant',u.user.id,{valid_until:new Date(Date.now()+86400000).toISOString(),capabilities:['search_full']}));
    const boost=await command(api,u,'POST','/boost-reservations',{target_id:first.id,placement_id:'search.orders.promoted',price_id:price.id});assert.equal(boost.status,'reserved');
    await assert.rejects(()=>command(api,u,'POST','/boost-reservations',{target_id:second.id,placement_id:'search.orders.promoted',price_id:price.id}),e=>e.getResponse().error.code==='PLACEMENT_FULL');
    await api.store.put({...first,expires_at:new Date(Date.now()+86400000).toISOString(),version:2});
    await assert.rejects(()=>api.growth.reserveBoost(u.user.id,'KZ',{target_id:first.id,placement_id:'search.orders.promoted',price_id:price.id}),e=>e.getResponse().error.code==='TARGET_EXPIRES_EARLY');
  }finally{await api.store.close();}
});

test('new account keeps an empty profile; changing a phone requires password and never transfers account ownership',async()=>{
  const api=new Marketplace(new Store('memory://'));await api.initialize();
  try{
    const u=await api.handle('POST','/auth/register',{country:'KZ',phone:'+77000000201',password:'a long safe test password'},undefined,undefined,{},'test');assert.equal(u.user.display_name,'');
    await create(api,'+77000000202');
    await assert.rejects(()=>command(api,u,'POST','/me/phone-change-requests',{new_phone:'+77000000203',current_password:'wrong'}),e=>e.getResponse().error.code==='REAUTH_REQUIRED');
    await assert.rejects(()=>command(api,u,'POST','/me/phone-change-requests',{new_phone:'+77000000202',current_password:'a long safe test password'}),e=>e.getResponse().error.code==='PHONE_CHANGE_UNAVAILABLE');
    const changed=await command(api,u,'POST','/me/phone-change-requests',{new_phone:'+77000000203',current_password:'a long safe test password'});assert.equal(changed.phone_status,'unverified');
    const me=await command(api,u,'GET','/me');assert.equal(me.id,u.user.id);assert.equal(me.phone,'+77000000203');
  }finally{await api.store.close();}
});

test('outbox requires a provider and only records send success after accepted delivery',async()=>{
  const api=new Marketplace(new Store('memory://'));await api.initialize();
  try {
    const u=await create(api,'+77000000201');const outbox=record('outbox',u.user.id,{recipient_id:u.user.id,event_id:randomUUID(),type:'order.updated',status:'pending',attempts:0});await api.store.put(outbox);
    assert.equal((await api.deliverOutbox()).blocked,'push_provider_unavailable');assert.equal((await api.store.get(outbox.id)).status,'pending');
    await command(api,u,'POST','/me/push-tokens',{token:'isolated-test-token',platform:'android'});
    let calls=0;api.providers.push={send:async(token,event)=>{calls++;assert.equal(event.event_id,outbox.event_id);assert.equal('phone' in event,false);return {provider_message_id:'contract-test-message'};}};
    assert.equal((await api.deliverOutbox()).sent,1);assert.equal((await api.store.get(outbox.id)).status,'sent');
    await api.deliverOutbox();assert.equal(calls,1);
  }finally{await api.store.close();}
});

test('paid boost rejects subscription prices, hidden targets and incompatible placements and counts active paid slots',async()=>{
  const api=new Marketplace(new Store('memory://'));await api.initialize();
  try {
    const u=await create(api,'+77000000219');
    const future=new Date(Date.now()+10*86400000).toISOString();
    const order=record('order',u.user.id,{status:'open',title:'Размещение заказа',expires_at:future});
    const existing=record('order',u.user.id,{status:'open',title:'Уже продвигаемый заказ',expires_at:future});
    await api.store.put(order);await api.store.put(existing);
    const placement='search.orders.promoted';
    await api.store.put(record('placement_policy','system',{status:'effective',payload:{placement_id:placement,capacity:1}}));
    await api.store.put(record('placement_policy','system',{status:'effective',payload:{placement_id:'search.services.promoted',capacity:1}}));
    const price=record('price_version','system',{status:'effective',payload:{period:'week',amount_minor:100,currency:'KZT',product_type:'boost'}});
    const subscription=record('price_version','system',{status:'effective',payload:{period:'week',amount_minor:1,currency:'KZT',product_type:'subscription'}});
    await api.store.put(price);await api.store.put(subscription);
    const reserve=(body)=>command(api,u,'POST','/boost-reservations',{target_id:order.id,placement_id:placement,price_id:price.id,...body});
    await assert.rejects(()=>reserve({price_id:subscription.id}),e=>e.getResponse().error.code==='PRICE_UNAVAILABLE');
    await assert.rejects(()=>reserve({placement_id:'search.services.promoted'}),e=>e.getResponse().error.code==='PLACEMENT_UNAVAILABLE');
    await api.store.put({...order,moderation_status:'quarantined'});
    await assert.rejects(()=>reserve({}),e=>e.getResponse().error.code==='TARGET_INELIGIBLE');
    await api.store.put(order);
    await api.store.put(record('boost',u.user.id,{target_id:existing.id,placement_id:placement,status:'active',starts_at:new Date().toISOString(),ends_at:future,reservation_expires_at:'2000-01-01T00:00:00Z',provenance:'paid'}));
    await assert.rejects(()=>reserve({}),e=>e.getResponse().error.code==='PLACEMENT_FULL');
    assert.equal((await api.store.all('boost','KZ')).length,1);
  }finally{await api.store.close();}
});

test('confirmed boost payments recheck hidden targets, exact access and occupied slots without losing payment evidence',async()=>{
 const api=new Marketplace(new Store('memory://'));await api.initialize();
 try{
  const u=await create(api,'+77000000229'),owner=u.user.id,future=new Date(Date.now()+10*86400000).toISOString();
  await api.store.put({...await api.store.get(owner),verification:'passed'});
  let proof;
  api.providers.billing.set('isolated',{name:'isolated',verifyPurchase:async()=>proof});
  for(const scenario of ['capacity','hidden','access']){
   const kind=scenario==='access'?'contractor':'order',placement=kind==='order'?'search.orders.promoted':'search.services.promoted';
   const target=record(kind,owner,{title:'Проверяемая карточка',status:kind==='order'?'open':'published',expires_at:future});await api.store.put(target);
   const policy=record('placement_policy','system',{status:'effective',payload:{placement_id:placement,capacity:1}});await api.store.put(policy);
   const price={provider:'isolated',product_id:'boost',amount_minor:100,currency:'KZT',product_type:'boost',period:'week'};
   const reserved=record('boost',owner,{target_id:target.id,placement_id:placement,status:'reserved',starts_at:new Date().toISOString(),ends_at:future,reservation_expires_at:'2000-01-01T00:00:00Z',price_snapshot:price});await api.store.put(reserved);
   if(scenario==='capacity')await api.store.put(record('boost',owner,{target_id:randomUUID(),placement_id:placement,status:'active',starts_at:new Date().toISOString(),ends_at:future,reservation_expires_at:'2000-01-01T00:00:00Z'}));
   if(scenario==='hidden')await api.store.put({...target,moderation_status:'hidden'});
   if(scenario==='access')await api.store.put(record('grant',owner,{valid_until:future,capabilities:['send_offer']}));
   proof={provider:'isolated',transaction_id:'boost-'+scenario,user_id:owner,country:'KZ',product_id:'boost',environment:'sandbox',amount_minor:100,currency:'KZT',state:'active'};
   const verify=()=>command(api,u,'POST','/boost-purchases/verify',{provider:'isolated',transaction_reference:'proof',reservation_id:reserved.id});
   assert.equal((await verify()).status,'resolution_required',scenario);
   const replay=await verify();assert.equal(replay.duplicate,true);assert.equal(replay.status,'resolution_required');
   assert.equal((await api.store.all('payment_transaction','KZ')).filter(x=>x.transaction_id===proof.transaction_id).length,1);
   for(const row of await api.store.all('boost','KZ'))await api.store.put({...row,status:'revoked'});
   for(const row of await api.store.all('placement_policy','KZ'))await api.store.put({...row,status:'archived'});
  }
 }finally{await api.store.close();}
});
