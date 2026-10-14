const {test}=require('node:test');
const assert=require('node:assert/strict');
const {randomUUID,randomBytes}=require('node:crypto');
const {Marketplace}=require('../dist/marketplace');
const {Store}=require('../dist/store');
const {totp}=require('../dist/totp');
test('staff review protects document references, regional data and sensitive reads',async()=>{
 const api=new Marketplace(new Store('memory://'));await api.initialize();
 const password='Isolated review account password';
 const register=phone=>api.handle('POST','/auth/register',{country:'KZ',phone,password},undefined,undefined,{},phone);
 const call=(session,method,path,body={},query={})=>api.handle(method,path,body,'Bearer '+session.access_token,randomUUID(),query);
 const rejected=(fn,code)=>assert.rejects(fn,error=>error.getResponse().error.code===code);
 try{
  const owner=await register('+77000000451'),staffAccount=await register('+77000000452');
  const user=await api.store.get(staffAccount.user.id),secret=randomBytes(20).toString('hex');
  await api.store.put({...user,staff_permissions:['verification_reviewer'],totp_secret:secret});
  const staff=await api.handle('POST','/auth/staff-login',{country:'KZ',phone:user.phone,password,mfa_code:totp(secret)},undefined,undefined,{},'review-staff');
  const id=randomUUID(),file=randomUUID(),base={kind:'verification',owner:owner.user.id,version:1,created_at:new Date().toISOString(),status:'pending_review',document_type:'passport',document_revision:2,document_refs:[file]};
  await api.store.put({...base,id,country:'KZ'});
  const foreign=randomUUID();await api.store.put({...base,id:foreign,country:'RS'});
  const path='/admin/verifications/'+id;
  assert.equal((await call(staff,'GET',path)).document_refs,undefined);
  assert.equal((await call(staff,'GET','/admin/verifications')).items[0].document_refs,undefined);
  await rejected(()=>call(owner,'GET',path),'FORBIDDEN');
  await rejected(()=>call(staff,'GET','/admin/verifications/'+foreign),'NOT_FOUND');
  await rejected(()=>call(staff,'GET',path,{}, {include_documents:'true',reason:'Проверка документов по заявке'}),'FORBIDDEN');
  await api.store.put({...await api.store.get(user.id),staff_permissions:['verification_reviewer','identity_view']});
  await rejected(()=>call(staff,'GET',path,{}, {include_documents:'true'}),'VALIDATION_ERROR');
  assert.deepEqual((await call(staff,'GET',path,{}, {include_documents:'true',reason:'Проверка документов по заявке'})).document_refs,[file]);
  assert.ok((await api.store.all('audit','KZ')).some(x=>x.action==='verification.documents_read'));
  await rejected(()=>call(staff,'POST',path+'/decision',{expected_version:1,document_revision:1,decision:'rejected',reason:'Документ не соответствует правилам'}),'STATE_CONFLICT');
  await call(staff,'POST',path+'/decision',{expected_version:1,document_revision:2,decision:'rejected',reason:'Документ не соответствует правилам'});
  assert.equal((await api.store.get(owner.user.id)).verification,'rejected');
  const otherId=randomUUID();await api.store.put({...base,id:otherId,country:'KZ',status:'draft',document_refs:[]});
  const upload=await call(owner,'POST','/uploads/initiate',{purpose:'identity',verification_id:otherId,mime:'image/png',size:100});
  assert.equal(upload.verification_id,otherId);
  // Isolated metadata fixture exercises session binding, not antivirus correctness.
  await api.store.put({...upload,kind:'upload',status:'clean'});
  await rejected(()=>call(owner,'POST','/me/verification-sessions/'+id+'/submit',{expected_version:2,upload_ids:[upload.id]}),'POLICY_REJECTED');
  await call(owner,'POST','/me/verification-sessions/'+otherId+'/submit',{expected_version:1,upload_ids:[upload.id]});
  assert.equal((await api.store.get(otherId)).status,'pending_review');

 }finally{await api.store.close();}
});
test('public recovery retries create one thread and published legal data exclude drafts and staff metadata',async()=>{
 const api=new Marketplace(new Store('memory://'));await api.initialize();
 try{
  const key=randomUUID(),body={country:'KZ',subject:'Нет доступа к аккаунту',text:'Помогите восстановить доступ'};
  const first=await api.handle('POST','/public/recovery-threads',body,undefined,key,{},'recovery-test');
  const second=await api.handle('POST','/public/recovery-threads',body,undefined,key,{},'recovery-test');
  assert.deepEqual(second,first);assert.equal((await api.store.all('recovery','KZ')).length,1);
  const draft={id:randomUUID(),kind:'legal_document',owner:'private-staff-id',country:'KZ',version:1,created_at:new Date().toISOString(),status:'draft',type:'privacy',locale:'ru',content:'Private draft',reason:'Private legal workflow note'};
  await api.store.put(draft);await api.store.put({...draft,id:randomUUID(),status:'published',published_at:'2026-01-01T00:00:00Z',content:'Previous approved legal text'});await api.store.put({...draft,id:randomUUID(),status:'published',published_at:'2026-02-01T00:00:00Z',content:'Published approved legal text'});
  const docs=await api.handle('GET','/legal/documents',{},undefined,undefined,{country:'KZ',locale:'ru'});
  assert.equal(docs.items.length,1);assert.equal(docs.items[0].content,'Published approved legal text');assert.equal(docs.items[0].owner,undefined);assert.equal(docs.items[0].reason,undefined);
 }finally{await api.store.close();}
});
test('new business commands require current consent and honor withdrawal without blocking privacy',async()=>{
 const api=new Marketplace(new Store('memory://'));await api.initialize();
 try{
  const session=await api.handle('POST','/auth/register',{country:'KZ',phone:'+77000000461',password:'Isolated legal account password'},undefined,undefined,{},'legal-test');
  const command=(method,path,body={})=>api.handle(method,path,body,'Bearer '+session.access_token,randomUUID());
  const document={id:randomUUID(),kind:'legal_document',owner:'system',country:'KZ',version:2,created_at:new Date().toISOString(),published_at:new Date().toISOString(),status:'published',type:'privacy',locale:'ru',content:'Approved privacy text',hash:'current-legal-hash'};
  await api.store.put(document);
  await api.store.put({id:randomUUID(),kind:'grant',owner:session.user.id,country:'KZ',version:1,created_at:new Date().toISOString(),valid_until:new Date(Date.now()+86400000).toISOString(),capabilities:['publish_order'],source:'isolated_legal_fixture'});
  const order={id:randomUUID(),kind:'order',owner:session.user.id,country:'KZ',version:1,revision:1,created_at:new Date().toISOString(),status:'draft',title:'Isolated legal draft'};
  await api.store.put(order);
  const publish=()=>command('POST','/orders/'+order.id+'/publish',{expected_version:1});
  await assert.rejects(publish,error=>error.getResponse().error.code==='CONSENT_REQUIRED');
  const identity=await api.store.get(session.user.id);await api.store.put({...identity,locale:'be'});
  await assert.rejects(publish,error=>error.getResponse().error.code==='CONSENT_REQUIRED');
  const fallback=await api.handle('GET','/legal/documents',{},undefined,undefined,{country:'KZ',locale:'be',required:'true'});assert.equal(fallback.items[0].id,document.id);assert.equal(fallback.items[0].locale,'ru');
  const consent=accepted=>command('POST','/me/consents',{document_id:document.id,document_hash:document.hash,accepted});
  await consent(true);await consent(false);
  await assert.rejects(publish,error=>error.getResponse().error.code==='CONSENT_REQUIRED');
  assert.equal((await command('GET','/me/privacy-requests')).items.length,0);
  await consent(true);assert.equal((await publish()).status,'open');
 }finally{await api.store.close();}
});
