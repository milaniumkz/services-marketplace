const {test}=require('node:test'),assert=require('node:assert/strict'),{randomUUID}=require('node:crypto'),{readFileSync}=require('node:fs');
const {Marketplace}=require('../dist/marketplace'),{Store}=require('../dist/store'),{profileFields}=require('../dist/contractor-profile');
const {publishCountryReadiness}=require('../../../scripts/publish-country-readiness.cjs');
const documents=['KZ','RU','BY','KG'].flatMap(country=>['terms','privacy','payments','refunds','public_offer','contacts','verification_consent'].map(type=>({country,type,locale:'ru',content:readFileSync(__dirname+'/../../../docs/legal/'+country.toLowerCase()+'/'+type+'.ru.txt','utf8')})));
test('all four countries have registration documents, locale fallback, identity policy and test offers; re-deployment preserves admin edits',async()=>{
 const api=new Marketplace(new Store('memory://'));await api.initialize();try{
 const c={id:randomUUID(),kind:'country_control',owner:'system',country:'BY',version:1,created_at:new Date().toISOString(),status:'effective',payload:{registration_enabled:false,stop_new_business:true}};await api.store.put(c);
 await publishCountryReadiness(api.store,documents);
 const config=await api.handle('GET','/public/config');assert.ok(config.countries.every(c=>c.active&&c.registration_enabled&&!c.stop_new_business));
 const phones={KZ:'+77000000721',RU:'+79001234721',BY:'+375291234721',KG:'+996700123721'};
 for(const country of Object.keys(phones)){
  const locale=country==='BY'?'be':country==='KZ'?'kk':'ru';const list=await api.handle('GET','/legal/documents',{},undefined,undefined,{country,locale,required:'true'});for(const type of ['terms','privacy','payments','refunds','public_offer','contacts','verification_consent'])assert.ok(list.items.some(d=>d.type===type));assert.ok(list.items.every(d=>d.country===country&&d.content.length>=500));
  const all=await api.handle('GET','/legal/documents',{},undefined,undefined,{country,locale});assert.ok(all.items.some(d=>d.type==='terms'));
  const registered=await api.handle('POST','/auth/register',{country,phone:phones[country],password:'Isolated country password!'},undefined,undefined,{},country);
  const token='Bearer '+registered.access_token;const offers=await api.handle('GET','/billing/offers',{},token);assert.ok(offers.items.some(o=>o.plan==='customer'&&o.amount_minor>0&&o.is_test));
  assert.ok((await api.store.all('verification_policy',country)).some(p=>p.status==='effective'));
  const langs=(await api.handle('GET','/me/contractor-profile',{},token)).communication_languages;assert.deepEqual(langs.map(l=>l.code),['ru','ky','kk','be','en']);
 }
 const row=(await api.store.all('legal_document','BY')).find(d=>d.type==='terms');await api.store.put({...row,content:'Собственная редакция владельца'});await api.store.put({...await api.store.get(c.id),payload:{registration_enabled:false,stop_new_business:false}});
 await publishCountryReadiness(api.store,documents);assert.equal((await api.store.get(row.id)).content,'Собственная редакция владельца');assert.equal((await api.store.get(c.id)).payload.registration_enabled,false);
 assert.deepEqual(profileFields({category_id:'category',city:'Бишкек',languages:['ky','en']},null,'KGS',new Set(['category'])).languages,['ky','en']);
 }finally{await api.store.close();}
});
