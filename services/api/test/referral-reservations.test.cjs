const {test}=require('node:test');
const assert=require('node:assert/strict');
const {randomUUID}=require('node:crypto');
const {Marketplace}=require('../dist/marketplace');
const {Store}=require('../dist/store');
const record=(kind,owner,data)=>({id:randomUUID(),kind,owner,country:'KZ',version:1,created_at:new Date().toISOString(),...data});
test('referral budget is reserved before attribution and accepted promises survive stopping the campaign',async()=>{
  const inviterOne=randomUUID(),inviterTwo=randomUUID(),inviteeOne=randomUUID(),inviteeTwo=randomUUID(),inviteeThree=randomUUID();
  const api=new Marketplace(new Store('memory://'));await api.initialize();
  try{
    const campaign=record('referral_campaign','system',{status:'effective',payload:{threshold:2,budget_units:1,reward_duration_seconds:3600,qualifying_event:'completed_order',capabilities:['search_full']}});
    await api.store.put(campaign);
    const first=await api.growth.referrals(inviterOne,'KZ'),second=await api.growth.referrals(inviterTwo,'KZ');
    const a=await api.growth.attribute(inviteeOne,'KZ',first.code);
    await assert.rejects(()=>api.growth.attribute(inviteeTwo,'KZ',second.code),e=>e.getResponse().error.code==='REFERRAL_BUDGET_EXHAUSTED');
    const b=await api.growth.attribute(inviteeTwo,'KZ',first.code);
    assert.equal(a.reservation_id,b.reservation_id);
    await assert.rejects(()=>api.growth.attribute(inviteeThree,'KZ',first.code),e=>e.getResponse().error.code==='REFERRAL_BUDGET_EXHAUSTED');
    await api.store.put({...campaign,status:'stopped',version:2});
    await assert.rejects(()=>api.growth.attribute(inviteeThree,'KZ',first.code),e=>e.getResponse().error.code==='CAMPAIGN_UNAVAILABLE');
    await api.growth.qualify(inviteeOne,'KZ','executor_verified',randomUUID());
    assert.equal((await api.store.all('referral_reward','KZ')).length,0);
    await api.growth.qualify(inviteeOne,'KZ','completed_order',randomUUID());
    assert.equal((await api.store.all('referral_reward','KZ')).length,0);
    await api.growth.qualify(inviteeTwo,'KZ','completed_order',randomUUID());
    await api.growth.qualify(inviteeTwo,'KZ','completed_order',randomUUID());
    const rewards=await api.store.all('referral_reward','KZ');assert.equal(rewards.length,1);
    assert.deepEqual(new Set(rewards[0].qualifying_attributions),new Set([a.id,b.id]));
    assert.equal((await api.store.all('referral_reservation','KZ'))[0].status,'issued');
    const redeemed=await api.growth.redeem(inviterOne,'KZ',rewards[0].id);
    assert.equal((await api.growth.redeem(inviterOne,'KZ',rewards[0].id)).grant_id,redeemed.grant_id);
    assert.equal((await api.store.all('grant','KZ')).length,1);
  }finally{await api.store.close();}
});

test('attribution window rejects late codes before reserving budget but preserves accepted promises',async()=>{
 const inviter=randomUUID();
 const api=new Marketplace(new Store('memory://'));await api.initialize();
 try{
  const campaign=record('referral_campaign','system',{status:'effective',payload:{threshold:1,budget_units:2,reward_duration_seconds:3600,qualifying_event:'completed_order',capabilities:['search_full'],attribution_window_days:1}});await api.store.put(campaign);
  const referrer=await api.growth.referrals(inviter,'KZ');
  const late=record('user','late',{created_at:new Date(Date.now()-2*86400000).toISOString()});await api.store.put(late);
  await assert.rejects(()=>api.growth.attribute(late.id,'KZ',referrer.code),e=>e.getResponse().error.code==='ATTRIBUTION_WINDOW_EXPIRED');
  assert.equal((await api.store.all('referral_reservation','KZ')).length,0);assert.equal((await api.store.all('referral_attribution','KZ')).length,0);
  const recent=record('user','recent',{});await api.store.put(recent);await api.growth.attribute(recent.id,'KZ',referrer.code);
  await api.store.put({...recent,created_at:late.created_at});await api.growth.qualify(recent.id,'KZ','completed_order',randomUUID());assert.equal((await api.store.all('referral_reward','KZ')).length,1);
  const legacy=record('referral_campaign','system',{status:'effective',payload:{...campaign.payload}});delete legacy.payload.attribution_window_days;await api.store.put({...campaign,status:'stopped'});await api.store.put(legacy);
  await api.growth.attribute(late.id,'KZ',referrer.code);assert.equal((await api.store.all('referral_attribution','KZ')).length,2);
 }finally{await api.store.close();}
});
