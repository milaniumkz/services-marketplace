const {test}=require('node:test');
const assert=require('node:assert/strict');
const {randomUUID}=require('node:crypto');
const {Marketplace}=require('../dist/marketplace');
const {Store}=require('../dist/store');
const {exportSnapshot}=require('../dist/privacy-export');
test('free safety reports require a visible regional target and freeze its revision',async()=>{
 const api=new Marketplace(new Store('memory://'));await api.initialize();
 const call=(u,m,p,b={})=>api.handle(m,p,b,'Bearer '+u.access_token,randomUUID());
 const register=phone=>api.handle('POST','/auth/register',{country:'KZ',phone,password:'Isolated safety test!'},undefined,undefined,{},phone);
 try{
  const owner=await register('+77000000291'),other=await register('+77000000292'),outsider=await register('+77000000293');
  const put=(kind,account,data,country='KZ')=>api.store.put({id:randomUUID(),kind,country,owner:account,version:1,created_at:new Date().toISOString(),...data});
  const report=(session,target,type=target.kind)=>call(session,'POST','/cases',{target_type:type,target_id:target.id,reason_code:'other',description:'Описание конкретной проблемы для проверки.'});
  const order=await put('order',owner.user.id,{status:'draft',revision:4});
  await assert.rejects(()=>report(other,order),e=>e.getStatus()===404);
  const own=await report(owner,order);assert.equal(own.target_version,1);assert.equal(own.target_revision,4);assert.equal(own.target_snapshot,undefined);assert.equal((await api.store.get(own.id)).target_content_hash.length,64);
  await assert.rejects(()=>report(owner,order),e=>e.getResponse().error.code==='STATE_CONFLICT');
  await assert.rejects(()=>report(owner,order,'contractor'),e=>e.getStatus()===404);
  const foreign=await put('order',owner.user.id,{status:'open'},'RU');await assert.rejects(()=>report(owner,foreign),e=>e.getStatus()===404);
  const conversation=await put('conversation',owner.user.id,{members:[owner.user.id,other.user.id],status:'closed'});
  const message=await put('message',other.user.id,{thread_id:conversation.id,text:'Сообщение из завершённого чата'});
  const file=await put('upload',owner.user.id,{purpose:'chat',mime:'image/png',size:10,status:'clean'});
  const unsafe=await put('upload',owner.user.id,{purpose:'chat',mime:'image/png',size:10,status:'processing'});
  await assert.rejects(()=>call(owner,'POST','/cases',{target_type:'message',target_id:message.id,reason_code:'content',description:'Описание конкретной проблемы для проверки.',upload_ids:[unsafe.id]}),e=>e.getResponse().error.code==='UNSAFE_UPLOAD');
  const complaint=await call(owner,'POST','/cases',{target_type:'message',target_id:message.id,reason_code:'content',description:'Описание конкретной проблемы для проверки.',upload_ids:[file.id]});
  assert.equal(complaint.reporter_private,true);
  await assert.rejects(()=>call(other,'GET','/cases/'+complaint.id),e=>e.getStatus()===404);
  await assert.rejects(()=>call(other,'GET','/cases/'+complaint.id+'/messages'),e=>e.getStatus()===404);
  await assert.rejects(()=>call(other,'GET','/uploads/'+file.id+'/metadata'),e=>e.getStatus()===404);
  assert.ok(!(await call(other,'GET','/me/cases')).items.some(c=>c.id===complaint.id));
  assert.ok(!(await exportSnapshot(api.store,other.user.id,'KZ')).data.case.some(c=>c.id===complaint.id));
  await assert.rejects(()=>report(outsider,message),e=>e.getStatus()===404);
  const participant=await put('order',owner.user.id,{status:'completed',executor_id:other.user.id,revision:1});await report(other,participant);
  const user=await api.store.get(other.user.id);await report(owner,user);await assert.rejects(()=>report(outsider,user),e=>e.getStatus()===404);
  await assert.rejects(()=>report(owner,message,'privacy'),e=>e.getStatus()===400);
  assert.deepEqual(await call(owner,'GET','/me/cases/overview'),{open:3,resolved:0});
  assert.deepEqual(await call(other,'GET','/me/cases/overview'),{open:1,resolved:0});
  await api.store.put({...complaint,status:'resolved',version:complaint.version+1});
  assert.deepEqual(await call(owner,'GET','/me/cases/overview'),{open:2,resolved:1});
  const resolved=await api.handle('GET','/me/cases',{},'Bearer '+owner.access_token,undefined,{bucket:'resolved',limit:1});assert.equal(resolved.items.length,1);assert.equal(resolved.items[0].id,complaint.id);
  const otherResolved=await api.handle('GET','/me/cases',{},'Bearer '+other.access_token,undefined,{bucket:'resolved'});assert.equal(otherResolved.items.length,0);
  await assert.rejects(()=>api.handle('GET','/me/cases',{},'Bearer '+owner.access_token,undefined,{bucket:'invalid'}),e=>e.getStatus()===400);

 }finally{await api.store.close();}
});
