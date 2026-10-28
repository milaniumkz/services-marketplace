const {test}=require('node:test'),assert=require('node:assert/strict'),{randomUUID,createHash}=require('node:crypto');
const{Marketplace}=require('../dist/marketplace'),{Store}=require('../dist/store');
const refresh=(a,token,id)=>a.handle('POST','/auth/refresh',{refresh_token:token,...id?{request_id:id}:{}},undefined,undefined,{},'isolated-refresh');
const register=a=>a.handle('POST','/auth/register',{country:'KZ',phone:'+77000000881',password:'Isolated session password'},undefined,undefined,{},'isolated-login');
test('lost refresh response is recoverable with the same persisted request ID, encrypted at rest and forbidden after logout',async()=>{
 const a=new Marketplace(new Store('memory://'));await a.initialize();
 try{
  const first=await register(a),id=randomUUID(),rotated=await refresh(a,first.refresh_token,id);
  assert.deepEqual(await refresh(a,first.refresh_token,id),rotated);
  const receipts=(await a.store.db.query('SELECT * FROM refresh_receipts')).rows;assert.equal(receipts.length,1);assert.equal(JSON.stringify(receipts).includes(rotated.refresh_token),false);assert.equal(JSON.stringify(receipts).includes(rotated.access_token),false);
  assert.equal((await a.handle('GET','/me',{},'Bearer '+rotated.access_token)).id,first.user.id);
  await a.handle('POST','/auth/logout',{},'Bearer '+rotated.access_token,randomUUID());
  await assert.rejects(()=>refresh(a,first.refresh_token,id),e=>e.getStatus()===401);
  await assert.rejects(()=>a.handle('GET','/me',{},'Bearer '+rotated.access_token),e=>e.getStatus()===401);
 }finally{await a.store.close();}
});
test('an unrelated replay still durably revokes the family and a further rotation removes the old retry receipt',async()=>{
 const a=new Marketplace(new Store('memory://'));await a.initialize();
 try{
  const first=await register(a),id=randomUUID(),second=await refresh(a,first.refresh_token,id),third=await refresh(a,second.refresh_token,randomUUID());
  assert.equal((await a.store.db.query('SELECT count(*)::int AS n FROM refresh_receipts')).rows[0].n,1);
  await assert.rejects(()=>refresh(a,first.refresh_token,randomUUID()),e=>e.getResponse().error.code==='REFRESH_REPLAY');
  await assert.rejects(()=>refresh(a,third.refresh_token,randomUUID()),e=>e.getStatus()===401);
 }finally{await a.store.close();}
});
