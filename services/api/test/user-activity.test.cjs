const{test}=require('node:test'),assert=require('node:assert/strict'),{randomUUID}=require('node:crypto');
const{Marketplace}=require('../dist/marketplace'),{Store}=require('../dist/store');
test('user activity records screens and successful commands without field contents; staff sees ordered scoped events without manual reason',async()=>{
 const a=new Marketplace(new Store('memory://'));await a.initialize();
 try{
  const reg=phone=>a.handle('POST','/auth/register',{country:'KZ',phone,password:'Activity isolated password'},undefined,undefined,{},phone);
  const user=await reg('+77000000941'),owner=await reg('+77000000942');
  await a.store.put({...await a.store.get(owner.user.id),staff_permissions:['administrator'],staff_auth_mode:'password'});
  const staff=await a.handle('POST','/auth/staff-login',{country:'KZ',phone:owner.user.phone,password:'Activity isolated password'});
  const call=(method,path,body={},query={},token=user.access_token,key=randomUUID())=>a.handle(method,path,body,'Bearer '+token,key,query,'192.0.2.23');
  const key=randomUUID();await call('POST','/me/activity',{screen:'home',password:'never-record-this'}, {},user.access_token,key);
  await call('POST','/me/activity',{screen:'home',password:'never-record-this'}, {},user.access_token,key);
  await assert.rejects(()=>call('POST','/me/activity',{screen:'password=secret'}),e=>e.getStatus()===400);
  await call('PATCH','/me',{display_name:'Имя для проверки',expected_version:(await a.store.get(user.user.id)).version});
  const events=(await a.store.all('security_event','KZ')).filter(e=>e.owner===user.user.id);
  assert.equal(events.filter(e=>e.event==='app.screen_opened').length,1);
  assert.ok(events.some(e=>e.event==='app.action_completed'&&e.action_path==='/me'&&e.method==='PATCH'));
  assert.equal(JSON.stringify(events).includes('never-record-this'),false);assert.equal(JSON.stringify(events).includes('Имя для проверки'),false);
  const page=await call('GET','/admin/users/'+user.user.id+'/security-events',{}, {include_ip:'true',limit:1},staff.access_token);
  assert.equal(page.items[0].event,'app.action_completed');assert.equal(page.items[0].ip,'192.0.2.23');assert.equal(page.items[0].session_family,undefined);
  assert.ok(page.meta.next_cursor);
  const next=await call('GET','/admin/users/'+user.user.id+'/security-events',{}, {include_ip:'true',limit:1,cursor:page.meta.next_cursor},staff.access_token);
  assert.equal(next.items[0].event,'app.screen_opened');
 }finally{await a.store.close();}
});
