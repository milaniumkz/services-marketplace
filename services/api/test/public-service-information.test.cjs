const {test}=require('node:test'),assert=require('node:assert/strict'),{randomUUID,createHash}=require('node:crypto');
const {Marketplace}=require('../dist/marketplace'),{Store}=require('../dist/store');
const {currentServiceText,refreshPublicServiceInformation}=require('../dist/public-service-information');
const {currentLegalDocuments,legalHashAccepted}=require('../dist/legal-documents');
test('public bank information uses editable prices, anonymous access and country-specific payment availability',async()=>{
 const api=new Marketplace(new Store('memory://'));await api.initialize();try{
 // Use the same catalogue API shape as the administrator; public rendering must
 // read each time rather than copy a price into a static page.
 const before=(await api.commerce.plans('KZ')).items;
 const html=(await api.handle('GET','/public/site/site/pricing.html',{})).public_html;
 for(const item of before)assert.ok(html.includes(new Intl.NumberFormat('ru',{style:'currency',currency:item.currency}).format(item.amount_minor/100)));
 for(const path of ['pricing','privacy','payments','refunds','contacts','offer']){
  const result=await api.handle('GET','/public/site/site/'+path+'.html',{});
  assert.ok(result.public_html.includes('href="/"'));assert.ok(result.public_html.includes('/site/pricing.html'));
  assert.ok(result.public_html.includes('/site/privacy.html'));assert.ok(result.public_html.includes('/site/contacts.html'));
 }
 api.commerce.providers.billing.set('kz-test',{name:'kz-test',hostedCheckout:true,countries:['KZ'],environment:'sandbox'});
 const kz=(await api.handle('GET','/public/site/site/pricing.html',{})).public_html;
 assert.ok(kz.includes('Используйте только тестовые карты банка'));
 const kg=(await api.handle('GET','/public/site/site/pricing.html',{},undefined,undefined,{country:'KG'})).public_html;
 assert.equal(kg.includes('Банковская оплата работает в тестовой среде'),false);
 const originalPlans=api.commerce.plans.bind(api.commerce);
 api.commerce.plans=async country=>{const catalog=await originalPlans(country);return {...catalog,items:catalog.items.map(x=>({...x,amount_minor:32100}))};};
 const changed=(await api.handle('GET','/public/site/site/pricing.html',{})).public_html;
 assert.ok(changed.includes(new Intl.NumberFormat('ru',{style:'currency',currency:'KZT'}).format(321)));
 assert.ok(changed.includes('Физическая доставка отсутствует'));assert.ok(changed.includes('серверного подтверждения'));
 }finally{await api.store.close();}
});
test('obsolete service clauses get a new published revision once; prior consents and operator text are not silently changed',async()=>{
 const store=new Store('memory://');await store.initialize();try{
 const content='ИП Пример\nОсновные возможности заказчика бесплатны; подписка заказчика не продаётся.\nВ Казахстане базовая цена — 500 тенге.\nИндивидуальные условия оператора без изменений.';
 const old={id:randomUUID(),kind:'legal_document',owner:randomUUID(),country:'KZ',type:'contacts',locale:'ru',status:'published',version:3,created_at:'2026-10-01T00:00:00Z',published_at:'2026-10-01T00:00:00Z',content,hash:createHash('sha256').update(content).digest('hex'),operator_contacts_only:true,operator_contact_previous_hashes:['old-contact-hash']};await store.put(old);
 await refreshPublicServiceInformation(store);
 const docs=await store.all('legal_document','KZ'),current=currentLegalDocuments(docs,'KZ','ru')[0];
 assert.equal(docs.length,2);assert.equal((await store.get(old.id)).content,content);assert.notEqual(current.id,old.id);assert.equal(current.version,4);
 assert.equal(current.content.includes('500 тенге'),false);assert.equal(current.content.includes('подписка заказчика не продаётся'),false);assert.ok(current.content.includes('ИП Пример'));assert.ok(current.content.includes('Индивидуальные условия оператора без изменений.'));
 assert.equal(legalHashAccepted(current,old.hash),false);assert.equal(legalHashAccepted(current,'old-contact-hash'),false);
 await refreshPublicServiceInformation(store);assert.equal((await store.all('legal_document','KZ')).length,2);
 assert.equal((await store.all('audit','KZ')).length,1);
 const custom='Проверенные индивидуальные условия владельца';assert.equal(currentServiceText(custom),custom);
 }finally{await store.close();}
});
