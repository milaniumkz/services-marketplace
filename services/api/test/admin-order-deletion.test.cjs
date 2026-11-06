const {test}=require('node:test'),assert=require('node:assert/strict'),{randomUUID}=require('node:crypto');
const {Marketplace}=require('../dist/marketplace'),{Store}=require('../dist/store');
test('admin deletion immediately removes an order from directory, search, personal lists and detail, closes linked chats and remains audited',async()=>{
 const a=new Marketplace(new Store('memory://'));await a.initialize();try{
 const pwd='Order removal isolated password!',owner=await a.handle('POST','/auth/register',{country:'KZ',phone:'+77000000651',password:pwd});await a.store.put({...await a.store.get(owner.user.id),staff_permissions:['platform_owner']});
 const boss=await a.handle('POST','/auth/staff-login',{country:'KZ',phone:owner.user.phone,password:pwd});const call=(m,p,b={},q={})=>a.handle(m,p,b,'Bearer '+boss.access_token,randomUUID(),q);
 const customer=await a.handle('POST','/auth/register',{country:'KZ',phone:'+77000000652',password:pwd});const record=(kind,data)=>({id:randomUUID(),kind,owner:customer.user.id,country:'KZ',version:1,created_at:new Date().toISOString(),...data});
 const order=record('order',{title:'Удаляемый заказ штукатурки',description:'Достаточное описание ремонтного заказа',status:'open',city:'Караганда',expires_at:new Date(Date.now()+86400000).toISOString()});await a.store.put(order);const chat=record('conversation',{order_id:order.id,status:'open',members:[customer.user.id,owner.user.id]});await a.store.put(chat);
 assert.ok((await call('GET','/admin/orders')).items.some(x=>x.id===order.id));
 await assert.rejects(()=>a.handle('DELETE','/admin/orders/'+order.id,{expected_version:1},'Bearer '+customer.access_token,randomUUID()),e=>e.getStatus()===403);
 await assert.rejects(()=>call('DELETE','/admin/orders/'+order.id,{expected_version:0}),e=>e.getStatus()===409);
 const key=randomUUID(),deleted=await a.handle('DELETE','/admin/orders/'+order.id,{expected_version:1},'Bearer '+boss.access_token,key);assert.equal(deleted.deleted,true);assert.deepEqual(await a.handle('DELETE','/admin/orders/'+order.id,{expected_version:1},'Bearer '+boss.access_token,key),deleted);
 assert.equal((await call('GET','/admin/orders')).items.some(x=>x.id===order.id),false);assert.equal((await call('GET','/admin/orders',{}, {status:'deleted'})).items.length,0);assert.equal((await call('GET','/admin/search',{}, {q:order.id})).items.some(x=>x.id===order.id),false);
 await assert.rejects(()=>call('GET','/admin/orders/'+order.id),e=>e.getStatus()===404);assert.equal((await a.handle('GET','/me/orders',{},'Bearer '+customer.access_token)).items.some(x=>x.id===order.id),false);await assert.rejects(()=>a.handle('GET','/orders/'+order.id,{},'Bearer '+customer.access_token),e=>e.getStatus()===404);
 assert.equal((await a.store.get(chat.id)).status,'closed');assert.ok((await a.store.all('audit','KZ')).some(x=>x.action==='order.deleted'));assert.ok((await a.store.all('notification','KZ')).some(x=>x.type==='order.deleted'&&x.title==='Заказ удалён администратором'));
 }finally{await a.store.close();}
});
