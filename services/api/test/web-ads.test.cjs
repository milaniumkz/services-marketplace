const {test}=require('node:test'),assert=require('node:assert/strict'),{randomUUID,createHash}=require('node:crypto');
const {Marketplace}=require('../dist/marketplace'),{Store}=require('../dist/store');
test('rewarded subscriptions require separate complete server-side bundles, preserve paid periods and never grant on early close or replay',async()=>{
 const api=new Marketplace(new Store('memory://'));await api.initialize();try{
 const password='Web ads test password',u=await api.handle('POST','/auth/register',{country:'KZ',phone:'+77000000871',password});await api.store.put({...await api.store.get(u.user.id),staff_permissions:['platform_owner']});
 const owner=await api.handle('POST','/auth/staff-login',{country:'KZ',phone:u.user.phone,password});
 const call=(token,m,p,b={})=>api.handle(m,p,b,'Bearer '+token,randomUUID());
 const p={expected_version:0,enabled:true,rewarded_enabled:true,banner_id:'R-A-20302217-1',mobile_rewarded_id:'R-A-20302217-2',desktop_rewarded_id:'R-A-20302217-3',reward_kind:'subscription',reward_days:30,customer_views:5,standard_views:5,top100_views:5,daily_cap:30,cooldown_seconds:0};
 await call(owner.access_token,'PUT','/admin/web-ads',p);
 await assert.rejects(()=>call(owner.access_token,'PUT','/admin/web-ads',p),e=>e.getStatus()===409);
 await assert.rejects(()=>call(owner.access_token,'PUT','/admin/web-ads',{...p,expected_version:1,banner_id:'R-M-20254161-1'}),e=>e.getStatus()===422);
 const a=await api.handle('POST','/auth/register',{country:'BY',phone:'+375291234871',password}),b=await api.handle('POST','/auth/register',{country:'BY',phone:'+375291234872',password});
 for(const [account,role] of [[a,'customer'],[b,'executor']])await api.store.put({...await api.store.get(account.user.id),active_role:role,roles:[role],verification:'passed'});
 await assert.rejects(()=>call(a.access_token,'PUT','/admin/web-ads',p),e=>e.getStatus()===403);
 await assert.rejects(()=>call(a.access_token,'POST','/me/web-ads/consent',{accepted:true}),e=>e.getStatus()===403);assert.equal((await api.store.all('web_ad_consent','BY')).length,0);
 for(const type of ['privacy','terms']){
  const content='Изолированный тест опубликованного документа '+type,doc={id:randomUUID(),kind:'legal_document',owner:'isolated-legal',country:'BY',version:1,created_at:new Date().toISOString(),published_at:new Date().toISOString(),status:'published',type,locale:'ru',minimum_age:18,content,hash:createHash('sha256').update(content).digest('hex')};await api.store.put(doc);
  for(const account of [a,b])await api.store.put({id:randomUUID(),kind:'consent',country:'BY',owner:account.user.id,version:1,created_at:new Date().toISOString(),sequence:1,accepted:true,age_confirmed:true,document_id:doc.id,document_hash:doc.hash});
 }
 await assert.rejects(()=>call(a.access_token,'POST','/me/web-ads/reward-sessions',{platform:'touch',target:'customer'}),e=>e.getStatus()===403);
 await call(a.access_token,'POST','/me/web-ads/consent',{accepted:true});
 const processing=await call(a.access_token,'GET','/me/processing-consents');assert.equal(processing.ad_personalization,true);
 await call(a.access_token,'POST','/me/processing-consents',{expected_version:processing.version,marketing:true,ad_personalization:false,optional_analytics:false});assert.equal((await call(a.access_token,'GET','/me/web-ads')).consent,false);
 const off=await call(a.access_token,'GET','/me/processing-consents');await call(a.access_token,'POST','/me/processing-consents',{expected_version:off.version,marketing:true,ad_personalization:true,optional_analytics:false});assert.equal((await call(a.access_token,'GET','/me/web-ads')).consent,false);
 for(const account of [a,b])await call(account.access_token,'POST','/me/web-ads/consent',{accepted:true});assert.equal((await call(a.access_token,'GET','/me/processing-consents')).marketing,true);
 const start=(account,target,platform='touch')=>call(account.access_token,'POST','/me/web-ads/reward-sessions',{platform,target});
 const finish=(account,s,completed=true)=>call(account.access_token,'POST','/me/web-ads/reward-sessions/'+s.id+'/outcome',{nonce:s.nonce,completed,completed_views:999});
 const s=await start(a,'customer');assert.equal(s.block_id,p.mobile_rewarded_id);assert.equal((await start(a,'customer')).id,s.id);
 await assert.rejects(()=>finish(b,s),e=>e.getStatus()===403);
 await assert.rejects(()=>call(a.access_token,'POST','/me/web-ads/reward-sessions/'+s.id+'/outcome',{nonce:'wrong',completed:true}),e=>e.getStatus()===403);
 assert.equal((await finish(a,s,false)).status,'not_completed');assert.equal((await finish(a,s)).status,'not_completed');
 await assert.rejects(()=>call(a.access_token,'POST','/me/web-ads/redeem',{target:'customer'}),e=>e.getStatus()===409);
 for(let i=1;i<=5;i++){
  const session=await start(a,'customer','desktop');assert.equal(session.block_id,p.desktop_rewarded_id);const result=await finish(a,session);assert.equal(result.completed_views,i);assert.equal(result.status,i===5?'granted':'progress');assert.deepEqual(await finish(a,session),result);
  assert.equal((await api.store.all('subscription','BY')).filter(x=>x.owner===a.user.id).length,i===5?1:0);
 }
 const sub=(await api.store.all('subscription','BY')).find(x=>x.owner===a.user.id);assert.equal(sub.price_snapshot.plan,'customer');assert.equal(Date.parse(sub.valid_until)-Date.parse(sub.valid_from),30*86400000);assert.equal(sub.price_snapshot.amount_minor,0);assert.equal(sub.verification_method,'client_sdk_callback_reported');
 assert.equal((await api.store.all('payment_transaction')).length,0);
 await assert.rejects(()=>start(b,'top100'),e=>e.getStatus()===403);
 for(let i=1;i<=5;i++)assert.equal((await finish(b,await start(b,'standard'))).status,i===5?'granted':'progress');
 let cfg=await call(b.access_token,'GET','/me/web-ads');assert.equal(cfg.offers.find(x=>x.target==='top100').completed_views,0);assert.equal(cfg.offers.find(x=>x.target==='top100').eligible,true);
 for(let i=1;i<=4;i++)assert.equal((await finish(b,await start(b,'top100'))).status,'progress');
 await call(owner.access_token,'PUT','/admin/web-ads',{...p,expected_version:1,enabled:false,top100_views:2});
 cfg=await call(b.access_token,'GET','/me/web-ads');assert.equal(cfg.enabled,false);assert.equal(cfg.rewarded_enabled,true);assert.equal(cfg.offers.find(x=>x.target==='top100').required_views,5);
 const lastTop=await start(b,'top100'),standardGrant=(await api.store.all('grant','BY')).find(x=>x.owner===b.user.id&&x.plan==='standard');
 await api.store.put({...standardGrant,valid_until:new Date(0).toISOString()});
 const ready=await finish(b,lastTop);assert.equal(ready.status,'ready');assert.equal(ready.completed_views,5);assert.equal((await api.store.all('web_ad_redemption','BY')).filter(x=>x.target==='top100').length,0);
 await api.store.put(standardGrant);const top=await call(b.access_token,'POST','/me/web-ads/redeem',{target:'top100'});assert.equal(top.status,'granted');assert.equal(top.required_views,5);
 await assert.rejects(()=>call(b.access_token,'POST','/me/web-ads/redeem',{target:'top100'}),e=>e.getStatus()===409);
 const grants=(await api.store.all('grant','BY')).filter(x=>x.owner===b.user.id);assert(grants.some(x=>x.plan==='standard'));assert(grants.some(x=>x.plan==='top100'));assert(!grants.some(x=>x.plan==='premium'));
 const next=await start(b,'top100');assert.equal(next.required_views,2);await finish(b,next,false);
 // Customer paid/current access is retained; another reward is scheduled after it.
 for(let i=1;i<=5;i++){const result=await finish(a,await start(a,'customer'));if(i===5){assert.equal(result.scheduled,true);assert.equal(result.valid_from,sub.valid_until);}}
 assert.equal((await api.store.all('web_ad_redemption','BY')).length,4);
 const expired=await start(a,'customer');await api.store.put({...await api.store.get(expired.id),expires_at:new Date(0).toISOString()});await assert.rejects(()=>finish(a,expired),e=>e.getStatus()===409);
 const revoke=require('../dist/processing-consent-retention').revokeOptionalProcessing;await revoke(api.store,b.user.id,'BY',new Date());await revoke(api.store,b.user.id,'BY',new Date());const history=(await api.store.all('web_ad_consent','BY')).filter(x=>x.owner===b.user.id).sort((x,y)=>y.sequence-x.sequence);assert.equal(history[0].accepted,false);assert.equal(history[0].revocation_source,'account_deletion');
 }finally{await api.store.close();}
});
