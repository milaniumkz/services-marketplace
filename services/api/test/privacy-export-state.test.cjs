const {test}=require('node:test');const assert=require('node:assert/strict');const {randomUUID}=require('node:crypto');
const {Marketplace}=require('../dist/marketplace');const {Store}=require('../dist/store');
test('export availability is derived from an owned clean unexpired export file and bad reauthentication preserves the account',async()=>{
 const api=new Marketplace(new Store('memory://'));await api.initialize();
 try{
  const session=await api.handle('POST','/auth/register',{country:'KZ',phone:'+77000000096',password:'An isolated privacy password!'},undefined,undefined,{},'privacy-export-state');
  const actor=session.user.id,other=randomUUID(),now=new Date().toISOString(),future=new Date(Date.now()+86400000).toISOString();
  const put=(kind,data={},owner=actor,country='KZ')=>api.store.put({id:randomUUID(),kind,owner,country,version:1,created_at:now,...data});
  const call=(method,path,body={})=>api.handle(method,path,body,'Bearer '+session.access_token,randomUUID());
  await assert.rejects(()=>call('POST','/me/privacy-requests',{type:'export',current_password:'wrong password'}),e=>e.getStatus()===401&&e.getResponse().error.code==='REAUTH_REQUIRED');
  assert.equal((await call('GET','/me')).id,actor);assert.equal((await api.store.all('privacy','KZ')).length,0);
  const job=await put('privacy',{type:'export',status:'completed'});
  const show=()=>call('GET','/me/privacy-requests/'+job.id);
  assert.equal((await show()).download_available,false);
  const clean=await put('upload',{purpose:'export',status:'clean',expires_at:future});
  await api.store.put({...job,upload_id:clean.id});
  assert.equal((await show()).download_available,true);assert.equal((await show()).download_expires_at,future);
  await api.store.put({...clean,expires_at:'2000-01-01T00:00:00Z'});assert.equal((await show()).download_available,false);
  for(const [owner,country,purpose] of [[other,'KZ','export'],[actor,'KG','export'],[actor,'KZ','identity']]){
   const file=await put('upload',{purpose,status:'clean',expires_at:future},owner,country);await api.store.put({...job,upload_id:file.id});
   const result=await show();assert.equal(result.download_available,false);assert.equal(result.download_expires_at,null);
  }
  const foreign=await put('privacy',{type:'export',status:'completed',upload_id:clean.id},other);
  await assert.rejects(()=>call('GET','/me/privacy-requests/'+foreign.id),e=>e.getStatus()===404);
 }finally{await api.store.close();}
});
