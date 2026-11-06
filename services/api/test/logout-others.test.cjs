const {test}=require('node:test');const assert=require('node:assert/strict');const {randomUUID}=require('node:crypto');
const {Store}=require('../dist/store'),{Marketplace}=require('../dist/marketplace');
test('logout others requires reauthentication, revokes other access and refresh tokens, and preserves current and unrelated users',async()=>{
 const a=new Marketplace(new Store('memory://'));await a.initialize();try{
 const password='Isolated session password!';
 const register=n=>a.handle('POST','/auth/register',{country:'KZ',phone:'+77000000'+n,password},undefined,randomUUID(),{},'session-register-'+n);
 const u=await register('631'),other=await register('632');
 const remote=await a.handle('POST','/auth/login',{country:'KZ',phone:u.user.phone,password},undefined,undefined,{},'session-login');
 const call=(user,m,p,b={})=>a.handle(m,p,b,'Bearer '+user.access_token,randomUUID(),{},'session-action');
 assert.equal((await call(u,'GET','/me/sessions')).items.length,2);
 await assert.rejects(()=>call(u,'POST','/auth/logout-others',{current_password:'Incorrect password'}),e=>e.getStatus()===401);
 assert.equal((await call(remote,'GET','/me'))['id'],u.user.id);
 const result=await call(u,'POST','/auth/logout-others',{current_password:password});assert.equal(result.current_session_preserved,true);
 const sessions=(await call(u,'GET','/me/sessions')).items;assert.equal(sessions.length,1);assert.equal(sessions[0].current,true);
 await assert.rejects(()=>call(remote,'GET','/me'),e=>e.getStatus()===401);
 await assert.rejects(()=>a.handle('POST','/auth/refresh',{country:'KZ',refresh_token:remote.refresh_token}),e=>e.getStatus()===401);
 assert.equal((await call(other,'GET','/me')).id,other.user.id);
 assert.equal((await call(u,'GET','/me')).id,u.user.id);
 assert.equal((await a.store.all('security_event','KZ')).filter(x=>x.owner===u.user.id&&x.event==='sessions.others_revoked').length,1);
 }finally{await a.store.close();}
});
