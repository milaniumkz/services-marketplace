const {test}=require('node:test');
const assert=require('node:assert/strict');
const {randomUUID}=require('node:crypto');
const {Marketplace}=require('../dist/marketplace');
const {Store}=require('../dist/store');
const record=(kind,owner,data)=>({id:randomUUID(),kind,owner,country:'KZ',version:1,created_at:new Date().toISOString(),...data});
test('referral budget is reserved before attribution and accepted promises survive stopping the campaign',async()=>{
  const api=new Marketplace(new Store('memory://'));await api.initialize();
  try{
    const campaign=record('referral_campaign','system',{status:'effective',payload:{threshold:2,budget_units:1,reward_duration_seconds:3600,qualifying_event:'completed_order',capabilities:['search_full']}});
    await api.store.put(campaign);
    const first=await api.growth.referrals('inviter-one','KZ'),second=await api.growth.referrals('inviter-two','KZ');
    const a=await api.growth.attribute('invitee-one','KZ',first.code);
    await assert.rejects(()=>api.growth.attribute('invitee-two','KZ',second.code),e=>e.getResponse().error.code==='REFERRAL_BUDGET_EXHAUSTED');
    const b=await api.growth.attribute('invitee-two','KZ',first.code);
    assert.equal(a.reservation_id,b.reservation_id);
    await assert.rejects(()=>api.growth.attribute('invitee-three','KZ',first.code),e=>e.getResponse().error.code==='REFERRAL_BUDGET_EXHAUSTED');
    await api.store.put({...campaign,status:'stopped',version:2});
    await assert.rejects(()=>api.growth.attribute('invitee-three','KZ',first.code),e=>e.getResponse().error.code==='CAMPAIGN_UNAVAILABLE');
    await api.growth.qualify('invitee-one','KZ','executor_verified',randomUUID());
    assert.equal((await api.store.all('referral_reward','KZ')).length,0);
    await api.growth.qualify('invitee-one','KZ','completed_order',randomUUID());
    assert.equal((await api.store.all('referral_reward','KZ')).length,0);
    await api.growth.qualify('invitee-two','KZ','completed_order',randomUUID());
    await api.growth.qualify('invitee-two','KZ','completed_order',randomUUID());
    const rewards=await api.store.all('referral_reward','KZ');assert.equal(rewards.length,1);
    assert.deepEqual(new Set(rewards[0].qualifying_attributions),new Set([a.id,b.id]));
    assert.equal((await api.store.all('referral_reservation','KZ'))[0].status,'issued');
    const redeemed=await api.growth.redeem('inviter-one','KZ',rewards[0].id);
    assert.equal((await api.growth.redeem('inviter-one','KZ',rewards[0].id)).grant_id,redeemed.grant_id);
    assert.equal((await api.store.all('grant','KZ')).length,1);
  }finally{await api.store.close();}
});
