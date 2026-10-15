const {test}=require('node:test');
const assert=require('node:assert/strict');
const {offerTerms,offerPolicy,offerExpired}=require('../dist/offer-terms');
const {randomUUID}=require('node:crypto');
const {Marketplace}=require('../dist/marketplace');
const {Store}=require('../dist/store');
const now=new Date('2026-10-15T10:00:00Z');
const order={country:'KZ',expires_at:'2026-11-01T00:00:00Z',time_window:{start_date:'2026-10-16',end_date:'2026-10-18',time_zone:'Asia/Almaty'}};
test('offer terms retain local time and exact UTC, cap expiry, reject invalid duration and DST ambiguity',()=>{
 const term=offerTerms(order,{proposed_start_local:'2026-10-16T10:00',duration_minutes:300,expires_local:'2026-10-15T18:00'},72,now);
 assert.equal(term.proposed_start_at,'2026-10-16T05:00:00Z');assert.equal(term.expires_at,'2026-10-15T13:00:00Z');assert.equal(term.duration_minutes,300);
 assert.equal(offerPolicy(order,72,now).latest_expires_local,'2026-10-18T15:00');
 const rejects=(body)=>assert.throws(()=>offerTerms(order,body,72,now),e=>e.getStatus()===400);
 rejects({duration_minutes:-1});rejects({duration_minutes:1.5});rejects({proposed_start_local:'2026-10-19T10:00'});
 rejects({proposed_start_local:'2026-10-15T09:00'});rejects({expires_local:'2026-10-15T14:00'});
 rejects({proposed_start_local:'2026-10-16T10:00',expires_local:'2026-10-16T11:00'});rejects({expires_local:'2026-11-01T10:00'});
 const serbia={...order,country:'RS',time_window:{time_zone:'Europe/Belgrade'}};
 for(const proposed_start_local of ['2026-10-25T02:30','2027-03-28T02:30'])assert.throws(()=>offerTerms(serbia,{proposed_start_local},10000,now),e=>e.getStatus()===400);
 assert.equal(offerExpired({created_at:'2026-10-12T09:00:00Z'},72,now),true);
 const legacy=offerTerms(order,{},72,now,{country:'KZ',created_at:'2026-10-13T12:00:00Z'});assert.equal(legacy.expires_at,'2026-10-16T12:00:00.000Z');
});
test('expired offers cannot be selected or reused; complete terms are kept in the assignment snapshot',async()=>{
 const api=new Marketplace(new Store('memory://'));await api.initialize();
 const call=(user,method,path,body={})=>api.handle(method,path,body,user?'Bearer '+user.access_token:undefined,randomUUID());
 try{
  const register=(phone)=>call(null,'POST','/auth/register',{country:'KZ',phone,password:'Isolated offer terms password!',display_name:'Участник'});
  const customer=await register('+77006660101'),executor=await register('+77006660102');
  for(const actor of [customer,executor]){await api.store.put({...await api.store.get(actor.user.id),verification:'passed',roles:['customer','executor']});await api.store.put({id:randomUUID(),kind:'grant',country:'KZ',owner:actor.user.id,created_at:new Date().toISOString(),version:1,valid_until:new Date(Date.now()+86400000).toISOString(),capabilities:['send_offer','search_full'],source:'isolated_test'});}
  const draft=await call(customer,'POST','/orders',{title:'Собрать новую кухню',description:'Нужна аккуратная сборка новой кухни и подключение мойки.',category_id:'1',city:'Алматы'});
  const open=await call(customer,'POST',`/orders/${draft.id}/publish`,{expected_version:draft.version});
  const offer=await call(executor,'POST',`/orders/${open.id}/offers`,{amount:4500000,text:'Привезу инструменты',acknowledged_revision:open.revision,duration_minutes:300});
  assert.ok(Date.parse(offer.expires_at)>Date.now());assert.equal(offer.duration_minutes,300);
  const expired={...offer,expires_at:new Date(Date.now()-1000).toISOString()};await api.store.put(expired);
  await assert.rejects(()=>call(customer,'POST',`/orders/${open.id}/select`,{expected_version:open.version,offer_id:offer.id,offer_version:offer.version}),e=>e.getResponse().error.code==='OFFER_EXPIRED');
  assert.equal((await call(customer,'GET',`/offers/${offer.id}`)).status,'expired');
  assert.equal((await call(customer,'GET',`/conversations/${offer.conversation_id}`)).blocked,true);
  await assert.rejects(()=>call(executor,'POST',`/conversations/${offer.conversation_id}/messages`,{client_message_id:randomUUID(),text:'После истечения'}),e=>e.getResponse().error.code==='OFFER_EXPIRED');
  let fresh=await call(executor,'POST',`/orders/${open.id}/offers`,{amount:4600000,text:'Новое предложение',acknowledged_revision:open.revision,duration_minutes:360});
  const deadline=fresh.expires_at;
  fresh=await call(executor,'PATCH',`/offers/${fresh.id}`,{expected_version:fresh.version,amount:4600000,text:'Уточнённое предложение',acknowledged_revision:open.revision});
  assert.equal(fresh.expires_at,deadline);assert.equal(fresh.duration_minutes,360);
  for(const data of [{status:'published',rating:5},{status:'sealed',rating:1},{status:'published',moderation_status:'quarantined',rating:1}])await api.store.put({id:randomUUID(),kind:'review',country:'KZ',owner:customer.user.id,created_at:new Date().toISOString(),version:1,order_id:randomUUID(),target_id:executor.user.id,...data});
  const shown=(await call(customer,'GET',`/orders/${open.id}/offers`)).items.find(row=>row.id===fresh.id);
  assert.equal(shown.executor.id,executor.user.id);assert.equal(shown.executor.phone,undefined);assert.deepEqual(shown.executor.rating,{count:1,average:5});assert.equal(shown.executor.available,true);
  await assert.rejects(()=>call(executor,'GET',`/orders/${open.id}/offers`),e=>e.getStatus()===404);
  const selected=await call(customer,'POST',`/orders/${open.id}/select`,{expected_version:open.version,offer_id:fresh.id,offer_version:fresh.version});
  assert.equal((await api.store.get(offer.id)).status,'expired');
  assert.equal(selected.agreed_duration_minutes,360);assert.equal(selected.agreed_time_zone,'Asia/Almaty');
  assert.equal((await api.store.get(selected.assignment_id)).offer_snapshot.duration_minutes,360);
 }finally{await api.store.close();}
});
