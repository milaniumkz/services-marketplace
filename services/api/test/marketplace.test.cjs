const { test } = require('node:test');
const assert = require('node:assert/strict');
const { Marketplace } = require('../dist/marketplace');
const { Store } = require('../dist/store');
const { randomUUID } = require('node:crypto');

test('marketplace lifecycle, access boundaries, command retry and refresh replay', async () => {
  const api = new Marketplace(new Store('memory://'));
  await api.initialize();
  const call = (user, method, path, body = {}, key = randomUUID()) => api.handle(method,path,body,user ? 'Bearer '+user.access_token : undefined,key,{},'test');
  const register = (phone,country='KZ') => call(null,'POST','/auth/register',{country,phone,password:'a long unique test password',display_name:'Тестовый пользователь'});
  const rejects = async (fn, code) => assert.rejects(fn,e => e.getResponse().error.code===code);
  try {
    const customer = await register('+77000000001');
    const executor = await register('+77000000002');
    const stranger = await register('+77000000003');
    const otherRegion = await register('+375291234567','BY');
    const unpaidDraft=await call(customer,'POST','/orders',{title:'Неоплаченный черновик',description:'Описание достаточно длинное для создания черновика заказа.',category_id:'1',city:'Алматы',budget_amount:null});
    await rejects(()=>call(customer,'POST',`/orders/${unpaidDraft.id}/publish`,{expected_version:unpaidDraft.version}),'ENTITLEMENT_REQUIRED');
    // Synthetic fixture grants only: never expose a client-side self-grant endpoint.
    for (const user of [customer,executor,stranger,otherRegion]) {
      const u=await api.store.get(user.user.id); u.verification='passed';u.roles=['customer','executor']; await api.store.put(u);
      await api.store.put({id:randomUUID(),kind:'grant',owner:u.id,country:u.country,version:1,created_at:new Date().toISOString(),valid_until:new Date(Date.now()+86400000).toISOString(),capabilities:['publish_order','search_full','send_offer','select_offer','publish_profile'],source:'test_fixture'});
    }
    const body={title:'Собрать новую кухню',description:'Необходима аккуратная сборка новой кухни и подключение мойки.',category_id:'1',city:'Алматы',budget_amount:4500000};
    const key=randomUUID();
    const draft=await call(customer,'POST','/orders',body,key);
    assert.deepEqual(await call(customer,'POST','/orders',body,key),draft);
    await rejects(()=>call(customer,'POST','/orders',{...body,title:'Другой заказ'},key),'IDEMPOTENCY_CONFLICT');
    const order=await call(customer,'POST',`/orders/${draft.id}/publish`,{expected_version:1});
    await rejects(()=>call(stranger,'POST',`/orders/${order.id}/cancel`,{expected_version:2,reason:'Нет прав на отмену'}),'NOT_FOUND');
    await rejects(()=>call(otherRegion,'GET',`/orders/${order.id}`),'NOT_FOUND');
    await rejects(()=>call(executor,'POST',`/orders/${order.id}/offers`,{text:'Готов выполнить',amount:4500000,acknowledged_revision:1}),'REVISION_NOT_ACKNOWLEDGED');
    const offer=await call(executor,'POST',`/orders/${order.id}/offers`,{text:'Готов выполнить',amount:4500000,acknowledged_revision:order.revision});
    await rejects(()=>call(stranger,'GET',`/conversations/${offer.conversation_id}/messages`),'NOT_FOUND');
    const visibleOffer=await call(customer,'GET',`/offers/${offer.id}`);assert.equal(visibleOffer.order.id,order.id);assert.equal(visibleOffer.executor.id,executor.user.id);assert.equal(visibleOffer.executor.phone,undefined);
    await rejects(()=>call(stranger,'GET',`/offers/${offer.id}`),'NOT_FOUND');
    const msg={client_message_id:randomUUID(),text:'Согласуем время работы'};
    const sent=await call(customer,'POST',`/conversations/${offer.conversation_id}/messages`,msg);
    assert.equal((await call(customer,'POST',`/conversations/${offer.conversation_id}/messages`,msg)).id,sent.id);
    await rejects(()=>call(customer,'POST',`/conversations/${offer.conversation_id}/messages`,{...msg,text:'Другой текст'}),'IDEMPOTENCY_CONFLICT');
    const assigned=await call(customer,'POST',`/orders/${order.id}/select`,{expected_version:order.version,offer_id:offer.id,offer_version:offer.version});
    assert.equal(assigned.status,'assigned');
    const working=await call(customer,'GET',`/orders/${order.id}`);assert.equal(working.conversation_id,offer.conversation_id);assert.equal(working.executor.id,executor.user.id);assert.equal(working.customer.phone,undefined);
    await rejects(()=>call(customer,'POST',`/orders/${order.id}/select`,{expected_version:order.version,offer_id:offer.id,offer_version:1}),'STATE_CONFLICT');
    const started=await call(executor,'POST',`/orders/${order.id}/start`,{expected_version:assigned.version});
    const completing=await call(executor,'POST',`/orders/${order.id}/request-completion`,{expected_version:started.version});
    const complete=await call(customer,'POST',`/orders/${order.id}/confirm-completion`,{expected_version:completing.version});
    assert.equal(complete.status,'completed');
    const review=await call(customer,'POST','/reviews',{order_id:order.id,rating:5,text:'Хорошая работа'});assert.equal(review.status,'sealed');
    await call(executor,'POST','/reviews',{order_id:order.id,rating:5,text:'Все отлично'});
    assert.equal((await api.store.all('review','KZ')).filter(x=>x.status==='published').length,2);
    await rejects(()=>call(stranger,'POST','/reviews',{order_id:order.id,rating:5,text:'Чужой отзыв'}),'FORBIDDEN');
    await rejects(()=>call(customer,'GET','/admin/users'),'FORBIDDEN');
    await rejects(()=>call(customer,'POST','/billing/verify-purchase',{transaction_reference:'fake',provider:'missing'}),'PROVIDER_UNAVAILABLE');
    await rejects(()=>call(customer,'POST','/me/verification-sessions',{document_type:'passport'}),'COUNTRY_FLOW_UNAPPROVED');
    const rotated=await call(null,'POST','/auth/refresh',{refresh_token:customer.refresh_token});
    await rejects(()=>call(customer,'GET','/me'),'TOKEN_EXPIRED');
    await rejects(()=>call(null,'POST','/auth/refresh',{refresh_token:customer.refresh_token}),'REFRESH_REPLAY');
    await rejects(()=>call(rotated,'GET','/me'),'TOKEN_EXPIRED');
  } finally { await api.store.close(); }
});

test('privacy and support remain available without marketplace entitlement', async () => {
  const api = new Marketplace(new Store('memory://'));await api.initialize();
  try {
    const u=await api.handle('POST','/auth/register',{country:'KZ',phone:'+77000000010',password:'a very long password!',display_name:'Тест'},undefined,undefined,{},'test');
    const token='Bearer '+u.access_token;
    const thread=await api.handle('POST','/support/threads',{subject:'Нужна помощь со входом'},token,randomUUID());
    const result=await api.handle('POST',`/support/threads/${thread.id}/messages`,{client_message_id:randomUUID(),text:'У меня нет подписки'},token,randomUUID());
    assert.equal(result.sequence,1);
    const privacy=await api.handle('POST','/me/privacy-requests',{type:'delete',current_password:'a very long password!'},token,randomUUID());
    assert.equal(privacy.status,'requested');
    assert.equal((await api.handle('GET','/me/privacy-requests',{},token)).items.length,1);
    const recovery=await api.handle('POST','/public/recovery-threads',{country:'KZ',subject:'Восстановление доступа',text:'Нужна помощь'},undefined,undefined,{},'test');
    assert.equal((await api.handle('GET',`/public/recovery-threads/${recovery.id}/messages`,{},'Bearer '+recovery.capability)).items.length,1);
    await assert.rejects(()=>api.handle('GET',`/public/recovery-threads/${recovery.id}/messages`,{},'Bearer fake'),e=>e.getStatus()===404);
  } finally { await api.store.close(); }
});
