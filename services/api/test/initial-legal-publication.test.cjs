const {test}=require('node:test');
const assert=require('node:assert/strict');
const {readFileSync}=require('node:fs');
const {createHash}=require('node:crypto');
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
  const internal=await app.store.get(terms.id);await app.store.put({...internal,content:'Administrator revision must remain',version:2});
  const second=await publishInitialLegal(app.store,documents);assert.equal(second.every(d=>d.status==='preserved_existing'),true);
  assert.equal((await app.store.get(terms.id)).content,'Administrator revision must remain');
  assert.equal((await app.store.all('audit','KZ')).filter(d=>d.action==='legal.initial_publication').length,2);
  assert.equal((await app.store.all('legal_document','RS')).length,0);
 }finally{await app.store.close();}
});
