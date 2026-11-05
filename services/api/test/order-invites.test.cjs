const {paidCustomer}=require('./paid-customer-fixture.cjs');
const {test}=require('node:test');
const assert=require('node:assert/strict');
const {randomUUID}=require('node:crypto');
const {Store}=require('../dist/store');
const {Marketplace}=require('../dist/marketplace');
test('invitations enforce expiry, active pair and daily limit without spending action credits',async()=>{
 const api=new Marketplace(new Store('memory://'));await api.initialize();
 try{
  const register=phone=>api.handle('POST','/auth/register',{country:'KZ',phone,password:'Isolated invitation test!',display_name:'Участник'},undefined,undefined,{},phone);
  const customer=await register('+77000000191'),executor=await register('+77000000192');
  await paidCustomer(api,customer);
  const now=new Date().toISOString(),until=new Date(Date.now()+86400000).toISOString();
  const put=(kind,owner,data)=>api.store.put({id:randomUUID(),kind,country:'KZ',owner,version:1,created_at:now,...data});
  const user=await api.store.get(executor.user.id);await api.store.put({...user,roles:['executor'],verification:'passed'});
  const cg=await put('grant',customer.user.id,{capabilities:['publish_order'],valid_until:until,balance:2});
  const eg=await put('grant',executor.user.id,{capabilities:['send_offer'],valid_until:until,balance:2});
  const profile=await put('contractor',executor.user.id,{status:'published',availability:'available'});
  const order=await put('order',customer.user.id,{status:'open',revision:1,expires_at:until,title:'Реальный заказ теста',exact_address:'Скрытый адрес'});
  const post=(session,path,body)=>api.handle('POST',path,body,'Bearer '+session.access_token,randomUUID());
  const invite=await post(customer,`/orders/${order.id}/invites`,{contractor_id:profile.id,message:'Подойдут ли сроки?'});
  assert.equal(invite.message,'Подойдут ли сроки?');
  assert.ok(Math.abs(Date.parse(invite.expires_at)-Date.now()-72*3600000)<5000);
  await assert.rejects(()=>post(customer,`/orders/${order.id}/invites`,{contractor_id:profile.id}),e=>e.getResponse().error.code==='STATE_CONFLICT');
  const accepted=await post(executor,`/order-invites/${invite.id}/respond`,{expected_version:1,decision:'accept'});
  assert.equal(accepted.status,'accepted');assert.equal((await api.store.get(cg.id)).balance,2);assert.equal((await api.store.get(eg.id)).balance,2);
  assert.equal((await api.store.all('conversation','KZ')).length,0);
  const stale=await post(customer,`/orders/${order.id}/invites`,{contractor_id:profile.id});
  await api.store.put({...order,revision:2,version:2});
  await assert.rejects(()=>post(executor,`/order-invites/${stale.id}/respond`,{expected_version:1,decision:'accept'}),e=>e.getResponse().error.code==='STATE_CONFLICT');
  await api.store.put({...stale,expires_at:new Date(Date.now()-1000).toISOString()});
  const list=await api.handle('GET','/me/order-invites',{},'Bearer '+executor.access_token);
  const shown=list.items.find(i=>i.id===stale.id);assert.equal(shown.status,'expired');
  const expired=await api.handle('GET','/me/order-invites',{},'Bearer '+executor.access_token,undefined,{status:'expired'});assert.equal(expired.items.length,1);assert.equal(expired.items[0].id,stale.id);
  const pending=await api.handle('GET','/me/order-invites',{},'Bearer '+executor.access_token,undefined,{status:'pending'});assert.equal(pending.items.length,0);
  assert.equal(shown.order.title,'Реальный заказ теста');assert.equal(shown.order.exact_address,undefined);assert.equal(shown.customer.phone,undefined);
  const overview=await api.handle('GET','/me/overview',{},'Bearer '+executor.access_token);assert.equal(overview.invitations.pending,0);
  await assert.rejects(()=>post(executor,`/order-invites/${stale.id}/respond`,{expected_version:1,decision:'decline'}),e=>e.getResponse().error.code==='STATE_CONFLICT');
  for(let n=0;n<8;n++)await put('invite',customer.user.id,{status:'declined',recipient_id:executor.user.id,order_id:randomUUID()});
  await assert.rejects(()=>post(customer,`/orders/${order.id}/invites`,{contractor_id:profile.id}),e=>e.getResponse().error.code==='RATE_LIMITED');
 }finally{await api.store.close();}
});
test('a paid customer can invite an executor without buying access for that executor; cross-account expiry never requests caller payment',async()=>{
 const api=new Marketplace(new Store('memory://'));await api.initialize();try{
  const register=phone=>api.handle('POST','/auth/register',{country:'KZ',phone,password:'Isolated invitation access!'},undefined,randomUUID());
  const buyer=await register('+77000001651'),worker=await register('+77000001652');await paidCustomer(api,buyer);
  await api.store.put({...await api.store.get(worker.user.id),roles:['customer','executor'],active_role:'executor',verification:'passed'});
  const now=new Date().toISOString(),future=new Date(Date.now()+86400000).toISOString();
  const row=(kind,owner,data)=>api.store.put({id:randomUUID(),kind,owner,country:'KZ',version:1,created_at:now,...data});
  const profile=await row('contractor',worker.user.id,{status:'published',availability:'available'}),order=await row('order',buyer.user.id,{status:'open',revision:1,expires_at:future,title:'Приглашение без чужой оплаты'});
  const post=(u,path,b)=>api.handle('POST',path,b,'Bearer '+u.access_token,randomUUID());
  const invite=await post(buyer,`/orders/${order.id}/invites`,{contractor_id:profile.id});assert.equal(invite.status,'pending');
  assert.equal((await api.store.select('grant','KZ',{owner:worker.user.id,limit:100})).length,0);
  await assert.rejects(()=>post(worker,`/order-invites/${invite.id}/respond`,{expected_version:1,decision:'accept'}),e=>e.getResponse().error.code==='ENTITLEMENT_REQUIRED');
  await row('grant',worker.user.id,{role:'executor',plan:'standard',valid_until:future,capabilities:['send_offer','search_full']});
  const buyerGrant=(await api.store.select('grant','KZ',{owner:buyer.user.id,limit:100}))[0];await api.store.put({...buyerGrant,valid_until:'2000-01-01T00:00:00Z',version:buyerGrant.version+1});
  await assert.rejects(()=>post(worker,`/order-invites/${invite.id}/respond`,{expected_version:1,decision:'accept'}),e=>e.getResponse().error.code==='INVITE_CUSTOMER_ACCESS_EXPIRED');
  await api.store.put({...buyerGrant,version:buyerGrant.version+2});
  assert.equal((await post(worker,`/order-invites/${invite.id}/respond`,{expected_version:1,decision:'accept'})).status,'accepted');
 }finally{await api.store.close();}
});
