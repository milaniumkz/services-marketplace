const {test}=require('node:test'),assert=require('node:assert/strict'),{randomUUID}=require('node:crypto');
const {Marketplace}=require('../dist/marketplace'),{Store}=require('../dist/store');
test('owner toggles BCC, VTB and rewarded subscriptions independently, globally, without disabling ordinary ads or erasing earned progress',async()=>{
 const api=new Marketplace(new Store('memory://'));await api.initialize();try{
 const password='Isolated payment controls password!',boss=await api.handle('POST','/auth/register',{country:'KZ',phone:'+77000002501',password});await api.store.put({...await api.store.get(boss.user.id),staff_permissions:['platform_owner']});const owner=await api.handle('POST','/auth/staff-login',{country:'KZ',phone:boss.user.phone,password}),customer=await api.handle('POST','/auth/register',{country:'BY',phone:'+375291235501',password});
 const call=(u,m,p,b={},q={})=>api.handle(m,p,b,'Bearer '+u.access_token,randomUUID(),q);
 const get=()=>call(owner,'GET','/admin/payment-controls');assert.deepEqual(await get(),{bcc_enabled:true,vtb_enabled:true,rewarded_enabled:true,version:0});
 await assert.rejects(()=>call(customer,'PUT','/admin/payment-controls',{bcc_enabled:false,expected_version:0}),e=>e.getStatus()===403);
 await call(owner,'PUT','/admin/web-ads',{expected_version:0,enabled:true,rewarded_enabled:true,banner_id:'R-A-20302217-1',mobile_rewarded_id:'R-A-20302217-2',desktop_rewarded_id:'R-A-20302217-3',reward_kind:'subscription',reward_days:30,customer_views:5,standard_views:5,top100_views:5,daily_cap:30,cooldown_seconds:0});
 const configBefore=await call(owner,'GET','/admin/web-ads');
 let c=await call(owner,'PUT','/admin/payment-controls',{bcc_enabled:false,expected_version:0});assert.equal(c.bcc_enabled,false);assert.equal(c.vtb_enabled,true);assert.equal(c.rewarded_enabled,true);
 await assert.rejects(()=>call(owner,'PUT','/admin/payment-controls',{vtb_enabled:false,expected_version:0}),e=>e.getStatus()===409);
 c=await call(owner,'PUT','/admin/payment-controls',{vtb_enabled:false,expected_version:c.version});assert.equal(c.vtb_enabled,false);
 c=await call(owner,'PUT','/admin/payment-controls',{rewarded_enabled:false,expected_version:c.version});
 const shown=await call(customer,'GET','/me/web-ads');assert.equal(shown.enabled,true);assert.equal(shown.rewarded_enabled,false);assert.equal(shown.offers[0].required_views,5);
 await assert.rejects(()=>call(customer,'POST','/me/web-ads/reward-sessions',{target:'customer',platform:'touch'}),e=>e.getStatus()===403);
 const progress={id:randomUUID(),kind:'web_ad_progress',owner:customer.user.id,country:'BY',version:1,created_at:new Date().toISOString(),status:'collecting',target:'customer',required_views:5,completed_views:4};await api.store.put(progress);
 const subscription={id:randomUUID(),kind:'subscription',owner:customer.user.id,country:'BY',version:1,created_at:new Date().toISOString(),status:'active',valid_until:new Date(Date.now()+86400000).toISOString(),is_ad_supported:true,price_snapshot:{plan:'customer'}};await api.store.put(subscription);
 c=await call(owner,'PUT','/admin/payment-controls',{rewarded_enabled:true,expected_version:c.version});const resumed=await call(customer,'GET','/me/web-ads');assert.equal(resumed.enabled,true);assert.equal(resumed.rewarded_enabled,true);assert.equal(resumed.offers[0].completed_views,4);assert.equal(resumed.offers[0].required_views,5);
 assert.deepEqual(await api.store.get(subscription.id),subscription);assert.deepEqual(await call(owner,'GET','/admin/web-ads'),configBefore);
 assert.equal((await api.store.all('audit','KZ')).filter(r=>r.action==='billing.controls_changed').length,4);
 assert.equal((await get()).bcc_enabled,false);assert.equal((await get()).vtb_enabled,false);
 }finally{await api.store.close();}
});
