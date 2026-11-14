const {test}=require('node:test'),assert=require('node:assert/strict'),{randomUUID}=require('node:crypto');
const {Marketplace}=require('../dist/marketplace'),{Store}=require('../dist/store');
const {legalHashAccepted}=require('../dist/legal-documents');
test('owner edits public contacts; anonymous pages and documents update without invalidating prior contact-only consents',async()=>{
 const api=new Marketplace(new Store('memory://'));await api.initialize();try{
 const password='Operator test password',boss=await api.handle('POST','/auth/register',{country:'KZ',phone:'+77000000861',password});await api.store.put({...await api.store.get(boss.user.id),staff_permissions:['platform_owner']});
 const owner=await api.handle('POST','/auth/staff-login',{country:'KZ',phone:boss.user.phone,password});
 const call=(m,p,b={})=>api.handle(m,p,b,'Bearer '+owner.access_token,randomUUID());
 const docs=(await api.handle('GET','/legal/documents',{},undefined,undefined,{country:'KZ',locale:'ru'})).items;
 const profile={expected_version:0,name:'ИП Тестовый оператор',tax_id:'123456789012',address:'Казахстан, тестовый адрес 12',email:'support@example.org',phone:'+77001234567'};
 const saved=await call('PUT','/admin/operator-profile',profile);assert.equal(saved.version,1);assert.equal((await call('GET','/admin/operator-profile')).email,profile.email);
 const html=(await api.handle('GET','/public/site/site/contacts.html',{})).public_html;assert.ok(html.includes(profile.email));assert.ok(html.includes(profile.phone));
 const current=(await api.handle('GET','/legal/documents',{},undefined,undefined,{country:'KZ',locale:'ru'})).items;
 for(const old of docs){const updated=current.find(x=>x.id===old.id);assert.ok(updated.content.includes(profile.email));assert.ok(legalHashAccepted(updated,old.hash));assert.notEqual(updated.hash,old.hash);assert.equal(legalHashAccepted({...updated,operator_contacts_only:false},old.hash),false);}
 await assert.rejects(()=>call('PUT','/admin/operator-profile',profile),e=>e.getStatus()===409);
 await assert.rejects(()=>call('PUT','/admin/operator-profile',{...profile,expected_version:1,email:'invalid'}),e=>e.getStatus()===422);
 await call('PUT','/admin/operator-profile',{...profile,expected_version:1,email:'new@example.org',phone:'+77007654321'});
 const next=(await api.handle('GET','/public/site/site/contacts.html',{})).public_html;assert.ok(next.includes('new@example.org'));assert.equal(next.includes(profile.email),false);assert.ok(next.includes('+77007654321'));
 const user=await api.handle('POST','/auth/register',{country:'KZ',phone:'+77000000862',password});await assert.rejects(()=>api.handle('PUT','/admin/operator-profile',profile,'Bearer '+user.access_token,randomUUID()),e=>e.getStatus()===403);
 for(const country of ['KZ','RU','BY','KG'])for(const page of ['','site/categories.html','site/pricing.html','site/privacy.html','site/support.html']){const result=await api.handle('GET','/public/site/'+page,{},undefined,undefined,{country});assert.ok(result.public_html.includes('<h1>'));assert.ok(result.public_html.includes('href="/"'));assert.equal(result.public_html.includes('data-demo'),false);}
 await assert.rejects(()=>api.handle('GET','/public/site/missing.html',{}),e=>e.getStatus()===404);
 assert.deepEqual(await api.handle('GET','/public/site/',{},undefined,undefined,{joba_push:'notifications'}),{public_redirect:'/app/?joba_push=notifications'});
 }finally{await api.store.close();}
});

test('owner activity codes are versioned in public documents and legacy contact edits preserve them',async()=>{
 const {publishOwnerActivityCodes}=require('../dist/public-operator');
 const api=new Marketplace(new Store('memory://'));await api.initialize();try{
 const password='Operator code test password',boss=await api.handle('POST','/auth/register',{country:'KZ',phone:'+77000000863',password});await api.store.put({...await api.store.get(boss.user.id),staff_permissions:['platform_owner']});
 const owner=await api.handle('POST','/auth/staff-login',{country:'KZ',phone:boss.user.phone,password});const call=(m,p,b={})=>api.handle(m,p,b,'Bearer '+owner.access_token,randomUUID());
 const contact={name:'ИП Проверка ОКЭД',tax_id:'123456789012',address:'Казахстан, тестовый адрес 12',email:'oked@example.org',phone:'+77001234567'};
 await call('PUT','/admin/operator-profile',{...contact,expected_version:0});
 const ru={id:randomUUID(),kind:'legal_document',owner:boss.user.id,country:'KZ',version:1,created_at:new Date().toISOString(),published_at:new Date().toISOString(),status:'published',locale:'ru',type:'privacy',content:'Опубликованный документ конфиденциальности',hash:'previous-ru-hash'};await api.store.put(ru);
 const kk={...ru,id:randomUUID(),locale:'kk',content:'Құпиялылық туралы құжаттың сынақ мәтіні',hash:'previous-kk-hash'};await api.store.put(kk);
 for(const country of ['RU','BY','KG'])await api.store.put({...ru,id:randomUUID(),country,locale:'ru',content:'Опубликованный региональный документ '+country,hash:'previous-'+country+'-hash',published_at:new Date().toISOString()});
 const before=(await api.store.all('public_operator_profile','KZ'))[0];
 await publishOwnerActivityCodes(api.store);const updated=(await api.store.all('public_operator_profile','KZ'))[0];assert.equal(updated.version,before.version+1);assert.equal(updated.oked_primary,'63120');assert.deepEqual(updated.oked_additional,['63115']);assert.equal(updated.oked_status,'updating');
 const html=(await api.handle('GET','/public/site/site/contacts.html',{})).public_html;assert.ok(html.includes('63120 — Деятельность веб-порталов'));assert.ok(html.includes('63115'));assert.ok(html.includes('Изменение регистрационных сведений об ОКЭД оформляется.'));assert.equal(html.includes('MCC'),false);
 const translated=await api.store.get(kk.id);assert.ok(translated.content.includes('63120'));assert.ok(translated.content.includes('63115'));assert.ok(legalHashAccepted(translated,'previous-kk-hash'));
 assert.ok(legalHashAccepted(await api.store.get(ru.id),ru.hash));
 for(const country of ['KZ','RU','BY','KG'])for(const d of (await api.handle('GET','/legal/documents',{},undefined,undefined,{country,locale:'ru'})).items){assert.ok(d.content.includes('63120'));assert.ok(d.content.includes('63115'));}
 await publishOwnerActivityCodes(api.store);assert.equal((await api.store.get(updated.id)).version,updated.version);
 const legacy=await call('PUT','/admin/operator-profile',{...contact,expected_version:updated.version,email:'next@example.org'});assert.equal(legacy.oked_primary,'63120');assert.deepEqual(legacy.oked_additional,['63115']);assert.equal(legacy.oked_status,'updating');
 for(const patch of [{oked_primary:'63.120'},{oked_primary:12345},{oked_additional:'63120'},{oked_additional:['bad']},{oked_status:'confirmed-by-bank'}])await assert.rejects(()=>call('PUT','/admin/operator-profile',{...contact,expected_version:legacy.version,...patch}),e=>e.getStatus()===422);
 const registered=await call('PUT','/admin/operator-profile',{...contact,expected_version:legacy.version,oked_primary:'63120',oked_additional:'63115',oked_status:'registered'});assert.equal(registered.oked_status,'registered');assert.equal((await api.handle('GET','/public/site/site/contacts.html',{})).public_html.includes('Изменение регистрационных сведений об ОКЭД оформляется.'),false);
 await publishOwnerActivityCodes(api.store);assert.equal((await api.store.get(updated.id)).oked_status,'registered');assert.equal((await call('GET','/me')).id,boss.user.id);
 }finally{await api.store.close();}
});
