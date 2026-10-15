const {test}=require('node:test');
const assert=require('node:assert/strict');
const {randomUUID}=require('node:crypto');
const {Store}=require('../dist/store');
const {Marketplace}=require('../dist/marketplace');

test('support composition atomically links participant order and clean attachments to first message, with scope and idempotency',async()=>{
 const api=new Marketplace(new Store('memory://'));await api.initialize();
 try{
  const session=await api.handle('POST','/auth/register',{country:'KZ',phone:'+77000000093',password:'An isolated support password!'},undefined,undefined,{},'support-compose');
  const actor=session.user.id,other=randomUUID(),now=new Date().toISOString();
  const put=(kind,data={},owner=actor,country='KZ')=>api.store.put({id:randomUUID(),kind,owner,country,version:1,created_at:now,...data});
  const create=(body,key=randomUUID())=>api.handle('POST','/support/threads',body,'Bearer '+session.access_token,key);
  const order=await put('order',{title:'Установка двери',status:'completed'});
  const upload=await put('upload',{purpose:'chat',status:'clean'});
  const body={subject:'Заказы и договорённости',topic:'orders',order_id:order.id,text:'Как запросить доработку результата?',upload_ids:[upload.id]};
  const key=randomUUID(),thread=await create(body,key);
  assert.equal(thread.order_id,order.id);assert.equal(thread.topic,'orders');assert.deepEqual(thread.members,[actor]);
  assert.equal((await create(body,key)).id,thread.id);
  const messages=(await api.store.all('support_message','KZ')).filter(m=>m.thread_id===thread.id);
  assert.equal(messages.length,1);assert.equal(messages[0].text,body.text);assert.deepEqual(messages[0].upload_ids,[upload.id]);
  const assigned=await put('order',{executor_id:actor,status:'in_progress'},other);
  assert.equal((await create({...body,order_id:assigned.id})).order_id,assigned.id);
  const foreign=await put('order',{},other),overseas=await put('order',{},actor,'RS');
  for(const id of [foreign.id,overseas.id])await assert.rejects(()=>create({...body,order_id:id}),e=>e.getResponse().error.code==='NOT_FOUND');
  const unclean=await put('upload',{purpose:'chat',status:'pending'});
  const identity=await put('upload',{purpose:'identity',status:'clean'});
  for(const id of [unclean.id,identity.id])await assert.rejects(()=>create({...body,upload_ids:[id]}),e=>e.getResponse().error.code==='UNSAFE_UPLOAD');
  const before=(await api.store.all('support','KZ')).length;
  await assert.rejects(()=>create({...body,text:'  '}),e=>e.getResponse().error.code==='VALIDATION_ERROR');
  await assert.rejects(()=>create({...body,topic:'invented'}),e=>e.getResponse().error.code==='VALIDATION_ERROR');
  await assert.rejects(()=>create({...body,text:undefined}),e=>e.getResponse().error.code==='VALIDATION_ERROR');
  assert.equal((await api.store.all('support','KZ')).length,before);
  assert.equal((await create({subject:'Старый клиент без первого сообщения'})).status,'new');
 }finally{await api.store.db.close();}
});
