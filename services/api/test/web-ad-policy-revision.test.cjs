const {test}=require('node:test'),assert=require('node:assert/strict'),{randomUUID,createHash}=require('node:crypto');
const {Marketplace}=require('../dist/marketplace'),{Store}=require('../dist/store');
test('rewarded playback preserves authentic platform acceptance across notice revisions without inventing consent or ignoring withdrawal',async()=>{
 const api=new Marketplace(new Store('memory://'));await api.initialize();try{
  const account=await api.handle('POST','/auth/register',{country:'KZ',phone:'+77000000865',password:'Isolated reward revision password!'});
  const call=(m,p,b={})=>api.handle(m,p,b,'Bearer '+account.access_token,randomUUID());
  const now=new Date().toISOString(),makeDoc=(type,revision)=>{const content='Isolated published '+type+' notice revision '+revision;return {id:randomUUID(),kind:'legal_document',owner:'isolated-operator',country:'KZ',created_at:now,published_at:new Date(Date.now()+revision*1000).toISOString(),version:revision,status:'published',type,locale:'ru',content,hash:createHash('sha256').update(content).digest('hex'),...(type==='terms'?{minimum_age:18}:{})};};
  const terms=makeDoc('terms',1),privacy=makeDoc('privacy',1);
  for(const doc of [terms,privacy]){await api.store.put(doc);await call('POST','/me/consents',{document_id:doc.id,document_hash:doc.hash,accepted:true,...(doc.type==='terms'?{age_confirmed:true}:{})});}
  await api.store.put({id:randomUUID(),kind:'web_ad_config',owner:'isolated-operator',country:'KZ',version:1,created_at:now,enabled:true,rewarded_enabled:true,customer_views:5});
  const revised=makeDoc('privacy',5);await api.store.put(revised);
  await call('POST','/me/web-ads/consent',{accepted:true});
  const start=()=>call('POST','/me/web-ads/reward-sessions',{platform:'android',provider:'yandex',target:'customer'});
  const close=s=>call('POST','/me/web-ads/reward-sessions/'+s.id+'/outcome',{nonce:s.nonce,completed:false});
  const first=await start();assert.equal(first.block_id,'R-M-20254161-3');assert.equal(first.status,'pending');await close(first);
  const originalEvidence=(await api.store.all('consent','KZ')).filter(c=>c.owner===account.user.id);assert.equal(originalEvidence.length,2);assert(!originalEvidence.some(c=>c.document_id===revised.id));
  await call('POST','/me/consents',{document_id:privacy.id,document_hash:privacy.hash,accepted:false});
  await assert.rejects(start,e=>e.getStatus()===403&&e.getResponse().error.message.includes('Примите опубликованные'));
  await call('POST','/me/consents',{document_id:revised.id,document_hash:revised.hash,accepted:true});
  const second=await start();await close(second);
  // A malformed/forged acceptance cannot become valid through the revision fallback.
  await api.store.put({id:randomUUID(),kind:'consent',owner:account.user.id,country:'KZ',version:1,created_at:now,sequence:100,document_id:privacy.id,document_hash:'incorrect',accepted:true});
  await assert.rejects(start,e=>e.getStatus()===403);
  await call('POST','/me/consents',{document_id:revised.id,document_hash:revised.hash,accepted:true});
  await call('POST','/me/web-ads/consent',{accepted:false});await assert.rejects(start,e=>e.getStatus()===403);
  assert.equal((await api.store.all('subscription','KZ')).filter(s=>s.owner===account.user.id).length,0);
 }finally{await api.store.close();}
});
