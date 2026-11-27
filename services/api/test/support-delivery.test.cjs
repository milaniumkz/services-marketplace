const {test}=require('node:test'),assert=require('node:assert/strict'),{randomUUID,randomBytes}=require('node:crypto');
const {Marketplace}=require('../dist/marketplace'),{Store}=require('../dist/store'),{totp}=require('../dist/totp');
test('support arrives immediately across owner countries, reads before assignment, replies and notifies assigned staff, sorts by activity with stable cursor',async()=>{
 const api=new Marketplace(new Store('memory://'));await api.initialize();
 try{
  const password='Support delivery isolated password!';
  const register=(phone,country='KZ')=>api.handle('POST','/auth/register',{phone,country,password},undefined,randomUUID());
  const user=await register('+77000000861'),by=await register('+375291234586','BY');
  async function staff(phone,permissions){const u=await register(phone),secret=randomBytes(20).toString('hex');await api.store.put({...await api.store.get(u.user.id),staff_permissions:permissions,totp_secret:secret});return api.handle('POST','/auth/staff-login',{phone,country:'KZ',password,mfa_code:totp(secret)},undefined,randomUUID());}
  const owner=await staff('+77000000862',['platform_owner']),agent=await staff('+77000000863',['support']),other=await staff('+77000000864',['support']);
  const call=(actor,m,p,b={},q={})=>api.handle(m,p,b,'Bearer '+actor.access_token,randomUUID(),q);
  const attachment={id:randomUUID(),kind:'upload',owner:user.user.id,country:'KZ',version:1,created_at:new Date().toISOString(),purpose:'chat',status:'clean',mime:'image/png',size:100};await api.store.put(attachment);
  const first=await call(user,'POST','/support/threads',{subject:'Первое обращение клиента',text:'Проверка доставки обращения',upload_ids:[attachment.id]});
  const second=await call(by,'POST','/support/threads',{subject:'Обращение из Беларуси',text:'Проверка другой страны'});
  const list=await call(owner,'GET','/admin/support-threads');assert.equal(list.items.length,2);assert.ok(list.items.some(t=>t.id===second.id));
  assert.equal((await call(agent,'GET','/admin/support-threads')).items.length,1);
  assert.equal((await call(agent,'GET',`/admin/support-threads/${first.id}/messages`)).items[0].text,'Проверка доставки обращения');
  assert.ok((await call(agent,'GET',`/uploads/${attachment.id}/download-url`,{}, {reason:'Изолированный просмотр вложения поддержки'})).url.startsWith('/api/v1/private-files/'));
  assert.ok((await api.store.all('audit','KZ')).some(r=>r.action==='support.attachment_read'&&r.target_id===attachment.id));
  await assert.rejects(()=>call(agent,'GET',`/admin/support-threads/${second.id}/messages`),e=>[403,404].includes(e.getStatus()));
  await assert.rejects(()=>call(other,'POST',`/admin/support-threads/${first.id}/messages`,{text:'Нельзя без назначения',client_message_id:randomUUID()}),e=>e.getStatus()===403);
  let t=await api.store.get(first.id);await call(agent,'POST',`/admin/support-threads/${first.id}/commands`,{command:'assign',expected_version:t.version});
  const reply={text:'Ответ поддержки получен',client_message_id:randomUUID()};await call(agent,'POST',`/admin/support-threads/${first.id}/messages`,reply);
  assert.ok((await call(user,'GET',`/support/threads/${first.id}/messages`)).items.some(m=>m.text===reply.text));
  await call(user,'POST',`/support/threads/${first.id}/messages`,{text:'Новое сообщение для сотрудника',client_message_id:randomUUID()});
  assert.equal((await call(owner,'GET','/admin/support-threads')).items[0].id,first.id);
  const notifications=await api.store.all('notification','KZ');assert.ok(notifications.some(n=>n.owner===agent.user.id&&JSON.stringify(n).includes(first.id)));
  assert.equal((await call(other,'GET',`/admin/support-threads/${first.id}/messages`)).items.length,3);
  let cursor,ids=[];do{const page=await call(owner,'GET','/admin/support-threads',{}, {limit:1,...cursor?{cursor}:{}});ids.push(...page.items.map(r=>r.id));cursor=page.meta.next_cursor;}while(cursor);
  assert.equal(ids.length,2);assert.equal(new Set(ids).size,2);
  assert.deepEqual((await call(owner,'GET','/admin/support-threads',{}, {q:'Беларуси'})).items.map(r=>r.id),[second.id]);
  assert.equal((await call(user,'GET','/me/support-threads')).items.length,1);
 }finally{await api.store.close();}
});
