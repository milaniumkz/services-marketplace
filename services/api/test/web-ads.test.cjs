const {test}=require('node:test'),assert=require('node:assert/strict'),{randomUUID}=require('node:crypto');
const {Marketplace}=require('../dist/marketplace'),{Store}=require('../dist/store');
test('web ad config stays owner-controlled; consent, nonce, expiry, owner binding and idempotent SDK reports never grant paid access',async()=>{
 const api=new Marketplace(new Store('memory://'));await api.initialize();try{
 const password='Web ads test password',u=await api.handle('POST','/auth/register',{country:'KZ',phone:'+77000000871',password});await api.store.put({...await api.store.get(u.user.id),staff_permissions:['platform_owner']});
 const owner=await api.handle('POST','/auth/staff-login',{country:'KZ',phone:u.user.phone,password});
 const call=(token,m,p,b={})=>api.handle(m,p,b,'Bearer '+token,randomUUID());
 const p={expected_version:0,enabled:true,rewarded_enabled:true,banner_id:'R-A-20302217-1',mobile_rewarded_id:'R-A-20302217-2',desktop_rewarded_id:'R-A-20302217-3',reward_kind:'ad_free',reward_seconds:3600,daily_cap:2,cooldown_seconds:0};
 await call(owner.access_token,'PUT','/admin/web-ads',p);
 await assert.rejects(()=>call(owner.access_token,'PUT','/admin/web-ads',p),e=>e.getStatus()===409);
 const a=await api.handle('POST','/auth/register',{country:'BY',phone:'+375291234871',password}),b=await api.handle('POST','/auth/register',{country:'BY',phone:'+375291234872',password});
 await assert.rejects(()=>call(a.access_token,'PUT','/admin/web-ads',p),e=>e.getStatus()===403);
 const cfg=await call(a.access_token,'GET','/me/web-ads');assert.equal(cfg.mobile_rewarded_id,p.mobile_rewarded_id);assert.equal(cfg.consent,false);
 await assert.rejects(()=>call(a.access_token,'POST','/me/web-ads/reward-sessions',{platform:'touch'}),e=>e.getStatus()===403);
 await call(a.access_token,'POST','/me/web-ads/consent',{accepted:true});await call(b.access_token,'POST','/me/web-ads/consent',{accepted:true});
 const s=await call(a.access_token,'POST','/me/web-ads/reward-sessions',{platform:'touch'});assert.equal(s.block_id,p.mobile_rewarded_id);
 const outcome='/me/web-ads/reward-sessions/'+s.id+'/outcome';
 await assert.rejects(()=>call(b.access_token,'POST',outcome,{nonce:s.nonce,completed:true}),e=>e.getStatus()===403);
 await assert.rejects(()=>call(a.access_token,'POST',outcome,{nonce:'wrong',completed:true}),e=>e.getStatus()===403);
 assert.equal((await call(a.access_token,'POST',outcome,{nonce:s.nonce,completed:false})).status,'not_completed');
 assert.equal((await call(a.access_token,'POST',outcome,{nonce:s.nonce,completed:true})).status,'not_completed');
 assert.equal((await api.store.all('web_ad_grant')).length,0);
 const second=await call(a.access_token,'POST','/me/web-ads/reward-sessions',{platform:'desktop'});assert.equal(second.block_id,p.desktop_rewarded_id);
 await call(owner.access_token,'PUT','/admin/web-ads',{...p,expected_version:1,enabled:false});
 const result=await call(a.access_token,'POST','/me/web-ads/reward-sessions/'+second.id+'/outcome',{nonce:second.nonce,completed:true});assert.equal(result.status,'granted');
 await call(a.access_token,'POST','/me/web-ads/reward-sessions/'+second.id+'/outcome',{nonce:second.nonce,completed:true});assert.equal((await api.store.all('web_ad_grant')).length,1);
 assert.equal((await api.store.all('grant')).filter(x=>x.owner===a.user.id).length,0);
 assert.equal((await api.store.all('subscription')).filter(x=>x.owner===a.user.id).length,0);
 await call(owner.access_token,'PUT','/admin/web-ads',{...p,expected_version:2});
 await assert.rejects(()=>call(a.access_token,'POST','/me/web-ads/reward-sessions',{platform:'desktop'}),e=>e.getStatus()===429);
 await call(a.access_token,'POST','/me/web-ads/consent',{accepted:false});assert.equal((await call(a.access_token,'GET','/me/web-ads')).consent,false);
 const third=await call(b.access_token,'POST','/me/web-ads/reward-sessions',{platform:'desktop'});await api.store.put({...await api.store.get(third.id),expires_at:new Date(0).toISOString()});await assert.rejects(()=>call(b.access_token,'POST','/me/web-ads/reward-sessions/'+third.id+'/outcome',{nonce:third.nonce,completed:true}),e=>e.getStatus()===409);
 const revoke=require('../dist/processing-consent-retention').revokeOptionalProcessing;await revoke(api.store,b.user.id,'BY',new Date());await revoke(api.store,b.user.id,'BY',new Date());const history=(await api.store.all('web_ad_consent','BY')).filter(x=>x.owner===b.user.id).sort((x,y)=>y.sequence-x.sequence);assert.equal(history[0].accepted,false);assert.equal(history[0].revocation_source,'account_deletion');assert.equal(history.length,2);
 }finally{await api.store.close();}
});
