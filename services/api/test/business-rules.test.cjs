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
    const policy=record('placement_policy','system',{status:'effective',payload:{placement_id:'test-placement',capacity:1}});await api.store.put(policy);
    const price=record('price_version','system',{status:'effective',payload:{duration_days:7,amount_minor:100,product_type:'boost'}});await api.store.put(price);
    await api.store.put(record('grant',u.user.id,{valid_until:new Date(Date.now()+86400000).toISOString(),capabilities:['search_full']}));
    const boost=await command(api,u,'POST','/boost-reservations',{target_id:first.id,placement_id:'test-placement',price_id:price.id});assert.equal(boost.status,'reserved');
    await assert.rejects(()=>command(api,u,'POST','/boost-reservations',{target_id:second.id,placement_id:'test-placement',price_id:price.id}),e=>e.getResponse().error.code==='PLACEMENT_FULL');
    await api.store.put({...first,expires_at:new Date(Date.now()+86400000).toISOString(),version:2});
    await assert.rejects(()=>api.growth.reserveBoost(u.user.id,'KZ',{target_id:first.id,placement_id:'test-placement',price_id:price.id}),e=>e.getResponse().error.code==='TARGET_EXPIRES_EARLY');
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
    await api.store.put(record('push_token',u.user.id,{token:'isolated-test-token',status:'active'}));
    let calls=0;api.providers.push={send:async(token,event)=>{calls++;assert.equal(event.event_id,outbox.event_id);assert.equal('phone' in event,false);return {provider_message_id:'contract-test-message'};}};
    assert.equal((await api.deliverOutbox()).sent,1);assert.equal((await api.store.get(outbox.id)).status,'sent');
    await api.deliverOutbox();assert.equal(calls,1);
  }finally{await api.store.close();}
});
