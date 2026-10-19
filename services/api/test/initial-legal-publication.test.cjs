const {test}=require('node:test');
const assert=require('node:assert/strict');
const {readFileSync}=require('node:fs');
const {createHash,randomUUID}=require('node:crypto');
const {Store}=require('../dist/store');
const {Marketplace}=require('../dist/marketplace');
const {publishInitialLegal}=require('../../../scripts/publish-initial-kz-legal.cjs');
test('authorized initial KZ legal publication is complete, public, audited and preserves later edits',async()=>{
 const app=new Marketplace(new Store('memory://'));await app.initialize();
 try{
  const documents=['terms','privacy'].map(type=>({type,locale:'ru',content:readFileSync('docs/legal/kz/'+type+'.ru.txt','utf8')}));
  await assert.rejects(()=>publishInitialLegal(app.store,[documents[0]]),/Expected complete/);
  const first=await publishInitialLegal(app.store,documents);assert.equal(first.filter(d=>d.status==='published').length,2);
  const publicDocs=await app.handle('GET','/legal/documents',{},undefined,undefined,{country:'KZ',locale:'ru',required:'true'});
  assert.equal(publicDocs.items.length,2);
  for(const d of publicDocs.items){assert.equal(d.hash,createHash('sha256').update(d.content).digest('hex'));assert.ok(d.published_at);}
  const terms=publicDocs.items.find(d=>d.type==='terms');assert.equal(terms.minimum_age,18);
  const session=await app.handle('POST','/auth/register',{country:'KZ',phone:'+77000000198',password:'Isolated legal acceptance password'},undefined,randomUUID(),{},'isolated-legal');
  const call=(method,path,body={})=>app.handle(method,path,body,'Bearer '+session.access_token,randomUUID(),{},'isolated-legal');
  await assert.rejects(()=>call('POST','/me/consents',{document_id:terms.id,document_hash:'outdated-hash',accepted:true,age_confirmed:true}),e=>e.getStatus()===409&&e.getResponse().error.code==='LEGAL_VERSION_CHANGED');
  assert.equal((await call('GET','/me/consents')).items.length,0);
  for(const document of publicDocs.items)await call('POST','/me/consents',{document_id:document.id,document_hash:document.hash,accepted:true,...(document.type==='terms'?{age_confirmed:true}:{})});
  const consents=(await call('GET','/me/consents')).items;assert.equal(consents.length,2);assert.equal(consents.find(c=>c.document_id===terms.id).age_confirmed,true);
  const preferences=await call('GET','/me/notification-preferences'),user=await call('GET','/me');
  await call('PATCH','/me/notification-preferences',{expected_version:user.version,preferences:{...preferences,marketing:false}});
  assert.equal((await call('GET','/me/notification-preferences')).marketing,false);
  const internal=await app.store.get(terms.id);await app.store.put({...internal,content:'Administrator revision must remain',version:2});
  const second=await publishInitialLegal(app.store,documents);assert.equal(second.every(d=>d.status==='preserved_existing'),true);
  assert.equal((await app.store.get(terms.id)).content,'Administrator revision must remain');
  assert.equal((await app.store.all('audit','KZ')).filter(d=>d.action==='legal.initial_publication').length,2);
  assert.equal((await app.store.all('legal_document','KG')).length,0);
 }finally{await app.store.close();}
});
