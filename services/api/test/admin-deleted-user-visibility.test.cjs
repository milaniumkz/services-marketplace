const {test}=require('node:test'),assert=require('node:assert/strict'),{randomUUID}=require('node:crypto');
const {Marketplace}=require('../dist/marketplace'),{Store}=require('../dist/store');
test('deleted users disappear across admin queues, details, search and counts without changing retention or blocked accounts',async()=>{
 const a=new Marketplace(new Store('memory://'));await a.initialize();try{
 const password='Isolated account removal password!';
 const boss=await a.handle('POST','/auth/register',{country:'KZ',phone:'+77000000881',password});
 await a.store.put({...await a.store.get(boss.user.id),staff_permissions:['platform_owner']});
 const session=await a.handle('POST','/auth/staff-login',{country:'KZ',phone:boss.user.phone,password});
 const call=(m,p,b={},q={})=>a.handle(m,p,b,'Bearer '+session.access_token,randomUUID(),q);
 const customer=await a.handle('POST','/auth/register',{country:'KZ',phone:'+77000000882',password});
 const make=(kind,owner,data={})=>({id:randomUUID(),kind,owner,country:'KZ',version:1,created_at:new Date().toISOString(),...data});
 const verification=make('verification',customer.user.id,{status:'pending_review',submitted_role:'customer'});
 const portfolio=make('portfolio',customer.user.id,{status:'pending_review',title:'Deleted portfolio'});
 const order=make('order',customer.user.id,{status:'open',title:'Deleted order'});
 const offer=make('offer',boss.user.id,{order_id:order.id,status:'pending'});
 const chat=make('conversation',boss.user.id,{order_id:order.id,status:'open'});
 const message=make('message',boss.user.id,{conversation_id:chat.id,text:'Linked message'});
 for(const r of [verification,portfolio,order,offer,chat,message])await a.store.put(r);
 const before=await call('GET','/admin/dashboard');assert.equal(before.review.queues.find(q=>q.key==='customers').count,1);
 await call('POST','/admin/users/'+customer.user.id+'/block',{expected_version:1});
 assert.ok((await call('GET','/admin/users')).items.some(r=>r.id===customer.user.id));
 assert.ok((await call('GET','/admin/verifications')).items.some(r=>r.id===verification.id));
 await call('POST','/admin/users/'+customer.user.id+'/delete',{expected_version:2});
 for(const [route,id] of [['users',customer.user.id],['verifications',verification.id],['portfolio',portfolio.id],['orders',order.id]]){
  assert.equal((await call('GET','/admin/'+route)).items.some(r=>r.id===id),false,route);
  await assert.rejects(()=>call('GET','/admin/'+route+'/'+id),e=>e.getStatus()===404,route);
  assert.equal((await call('GET','/admin/search',{}, {q:id})).items.some(r=>r.id===id),false);
 }
 const after=await call('GET','/admin/dashboard');assert.equal(after.review.queues.find(q=>q.key==='customers').count,0);assert.equal(after.review.queues.find(q=>q.key==='portfolio').count,0);
 assert.equal(after.orders,before.orders-1);assert.equal(after.review.activity.some(r=>[verification.id,portfolio.id].includes(r.id)),false);
 assert.ok(await a.store.get(verification.id),'private retention is unchanged');
 assert.equal((await a.store.withAdminReads(()=>a.store.all('offer','KZ'))).some(r=>r.id===offer.id),false);
 assert.equal((await a.store.withAdminReads(()=>a.store.all('message','KZ'))).some(r=>r.id===message.id),false);
 const [retained,visible]=await Promise.all([a.store.all('verification','KZ'),a.store.withAdminReads(()=>a.store.all('verification','KZ'))]);assert.equal(retained.length,1);assert.equal(visible.length,0);
 // A new identity reusing the same number must not inherit the old visibility state.
 const fresh=make('user',randomUUID(),{status:'active',phone:customer.user.phone,staff_permissions:[]});await a.store.put(fresh);
 assert.ok((await call('GET','/admin/users')).items.some(r=>r.id===fresh.id));
 }finally{await a.store.close();}
});
