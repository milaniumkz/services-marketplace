const {test}=require('node:test');
const assert=require('node:assert/strict');
const {randomUUID}=require('node:crypto');
const {Store}=require('../dist/store');
const {Marketplace}=require('../dist/marketplace');
test('existing work reviews stay free, sealed feedback stays private and an open case blocks automatic publication',async()=>{
 const api=new Marketplace(new Store('memory://'));await api.initialize();
 try{
  const register=(phone,name)=>api.handle('POST','/auth/register',{country:'KZ',phone,display_name:name,password:'A long isolated password!'},undefined,undefined,{},phone);
  const customer=await register('+77000000092','Заказчик'),executor=await register('+77000000093','Исполнитель'),stranger=await register('+77000000094','Другой');
  const call=(user,method,path,body={})=>api.handle(method,path,body,'Bearer '+user.access_token,randomUUID(),{},'review-free-test');
  const now=new Date().toISOString(),id=randomUUID(),caseId=randomUUID();
  await api.store.put({id,kind:'order',owner:customer.user.id,country:'KZ',version:1,created_at:now,completed_at:now,status:'completed',executor_id:executor.user.id,title:'Завершённый заказ',description:'Достаточно длинное описание завершённого заказа.'});
  await api.store.put({id:caseId,kind:'case',owner:customer.user.id,country:'KZ',version:1,created_at:now,status:'new',target_id:id});
  const first=await call(customer,'POST','/reviews',{order_id:id,rating:5,text:'Всё хорошо'});
  const second=await call(executor,'POST','/reviews',{order_id:id,rating:4,text:'Спасибо'});
  assert.equal(first.status,'sealed');assert.equal(second.status,'sealed');
  assert.equal((await call(customer,'GET','/orders/'+id)).my_review.id,first.id);
  assert.equal((await call(executor,'GET','/orders/'+id)).my_review.id,second.id);
  assert.equal((await call(customer,'GET','/users/'+customer.user.id+'/reviews')).items.length,0);
  await assert.rejects(()=>call(stranger,'GET','/orders/'+id),e=>e.getResponse().error.code==='NOT_FOUND');
  const closed=await api.store.get(caseId);await api.store.put({...closed,status:'resolved',version:2});
  await api.maintenance(new Date(Date.now()+15*86400000));
  const published=await call(customer,'GET','/users/'+customer.user.id+'/reviews');assert.equal(published.items.length,1);assert.ok(published.items[0].published_at);
  assert.equal((await call(stranger,'GET','/users/'+customer.user.id+'/reviews')).items.length,1);
  await api.store.put({...await api.store.get(stranger.user.id),roles:['customer','executor'],active_role:'executor'});
  await assert.rejects(()=>call(stranger,'GET','/users/'+customer.user.id+'/reviews'),e=>e.getResponse().error.code==='ENTITLEMENT_REQUIRED');
  const record=await api.store.get(second.id);await api.store.put({...record,moderation_status:'hidden',version:record.version+1});
  assert.equal((await call(customer,'GET','/users/'+customer.user.id+'/reviews')).items.length,0);
 }finally{await api.store.close();}
});
