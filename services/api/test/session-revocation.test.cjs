const {test}=require('node:test');
const assert=require('node:assert/strict');
const {randomUUID}=require('node:crypto');
const {Marketplace}=require('../dist/marketplace');
const {Store}=require('../dist/store');
test('session list excludes expired refresh families and revocation is owned regional input-checked and device-specific',async()=>{
 const api=new Marketplace(new Store('memory://'));await api.initialize();
 const password='Isolated session revocation password!';
 const call=(u,m,p,b={})=>api.handle(m,p,b,u?'Bearer '+u.access_token:undefined,randomUUID(),{},'session-test');
 try{
  const first=await call(null,'POST','/auth/register',{country:'KZ',phone:'+77000000771',password});
  const other=await call(null,'POST','/auth/register',{country:'KZ',phone:'+77000000772',password});
  const second=await call(null,'POST','/auth/login',{country:'KZ',phone:'+77000000771',password});
  const sessions=(await call(first,'GET','/me/sessions')).items;assert.equal(sessions.length,2);
  const remote=sessions.find(r=>!r.current),current=sessions.find(r=>r.current);
  await assert.rejects(()=>call(other,'DELETE','/me/sessions/'+remote.family),e=>e.getStatus()===404);
  await assert.rejects(()=>call(first,'DELETE','/me/sessions/not-a-uuid'),e=>e.getStatus()===400);
  assert.equal((await call(first,'DELETE','/me/sessions/'+remote.family)).revoked,true);
  await assert.rejects(()=>call(second,'GET','/me'),e=>e.getStatus()===401);
  assert.equal((await call(first,'GET','/me')).id,first.user.id);assert.equal((await call(other,'GET','/me')).id,other.user.id);
  assert.equal((await call(first,'GET','/me/sessions')).items.length,1);
  assert.ok((await api.store.all('security_event','KZ')).some(r=>r.event==='session.revoked'&&r.session_family===remote.family));
  await api.store.db.query("UPDATE tokens SET expires_at=now()-interval '1 minute' WHERE family=$1 AND kind='refresh'",[current.family]);
  assert.deepEqual((await call(first,'GET','/me/sessions')).items,[]);
 }finally{await api.store.close();}
});
