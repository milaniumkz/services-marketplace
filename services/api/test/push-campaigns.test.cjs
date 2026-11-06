const {test}=require('node:test');const assert=require('node:assert/strict');const {randomUUID,randomBytes}=require('node:crypto');
const {Store}=require('../dist/store'),{Marketplace}=require('../dist/marketplace'),{totp}=require('../dist/totp');
const {normalizePushPayload,queuePushCampaigns}=require('../dist/push-campaigns');
const password='Isolated push account password';
const reg=(a,n)=>a.handle('POST','/auth/register',{country:'KZ',phone:'+77000000'+n,password},undefined,randomUUID(),{},'push-register-'+n);
const call=(a,u,m,p,b={},q={})=>a.handle(m,p,b,'Bearer '+u.access_token,randomUUID(),q,'push-tests');
const row=(kind,owner,extra={})=>({id:randomUUID(),kind,owner,country:'KZ',created_at:new Date().toISOString(),version:1,...extra});
const payload=(now=new Date(),type='service')=>({type,service_purpose:'safety',countries:['KZ'],roles:['customer','executor'],locales:['ru'],title:{ru:'Состояние сервиса'},body:{ru:'Проверьте центр уведомлений.'},deep_link:{route:'notification'},time_zone:'Asia/Almaty',send_at:new Date(now.getTime()-1000).toISOString(),deadline_at:new Date(now.getTime()+3600000).toISOString()});
async function staff(a,n){const u=await reg(a,n),r=await a.store.get(u.user.id),secret=randomBytes(20).toString('hex');await a.store.put({...r,totp_secret:secret,staff_permissions:['administrator']});return a.handle('POST','/auth/staff-login',{country:'KZ',phone:r.phone,password,mfa_code:totp(secret)},undefined,undefined,{},'push-staff-'+n);}
async function fixture(run){const a=new Marketplace(new Store('memory://'));await a.initialize();try{await run(a);}finally{await a.store.close();}}
async function campaign(a,owner,p){const c=row('push_campaign',owner,{title:'Изолированная кампания',status:'scheduled',payload:p});await a.store.put(c);return c;}
async function token(a,u,value='isolated-push-token'){return call(a,u,'POST','/me/push-tokens',{token:value,platform:'android'});}
async function marketing(a,u){const r=await a.store.get(u.user.id);await a.store.put({...r,notification_preferences:{marketing:true,service:true,chat:true},version:r.version+1});await a.store.put(row('processing_consent',r.id,{marketing:true}));}
test('campaign validation, audience preview, finite test permission and independent scheduling use real regional records',()=>fixture(async a=>{
 const author=await staff(a,'861'),reviewer=await staff(a,'862'),u=await reg(a,'863');const p=payload();
 let c=await call(a,author,'POST','/admin/push-campaigns',{title:'Проверка кампании',payload:p,reason:'Проверка создания действительного черновика'});
 await assert.rejects(()=>call(a,u,'GET','/admin/push-campaigns/'+c.id),e=>e.getStatus()===403);
 const preview=await call(a,author,'POST','/admin/push-campaigns/'+c.id+'/preview',{expected_version:c.version,reason:'Проверка реального числа получателей'});assert.equal(preview.audience_count,1);assert.equal(preview.provider_configured,false);
 await assert.rejects(()=>call(a,author,'POST','/admin/push-campaigns/'+c.id+'/schedule',{expected_version:c.version,preview_id:preview.preview_id,reason:'Автор не может подтвердить рассылку'}),e=>e.getStatus()===403);
 await assert.rejects(()=>call(a,author,'POST','/admin/push-campaigns/'+c.id+'/test',{expected_version:c.version,recipient_ids:[u.user.id],reason:'Не разрешено отправлять любому аккаунту'}),e=>e.getStatus()===403);
 let user=await a.store.get(u.user.id);await call(a,author,'POST','/admin/users/'+user.id+'/push-test-access',{expected_version:user.version,enabled:true,until:new Date(Date.now()+86400000).toISOString(),reason:'Разрешение изолированного тестового получателя'});
 const testJob=await call(a,author,'POST','/admin/push-campaigns/'+c.id+'/test',{expected_version:c.version,recipient_ids:[u.user.id],reason:'Проверка отправки только разрешённому аккаунту'});assert.notEqual(testJob.id,c.id);assert.equal(testJob.status,'scheduled');
 c=await call(a,author,'PATCH','/admin/push-campaigns/'+c.id,{expected_version:c.version,title:c.title,payload:{...p,body:{ru:'Обновлённый сервисный текст'}},reason:'Изменение после предпросмотра аудитории'});
 await assert.rejects(()=>call(a,reviewer,'POST','/admin/push-campaigns/'+c.id+'/schedule',{expected_version:c.version,preview_id:preview.preview_id,reason:'Старый предпросмотр не должен применяться'}),e=>e.getStatus()===409);
 const actual=await call(a,reviewer,'POST','/admin/push-campaigns/'+c.id+'/preview',{expected_version:c.version,reason:'Повторный предпросмотр после изменения'});
 c=await call(a,reviewer,'POST','/admin/push-campaigns/'+c.id+'/schedule',{expected_version:c.version,preview_id:actual.preview_id,reason:'Независимо проверил и подтверждаю отправку'});assert.equal(c.status,'scheduled');
 await call(a,reviewer,'POST','/admin/push-campaigns/'+c.id+'/cancel',{expected_version:c.version,reason:'Проверка отмены до формирования получателей'});await a.maintenance();assert.equal((await a.store.all('outbox','KZ')).filter(o=>o.campaign_id===c.id).length,0);
 assert.equal(normalizePushPayload({send_local:'2027-01-01T10:00',time_zone:'Asia/Almaty'}).send_at,'2027-01-01T05:00:00.000Z');
 assert.throws(()=>normalizePushPayload({send_local:'2026-03-29T02:30',time_zone:'Europe/Berlin'}));
}));
test('withdrawal after queue suppresses push; retries preserve per-device acceptance and create no duplicate notifications',()=>fixture(async a=>{
 const u=await reg(a,'864');await marketing(a,u);await token(a,u,'isolated-first-token');await token(a,u,'isolated-second-token');
 const now=new Date(),c=await campaign(a,u.user.id,payload(now));await a.maintenance(now);await a.maintenance(now);assert.equal((await a.store.all('outbox','KZ')).filter(r=>r.campaign_id===c.id).length,1);
 assert.equal((await a.deliverOutbox(now)).blocked,'push_provider_unavailable');let sends=0,failSecond=true;
 a.providers.push={send:async(_token,event)=>{sends++;assert.equal(event.title,'Состояние сервиса');assert.equal(event.deep_link.route,'notification');if(sends===2&&failSecond){failSecond=false;throw Error('isolated transient provider failure');}return {provider_message_id:randomUUID()};}};
 await a.deliverOutbox(now);let o=(await a.store.all('outbox','KZ')).find(r=>r.campaign_id===c.id);assert.equal(o.status,'retry');assert.equal(o.accepted_tokens.length,1);
 await a.deliverOutbox(new Date(now.getTime()+5000));assert.equal(sends,3);assert.equal((await a.store.get(o.id)).status,'sent');assert.equal((await a.store.get(c.id)).status,'completed');
 const marketingCampaign=await campaign(a,u.user.id,payload(new Date(),'marketing'));await a.maintenance();const consent=(await a.store.all('processing_consent','KZ'))[0];await a.store.put({...consent,marketing:false,version:consent.version+1});const before=sends;await a.deliverOutbox();assert.equal(sends,before);assert.equal((await a.store.all('outbox','KZ')).find(r=>r.campaign_id===marketingCampaign.id).status,'suppressed');
}));
test('marketing frequency, quiet hours and deadline are applied at delivery, and cancellation does not claim to recall accepted messages',()=>fixture(async a=>{
 const u=await reg(a,'865');await marketing(a,u);await token(a,u);const now=new Date();for(let i=0;i<3;i++)await campaign(a,u.user.id,payload(now,'marketing'));await a.maintenance(now);
 let sends=0;a.providers.push={send:async()=>({provider_message_id:'isolated-'+(++sends)})};await a.deliverOutbox(now);assert.equal(sends,1);assert.equal((await a.store.all('outbox','KZ')).filter(r=>r.status==='retry').length,2);
 const user=await a.store.get(u.user.id),hour=now.getUTCHours();await a.store.put({...user,notification_preferences:{...user.notification_preferences,quiet_hours:{start:String((hour+23)%24).padStart(2,'0')+':00',end:String((hour+1)%24).padStart(2,'0')+':00',time_zone:'UTC'}}});
 const quiet=await campaign(a,u.user.id,payload(now));await a.maintenance(now);await a.deliverOutbox(now);assert.equal(sends,1);assert.equal((await a.store.all('outbox','KZ')).find(o=>o.campaign_id===quiet.id).status,'retry');
 await a.maintenance(new Date(now.getTime()+2*3600000));await a.deliverOutbox(new Date(now.getTime()+2*3600000));assert.equal(sends,1);assert.equal((await a.store.all('outbox','KZ')).find(o=>o.campaign_id===quiet.id).status,'expired');
}));
test('revoked device session cannot receive queued push and registering a current device resumes waiting work',()=>fixture(async a=>{
 const u=await reg(a,'866');await token(a,u);const c=await campaign(a,u.user.id,payload());await a.maintenance();await call(a,u,'POST','/auth/logout');let sends=0;a.providers.push={send:async()=>({provider_message_id:'isolated-'+(++sends)})};await a.deliverOutbox();assert.equal(sends,0);assert.equal((await a.store.all('outbox','KZ')).find(o=>o.campaign_id===c.id).status,'waiting_token');
 const signed=await a.handle('POST','/auth/login',{country:'KZ',phone:u.user.phone,password},undefined,undefined,{},'push-relogin');await token(a,signed);await a.deliverOutbox();assert.equal(sends,1);assert.equal((await a.store.all('push_token','KZ')).filter(t=>t.status==='active').length,1);
}));
test('audience batches retain a cutoff and cursor, and retry cannot multiply recipients',async()=>{
 const s=new Store('memory://');await s.initialize();try{const now=new Date(),owner=randomUUID();for(let i=0;i<120;i++){const id=randomUUID();await s.put({...row('user',id,{status:'active',locale:'ru',roles:['customer'],created_at:new Date(now.getTime()-1000).toISOString()}),id});}
 const c=row('push_campaign',owner,{status:'scheduled',payload:payload(now)});await s.put(c);await queuePushCampaigns(s,now);assert.equal((await s.all('outbox')).length,100);
 await s.put({...row('user',owner,{status:'active',locale:'ru',roles:['customer'],created_at:new Date(now.getTime()+1000).toISOString()})});await queuePushCampaigns(s,now);await queuePushCampaigns(s,now);assert.equal((await s.all('outbox')).length,120);assert.equal((await s.all('notification')).length,120);
 }finally{await s.close();}
});
test('weekly marketing cap and cancellation between devices prevent further claims; expired leases are recovered',()=>fixture(async a=>{
 const {cancelPushCampaign}=require('../dist/push-campaigns');const u=await reg(a,'867');await marketing(a,u);await token(a,u,'isolated-device-a');await token(a,u,'isolated-device-b');const now=new Date();
 for(let days=2;days<=4;days++)await a.store.put(row('outbox',u.user.id,{recipient_id:u.user.id,campaign_type:'marketing',status:'sent',sent_at:new Date(now.getTime()-days*86400000).toISOString()}));
 const capped=await campaign(a,u.user.id,payload(now,'marketing'));await a.maintenance(now);let sends=0;a.providers.push={send:async()=>({provider_message_id:'isolated-'+(++sends)})};await a.deliverOutbox(now);assert.equal(sends,0);assert.equal((await a.store.all('outbox')).find(o=>o.campaign_id===capped.id).status,'retry');
 const c=await campaign(a,u.user.id,payload(now));await a.maintenance(now);a.providers.push={send:async()=>{sends++;await cancelPushCampaign(a.store,await a.store.get(c.id));return {provider_message_id:'isolated-accepted'};}};await a.deliverOutbox(now);assert.equal(sends,1);let o=(await a.store.all('outbox')).find(o=>o.campaign_id===c.id);assert.equal(o.status,'canceled');assert.equal(o.accepted_tokens.length,1);
 const recovered=await campaign(a,u.user.id,payload(now));await a.maintenance(now);o=(await a.store.all('outbox')).find(o=>o.campaign_id===recovered.id);await a.store.put({...o,status:'processing',lease_id:randomUUID(),lease_expires_at:new Date(now.getTime()-1000).toISOString(),accepted_tokens:[]});a.providers.push={send:async()=>({provider_message_id:'isolated-recovered-'+(++sends)})};await a.deliverOutbox(now);assert.equal((await a.store.get(o.id)).status,'sent');assert.equal(sends,3);
}));
test('FCM permanently invalid token is revoked without blocking other devices',()=>fixture(async a=>{
 const {InvalidPushToken}=require('../dist/firebase-push');
 const u=await reg(a,'898');await marketing(a,u);await token(a,u,'isolated-invalid-token');await token(a,u,'isolated-valid-token');
 const now=new Date(),c=await campaign(a,u.user.id,payload(now));await a.maintenance(now);
 const sent=[];a.providers.push={send:async(value)=>{if(value==='isolated-invalid-token')throw new InvalidPushToken();sent.push(value);return {provider_message_id:randomUUID()};}};
 await a.deliverOutbox(now);
 assert.deepEqual(sent,['isolated-valid-token']);
 const tokens=await a.store.all('push_token','KZ');assert.equal(tokens.find(t=>t.status==='revoked').token,'');assert.equal(tokens.filter(t=>t.status==='active').length,1);
 assert.equal((await a.store.all('outbox','KZ')).find(r=>r.campaign_id===c.id).status,'sent');
}));
test('all invalid FCM tokens leave the event waiting for a new device instead of falsely sent',()=>fixture(async a=>{
 const {InvalidPushToken}=require('../dist/firebase-push');
 const u=await reg(a,'899');await marketing(a,u);await token(a,u,'isolated-only-invalid-token');
 const now=new Date(),c=await campaign(a,u.user.id,payload(now));await a.maintenance(now);
 a.providers.push={send:async()=>{throw new InvalidPushToken();}};
 assert.equal((await a.deliverOutbox(now)).sent,0);
 assert.equal((await a.store.all('outbox','KZ')).find(r=>r.campaign_id===c.id).status,'waiting_token');
 await token(a,u,'isolated-replacement-token');a.providers.push={send:async()=>({provider_message_id:randomUUID()})};
 assert.equal((await a.deliverOutbox(now)).sent,1);
}));
test('explicit personal push test bypasses quiet hours without changing preferences or reaching another account',()=>fixture(async a=>{
 const u=await reg(a,'887'),other=await reg(a,'886');await token(a,u,'isolated-own-test-token');await token(a,other,'isolated-other-test-token');
 const user=await a.store.get(u.user.id);await a.store.put({...user,notification_preferences:{service:false,chat:false,marketing:false,quiet_hours:{start:'00:00',end:'23:59',time_zone:'UTC'}},version:user.version+1});
 const sent=[];a.providers.push={send:async(value,event)=>{sent.push({value,event});return{provider_message_id:randomUUID()};}};
 const key=randomUUID(),send=()=>a.handle('POST','/me/push-test',{},'Bearer '+u.access_token,key,{},'isolated-push-test');assert.equal((await send()).queued,true);await send();
 assert.equal((await a.deliverOutbox()).sent,1);assert.equal(sent.length,1);assert.equal(sent[0].value,'isolated-own-test-token');assert.equal(sent[0].event.body,'Проверка push-уведомлений JOBA');assert.equal((await a.store.get(u.user.id)).notification_preferences.service,false);
}));
