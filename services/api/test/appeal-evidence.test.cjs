const {test}=require('node:test');const assert=require('node:assert/strict');const {randomUUID}=require('node:crypto');
const {Marketplace}=require('../dist/marketplace');const {Store}=require('../dist/store');
test('appeal evidence is owned clean chat content committed with the current subject decision and idempotent retry',async()=>{
 const api=new Marketplace(new Store('memory://'));await api.initialize();
 try{
  const session=await api.handle('POST','/auth/register',{country:'KZ',phone:'+77000000095',password:'An isolated appeal password!'},undefined,undefined,{},'appeal-evidence');
  const actor=session.user.id,other=randomUUID(),now=new Date().toISOString();
  const put=(kind,data={},owner=actor)=>api.store.put({id:randomUUID(),kind,owner,country:'KZ',version:1,created_at:now,...data});
  const incident=await put('case',{subject_user_id:actor,status:'resolved',decision:'content_removed'});
  const clean=await put('upload',{purpose:'chat',status:'clean'}),unclean=await put('upload',{purpose:'chat',status:'pending'}),identity=await put('upload',{purpose:'identity',status:'clean'}),foreign=await put('upload',{purpose:'chat',status:'clean'},other);
  const body={expected_version:1,reason:'Прошу пересмотреть решение по приложенным материалам.',upload_ids:[clean.id]};
  const send=(body,key=randomUUID())=>api.handle('POST','/cases/'+incident.id+'/appeals',body,'Bearer '+session.access_token,key);
  await assert.rejects(()=>send({...body,expected_version:0}),e=>e.getResponse().error.code==='STATE_CONFLICT');
  for(const id of [unclean.id,identity.id])await assert.rejects(()=>send({...body,upload_ids:[id]}),e=>e.getResponse().error.code==='UNSAFE_UPLOAD');
  await assert.rejects(()=>send({...body,upload_ids:[foreign.id]}),e=>e.getStatus()===404);
  assert.equal((await api.store.get(incident.id)).status,'resolved');
  const key=randomUUID(),result=await send(body,key);assert.equal(result.status,'appealed');assert.deepEqual(result.appeal_upload_ids,[clean.id]);assert.ok(Date.parse(result.appeal_submitted_at));
  assert.equal((await send(body,key)).version,result.version);
  await assert.rejects(()=>send(body),e=>e.getResponse().error.code==='STATE_CONFLICT');
 }finally{await api.store.db.close();}
});
