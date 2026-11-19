const {test}=require('node:test');
const assert=require('node:assert/strict');
const {randomUUID}=require('node:crypto');
const {Store}=require('../dist/store');
const {Marketplace}=require('../dist/marketplace');
test('account management blocks sessions, restores login and queues subject-owned deletion with audit',async()=>{
 const api=new Marketplace(new Store('memory://'));await api.initialize();
 try{
  const password='Isolated account password';
  const register=phone=>api.handle('POST','/auth/register',{country:'KZ',phone,password},undefined,randomUUID(),{},phone);
  const owner=await register('+77000000681'),user=await register('+77000000682');
  await api.store.put({...await api.store.get(owner.user.id),staff_permissions:['platform_owner','administrator'],staff_auth_mode:'password'});
  const staff=await api.handle('POST','/auth/staff-login',{country:'KZ',phone:owner.user.phone,password},undefined,undefined,{},'account-staff');
  const call=(action,body)=>api.handle('POST','/admin/users/'+user.user.id+'/'+action,body,'Bearer '+staff.access_token,randomUUID(),{},'account-admin');
  const current=()=>api.store.get(user.user.id);
  const body=async()=>({expected_version:(await current()).version});
  await assert.rejects(()=>call('block',{expected_version:0,reason:'Неверная ревизия аккаунта'}),e=>e.getStatus()===409);
  await call('block',await body());assert.equal((await current()).status,'blocked');
  const directory=query=>api.handle('GET','/admin/users',{},'Bearer '+staff.access_token,undefined,query);
  const search=()=>api.handle('GET','/admin/search',{},'Bearer '+staff.access_token,undefined,{q:user.user.id,kind:'user'});
  assert.ok((await directory({q:user.user.id})).items.some(r=>r.id===user.user.id));assert.equal((await search()).items[0].status,'blocked');
  assert.equal((await api.store.db.query('SELECT count(*)::int n FROM tokens WHERE user_id=$1 AND NOT revoked',[user.user.id])).rows[0].n,0);
  await assert.rejects(()=>api.handle('POST','/auth/login',{country:'KZ',phone:user.user.phone,password},undefined,undefined,{},'blocked-login'),e=>e.getResponse().error.code==='ACCOUNT_BLOCKED');
  await call('unblock',await body());assert.equal((await current()).status,'active');
  assert.ok((await api.handle('POST','/auth/login',{country:'KZ',phone:user.user.phone,password},undefined,undefined,{},'unblocked-login')).access_token);
  const result=await call('delete',await body());assert.equal(result.status,'deleted');assert.equal((await current()).status,'deleted');
  await assert.rejects(()=>api.handle('GET','/me',{},'Bearer '+user.access_token),e=>e.getStatus()===401);
  await assert.rejects(()=>api.handle('POST','/auth/login',{country:'KZ',phone:user.user.phone,password},undefined,undefined,{},'deleted-login'),e=>e.getStatus()===401);
  assert.equal((await directory({q:user.user.id})).items.length,0);assert.equal((await directory({status:'deleted'})).items.length,0);assert.equal((await search()).items.length,0);
  await assert.rejects(()=>api.handle('GET','/admin/users/'+user.user.id,{},'Bearer '+staff.access_token),e=>e.getStatus()===404);
  const job=await api.store.get(result.deletion_request_id);assert.equal(job.owner,user.user.id);assert.equal(job.type,'delete');assert.equal(job.requested_by,owner.user.id);
  await assert.rejects(async()=>call('unblock',{expected_version:(await current()).version,reason:'Попытка обойти запрос удаления'}),e=>e.getStatus()===409);
  assert.equal((await api.store.all('audit','KZ')).filter(r=>r.target_id===user.user.id).length,3);
  const metrics=()=>api.handle('GET','/admin/server-metrics',{},'Bearer '+staff.access_token);
  assert.equal((await metrics()).available,false);
  await api.store.put({...await api.store.get(owner.user.id),staff_permissions:['administrator']});
  await assert.rejects(metrics,e=>e.getStatus()===403);

 }finally{await api.store.close();}
});
