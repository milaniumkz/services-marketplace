const {test}=require('node:test');
const assert=require('node:assert/strict');
const {randomUUID}=require('node:crypto');
const {Marketplace}=require('../dist/marketplace');
const {Store}=require('../dist/store');
const {Configuration}=require('../dist/configuration');
const {Providers}=require('../dist/providers');
test('verification choices follow the effective regional policy and latest explicit consent',async()=>{
 const api=new Marketplace(new Store('memory://'));await api.initialize();
 try{
  const session=await api.handle('POST','/auth/register',{country:'KZ',phone:'+77000000090',password:'a long isolated password!',display_name:'Проверка'},undefined,undefined,{},'test');
  const call=(method,path,body={})=>api.handle(method,path,body,'Bearer '+session.access_token,randomUUID(),{},'test');
  assert.equal((await call('GET','/me/verification')).policy,null);
  const documentId=randomUUID(),policyId=randomUUID();
  await api.store.put({id:documentId,kind:'legal_document',owner:session.user.id,country:'KZ',version:1,created_at:new Date().toISOString(),status:'published',hash:'isolated-document-hash'});
  await api.store.put({id:policyId,kind:'verification_policy',owner:session.user.id,country:'KZ',version:1,created_at:new Date().toISOString(),status:'effective',payload:{document_id:documentId,document_types:['id_card'],private_note:'never public'}});
  const configuration=new Configuration(api.store,new Providers()),draftPolicy=await api.store.get(policyId);
  await assert.rejects(()=>configuration.validate(draftPolicy),e=>e.getResponse().error.code==='VALIDATION_ERROR');
  assert.deepEqual(await configuration.validate({...draftPolicy,payload:{...draftPolicy.payload,required_pages:{id_card:['Лицевая сторона','Оборотная сторона']}}}),{valid:true});
  await assert.rejects(()=>configuration.validate({...draftPolicy,payload:{...draftPolicy.payload,required_pages:{id_card:['Лицевая сторона','Лицевая сторона']}}}),e=>e.getResponse().error.code==='VALIDATION_ERROR');
  let response=await call('GET','/me/verification');
  assert.deepEqual(response.policy,{id:policyId,version:1,document_id:documentId,document_types:['id_card'],required_pages:{},consent_accepted:false});
  await assert.rejects(()=>call('POST','/me/verification-sessions',{document_type:'id_card'}),e=>e.getResponse().error.code==='CONSENT_REQUIRED');
  for(const [sequence,accepted] of [[1,true],[2,false],[3,true]]){
   await api.store.put({id:randomUUID(),kind:'consent',owner:session.user.id,country:'KZ',version:1,created_at:new Date().toISOString(),document_id:documentId,document_hash:'isolated-document-hash',sequence,accepted});
   assert.equal((await call('GET','/me/verification')).policy.consent_accepted,accepted);
  }
  await assert.rejects(()=>call('POST','/me/verification-sessions',{document_type:'passport'}),e=>e.getResponse().error.code==='VALIDATION_ERROR');
  const original=await call('POST','/me/verification-sessions',{document_type:'id_card'});assert.equal(original.policy_id,policyId);
  const policy=await api.store.get(policyId);await api.store.put({...policy,version:2,payload:{...policy.payload,required_pages:{id_card:['Лицевая сторона','Оборотная сторона']}}});
  const check=await call('POST','/me/verification-sessions',{document_type:'id_card'});assert.deepEqual(check.required_pages,['Лицевая сторона','Оборотная сторона']);
  const uploads=[];for(let i=0;i<2;i++){const id=randomUUID();uploads.push(id);await api.store.put({id,kind:'upload',owner:session.user.id,country:'KZ',version:1,created_at:new Date().toISOString(),status:'clean',purpose:'identity',verification_id:check.id});}
  await assert.rejects(()=>call('POST','/me/verification-sessions/'+check.id+'/submit',{expected_version:1,upload_ids:[uploads[0]]}),e=>e.getResponse().error.code==='VALIDATION_ERROR');
  await assert.rejects(()=>call('POST','/me/verification-sessions/'+original.id+'/submit',{expected_version:1,upload_ids:uploads}),e=>e.getResponse().error.code==='POLICY_CHANGED');
  await call('POST','/me/consents',{document_id:documentId,document_hash:'isolated-document-hash',accepted:false});
  await assert.rejects(()=>call('POST','/me/verification-sessions/'+check.id+'/submit',{expected_version:1,upload_ids:uploads}),e=>e.getResponse().error.code==='CONSENT_REQUIRED');
  await call('POST','/me/consents',{document_id:documentId,document_hash:'isolated-document-hash',accepted:true});
  const sent=await call('POST','/me/verification-sessions/'+check.id+'/submit',{expected_version:1,upload_ids:uploads});assert.equal(sent.status,'pending_review');assert.deepEqual(sent.document_refs,uploads);
  const document=await api.store.get(documentId);await api.store.put({...document,hash:'revised-document-hash',version:2});
  assert.equal((await call('GET','/me/verification')).policy.consent_accepted,false);
  await assert.rejects(()=>call('POST','/me/verification-sessions',{document_type:'id_card'}),e=>e.getResponse().error.code==='CONSENT_REQUIRED');
 }finally{await api.store.close();}
});
