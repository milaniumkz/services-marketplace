const {test}=require('node:test'),assert=require('node:assert/strict'),{randomUUID}=require('node:crypto');
const {Marketplace}=require('../dist/marketplace'),{Store}=require('../dist/store');
const {checkoutOffers,buyTestQuote}=require('../dist/subscription-quotes');
const {activatePeriods}=require('../dist/subscription-periods');
const {bestDiscount,useDiscount}=require('../dist/personal-discounts');
const {referralPolicy}=require('../dist/referral-policy');
const day=86400000;
const row=(kind,owner,data)=>({id:randomUUID(),kind,owner,country:'KZ',version:1,created_at:new Date().toISOString(),...data});
async function setup(){const api=new Marketplace(new Store('memory://'));await api.initialize();const user=row('user','self',{roles:['executor'],active_role:'executor',status:'active',verification:'passed'});user.owner=user.id;await api.store.put(user);await api.store.put(row('test_payment_settings','system',{enabled:true}));return {api,user,offers:async(now)=> (await checkoutOffers(api.store,api.commerce,user,now)).items,buy:async(o,now)=>buyTestQuote(api.store,api.commerce,user,{offer_id:o.id,accepted:true,amount_minor:o.amount_minor,currency:o.currency},now)};}
test('standard renewal queues, prorated upgrade preserves paid end, separate Top-100 and repeated quotes cannot duplicate rights',async()=>{
 const {api,user,offers,buy}=await setup();try{
 const now=new Date(),standard=await buy((await offers(now)).find(o=>o.plan==='standard'),now);
 const initialEnd=standard.subscription.valid_until;
 const addon=(await offers(now)).find(o=>o.plan==='top100');assert.equal(addon.amount_minor,50000);
 const top=await buy(addon,now);assert.equal(top.subscription.valid_until,initialEnd);assert.equal((await buy(addon,now)).subscription.id,top.subscription.id);
 const renew=await buy((await offers(now)).find(o=>o.plan==='standard'),now);assert.equal(renew.subscription.status,'scheduled');assert.equal(renew.subscription.valid_from,initialEnd);
 assert.equal(Date.parse(renew.subscription.valid_until)-Date.parse(initialEnd),30*day);
 assert.ok(!(await api.store.all('grant','KZ')).some(g=>g.source_id===renew.subscription.id));
 const later=new Date(now.getTime()+15*day),upgrade=(await offers(later)).find(o=>o.offer_kind==='upgrade');assert.equal(upgrade.amount_minor,75000);
 const premium=await buy(upgrade,later);assert.equal(premium.subscription.is_upgrade,true);assert.equal(premium.subscription.valid_until,renew.subscription.valid_until);
 assert.equal((await offers(later)).some(o=>o.offer_kind==='upgrade'||o.plan==='top100'),false);
 await activatePeriods(api.store,{...user,status:'deleted'},new Date(Date.parse(initialEnd)+1000));assert.ok(!(await api.store.all('grant','KZ')).some(g=>g.source_id===renew.subscription.id));
 await activatePeriods(api.store,user,new Date(Date.parse(initialEnd)+1000));assert.ok((await api.store.all('grant','KZ')).some(g=>g.source_id===renew.subscription.id));
 const stale=(await offers(later)).find(o=>o.plan==='standard');await assert.rejects(()=>buy(stale,new Date(later.getTime()+6*60000)),e=>e.getResponse().error.code==='OFFER_CHANGED');
 }finally{await api.store.close();}
});
test('referral threshold automatically issues one personal discount; discounted upgrade consumes it once; bonus days append and preserve prior purchases',async()=>{
 const {api,user,offers,buy}=await setup();try{
 await buy((await offers()).find(o=>o.plan==='standard'));
 const policy=referralPolicy({threshold:2,budget_units:10,reward_duration_seconds:7*86400,qualifying_event:'registered',reward_kind:'discount',discount_percent:20,discount_services:['all'],discount_max_uses:1});
 const campaign=row('referral_campaign','system',{status:'effective',payload:policy});await api.store.put(campaign);
 const referral=await api.growth.referrals(user.id,'KZ');
 const invite=async()=>{const u=row('user','self',{status:'active'});await api.store.put(u);return api.growth.attribute(u.id,'KZ',referral.code);};
 await invite();assert.equal((await api.store.all('referral_discount','KZ')).length,0);
 await invite();const discounts=await api.store.all('referral_discount','KZ');assert.equal(discounts.length,1);assert.equal(discounts[0].percent,20);
 const upgrade=(await offers()).find(o=>o.offer_kind==='upgrade');assert.equal(upgrade.discount_percent,20);assert.ok(upgrade.amount_minor<=40000);
 const result=await buy(upgrade);await buy(upgrade);assert.equal((await api.store.get(discounts[0].id)).uses,1);assert.equal(result.subscription.price_snapshot.discount_percent,20);
 const reward=row('referral_reward',user.id,{status:'available',expires_at:new Date(Date.now()+day).toISOString(),policy_snapshot:{reward_kind:'subscription_days',reward_plan:'current',reward_duration_seconds:3*86400}});await api.store.put(reward);
 const before=(await api.store.all('subscription','KZ')).filter(s=>!s.is_upgrade).map(s=>Date.parse(s.valid_until));
 const redeemed=await api.growth.redeem(user.id,'KZ',reward.id),period=await api.store.get(redeemed.subscription_id);
 assert.equal(period.price_snapshot.plan,'premium');assert.equal(Date.parse(period.valid_from),Math.max(...before));assert.equal(Date.parse(period.valid_until)-Date.parse(period.valid_from),3*day);
 assert.equal((await api.growth.redeem(user.id,'KZ',reward.id)).subscription_id,period.id);
 await assert.rejects(()=>api.growth.attribute(user.id,'KZ',referral.code),e=>e.getResponse().error.code==='REFERRAL_INELIGIBLE');
 }finally{await api.store.close();}
});
test('limited discounts account for boost reservations and never apply across owners or countries',async()=>{
 const {api,user}=await setup();try{
 const d=row('referral_discount',user.id,{status:'active',percent:30,services:['all'],uses:0,max_uses:1,valid_until:new Date(Date.now()+day).toISOString()});await api.store.put(d);
 assert.equal((await bestDiscount(api.store,user,'boost')).id,d.id);
 const hold=row('boost',user.id,{status:'reserved',reservation_expires_at:new Date(Date.now()+60000).toISOString(),price_snapshot:{discount_id:d.id,discount_version:1}});await api.store.put(hold);
 assert.equal(await bestDiscount(api.store,user,'standard'),undefined);
 await assert.rejects(()=>useDiscount(api.store,user.id,'KZ',{discount_id:d.id,discount_version:1}),e=>e.getResponse().error.code==='OFFER_CHANGED');
 assert.equal(await bestDiscount(api.store,{...user,country:'RU'},'boost'),undefined);
 await useDiscount(api.store,user.id,'KZ',hold.price_snapshot,new Date(),hold.id);assert.equal((await api.store.get(d.id)).status,'used');
 }finally{await api.store.close();}
});
test('customer bonus extends customer access and executor-only rewards wait without crossing roles',async()=>{
 const {api,user}=await setup();try{
 const customer={...user,roles:['customer'],active_role:'customer'};await api.store.put(customer);
 const future=new Date(Date.now()+10*day).toISOString();await api.store.put(row('subscription',user.id,{status:'active',valid_until:future,price_snapshot:{plan:'customer'},role:'customer'}));
 const reward=row('referral_reward',user.id,{status:'available',expires_at:new Date(Date.now()+day).toISOString(),policy_snapshot:{reward_kind:'subscription_days',reward_plan:'current',reward_duration_seconds:7*86400}});await api.store.put(reward);
 const redeemed=await api.growth.redeem(user.id,'KZ',reward.id),period=await api.store.get(redeemed.subscription_id);assert.equal(period.price_snapshot.plan,'customer');assert.equal(period.valid_from,future);assert.equal(period.status,'scheduled');
 const top=row('referral_reward',user.id,{...reward,id:randomUUID(),policy_snapshot:{reward_kind:'subscription_days',reward_plan:'top100',reward_duration_seconds:86400}});await api.store.put(top);
 await api.growth.redeemEligible(user.id,'KZ');assert.equal((await api.store.get(top.id)).status,'available');
 await assert.rejects(()=>api.growth.redeem(user.id,'RU',reward.id),e=>e.getStatus()===404);
 assert.throws(()=>referralPolicy({threshold:1,budget_units:1,reward_duration_seconds:86400,qualifying_event:'registered',reward_kind:'discount',discount_percent:101,discount_services:['all']}));
 }finally{await api.store.close();}
});
