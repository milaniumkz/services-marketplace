const {test}=require('node:test');const assert=require('node:assert/strict');const {randomUUID}=require('node:crypto');
const {Store}=require('../dist/store'),{Marketplace}=require('../dist/marketplace');
test('independent preferences persist with version checks and legacy service fallback',async()=>{
 const a=new Marketplace(new Store('memory://'));await a.initialize();try{
 const u=await a.handle('POST','/auth/register',{country:'KZ',phone:'+77000000627',password:'Isolated preferences password!'},undefined,randomUUID(),{},'preferences');
 const call=(m,p,b={})=>a.handle(m,p,b,'Bearer '+u.access_token,randomUUID(),{},'preferences');
 const get=()=>call('GET','/me/notification-preferences');
 assert.equal((await get()).orders,true);assert.equal((await get()).support,true);
 let user=await call('GET','/me');
 const p={chat:false,service:true,marketing:false,orders:false,support:true,quiet_hours:{start:'22:00',end:'08:00',time_zone:'Asia/Almaty'}};
 await call('PATCH','/me/notification-preferences',{expected_version:user.version,preferences:p});
 const snapshot=await get();assert.deepEqual(snapshot,{...p,version:user.version+1});
 await assert.rejects(()=>call('PATCH','/me/notification-preferences',{expected_version:user.version,preferences:{...p,orders:true}}),e=>e.getStatus()===409);
 user=await call('GET','/me');
 for(const invalid of [{...p,quiet_hours:false},{...p,quiet_hours:[]},{...p,quiet_hours:{start:'22:00',end:'08:00'}},{...p,support:'true'},{...p,quiet_hours:{start:'24:00',end:'08:00',time_zone:'UTC'}}])await assert.rejects(()=>call('PATCH','/me/notification-preferences',{expected_version:user.version,preferences:invalid}),e=>e.getStatus()===400);
 await call('PATCH','/me/notification-preferences',{expected_version:user.version,preferences:{chat:true,service:false,marketing:false,quiet_hours:null}});
 assert.equal((await get()).orders,false);assert.equal((await get()).support,true);
 user=await a.store.get(u.user.id);await a.store.put({...user,notification_preferences:{chat:true,service:false,marketing:false}});
 assert.equal((await get()).orders,false);assert.equal((await get()).support,false);
 }finally{await a.store.close();}
});
test('delivery suppresses only the disabled category and preserves in-app events',async()=>{
 const a=new Marketplace(new Store('memory://'));await a.initialize();try{
 const u=await a.handle('POST','/auth/register',{country:'KZ',phone:'+77000000628',password:'Isolated preferences password!'},undefined,randomUUID(),{},'preferences-delivery');
 const user=await a.store.get(u.user.id);await a.store.put({...user,notification_preferences:{chat:true,service:true,marketing:false,orders:false,support:true}});
 const ids=[];const event=randomUUID();await a.store.put({id:event,kind:'notification',country:'KZ',owner:user.id,type:'order.created',read:false,created_at:new Date().toISOString(),version:1});
 for(const type of ['order.created','support.message.created','message.created','verification.updated','marketing.campaign']){
 const id=randomUUID();ids.push(id);await a.store.put({id,kind:'outbox',owner:user.id,country:'KZ',recipient_id:user.id,event_id:randomUUID(),type,status:'pending',created_at:new Date().toISOString(),version:1});
 }
 a.providers.push={send:async()=>{throw new Error('No registered device');}};await a.deliverOutbox();
 const states=await Promise.all(ids.map(async id=>(await a.store.get(id)).status));
 assert.deepEqual(states,['suppressed','waiting_token','waiting_token','waiting_token','suppressed']);assert.equal((await a.store.get(event)).read,false);
 }finally{await a.store.close();}
});
