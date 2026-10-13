const {test}=require('node:test');
const assert=require('node:assert/strict');
const {randomUUID}=require('node:crypto');
const {Marketplace}=require('../dist/marketplace');
const {Store}=require('../dist/store');
test('verification choices follow the effective regional policy and latest explicit consent',async()=>{
 const api=new Marketplace(new Store('memory://'));await api.initialize();
 try{
  const session=await api.handle('POST','/auth/register',{country:'KZ',phone:'+77000000090',password:'a long isolated password!',display_name:'Проверка'},undefined,undefined,{},'test');
  const call=(method,path,body={})=>api.handle(method,path,body,'Bearer '+session.access_token,randomUUID(),{},'test');
  assert.equal((await call('GET','/me/verification')).policy,null);
  const documentId=randomUUID(),policyId=randomUUID();
  await api.store.put({id:documentId,kind:'legal_document',owner:session.user.id,country:'KZ',version:1,created_at:new Date().toISOString(),status:'published',hash:'isolated-document-hash'});
  await api.store.put({id:policyId,kind:'verification_policy',owner:session.user.id,country:'KZ',version:1,created_at:new Date().toISOString(),status:'effective',payload:{document_id:documentId,document_types:['id_card'],private_note:'never public'}});
  let response=await call('GET','/me/verification');
  assert.deepEqual(response.policy,{id:policyId,version:1,document_id:documentId,document_types:['id_card'],consent_accepted:false});
  await assert.rejects(()=>call('POST','/me/verification-sessions',{document_type:'id_card'}),e=>e.getResponse().error.code==='CONSENT_REQUIRED');
  for(const [sequence,accepted] of [[1,true],[2,false],[3,true]]){
   await api.store.put({id:randomUUID(),kind:'consent',owner:session.user.id,country:'KZ',version:1,created_at:new Date().toISOString(),document_id:documentId,document_hash:'isolated-document-hash',sequence,accepted});
   assert.equal((await call('GET','/me/verification')).policy.consent_accepted,accepted);
  }
  await assert.rejects(()=>call('POST','/me/verification-sessions',{document_type:'passport'}),e=>e.getResponse().error.code==='VALIDATION_ERROR');
  assert.equal((await call('POST','/me/verification-sessions',{document_type:'id_card'})).policy_id,policyId);
  const document=await api.store.get(documentId);await api.store.put({...document,hash:'revised-document-hash',version:2});
  assert.equal((await call('GET','/me/verification')).policy.consent_accepted,false);
  await assert.rejects(()=>call('POST','/me/verification-sessions',{document_type:'id_card'}),e=>e.getResponse().error.code==='CONSENT_REQUIRED');
 }finally{await api.store.close();}
});
