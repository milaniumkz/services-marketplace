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
