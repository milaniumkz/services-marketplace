const {test}=require('node:test'),assert=require('node:assert/strict'),{randomUUID,randomBytes}=require('node:crypto');
const {Marketplace}=require('../dist/marketplace'),{Store}=require('../dist/store'),{totp}=require('../dist/totp');
const password='Isolated policy editor password!';
const call=(a,u,method,path,body={})=>a.handle(method,path,body,'Bearer '+u.access_token,randomUUID());
test('document policies edit only own drafts and require published country-matched legal basis and independent publication',async()=>{
 const a=new Marketplace(new Store('memory://'));await a.initialize();
 try{
  const staff=[];for(const phone of ['+77000000841','+77000000842']){const u=await a.handle('POST','/auth/register',{country:'KZ',phone,password},undefined,randomUUID()),secret=randomBytes(20).toString('hex');await a.store.put({...await a.store.get(u.user.id),staff_permissions:['administrator'],totp_secret:secret});staff.push(await a.handle('POST','/auth/staff-login',{country:'KZ',phone,password,mfa_code:totp(secret)},undefined,randomUUID()));}
  const document={id:randomUUID(),kind:'legal_document',owner:staff[0].user.id,country:'KZ',status:'draft',version:1,created_at:new Date().toISOString(),type:'identity_consent',locale:'ru',content:'Изолированное основание для проверки контрактов политики.'};await a.store.put(document);
  const reason='Проверка версии политики документов',title='Проверка паспорта',payload={document_id:document.id,document_types:['passport'],required_pages:{passport:['Основная страница']}};
  let r=await call(a,staff[0],'POST','/admin/verification-policies',{title,reason,payload});const path='/admin/verification-policies/'+r.id;
  await assert.rejects(()=>call(a,staff[0],'POST',path+'/validate',{expected_version:1,reason}),e=>e.getResponse().error.code==='LEGAL_VERSION_UNAPPROVED');
  await a.store.put({...document,status:'published'});
  assert.equal((await call(a,staff[0],'GET',path)).id,r.id);
  await assert.rejects(()=>call(a,staff[1],'PATCH',path,{title,reason,payload,expected_version:1}),e=>e.getStatus()===409);
  r=await call(a,staff[0],'PATCH',path,{title,reason,payload:{...payload,document_types:['id_card'],required_pages:{id_card:['Лицевая сторона','Обратная сторона']}},expected_version:1});assert.equal(r.version,2);
  await assert.rejects(()=>call(a,staff[0],'PATCH',path,{title,reason,payload,expected_version:1}),e=>e.getStatus()===409);
  await assert.rejects(()=>call(a,staff[0],'POST',path+'/publish',{reason,expected_version:2}),e=>e.getStatus()===403);
  assert.equal((await call(a,staff[1],'POST',path+'/publish',{reason,expected_version:2})).status,'effective');
  await assert.rejects(()=>call(a,staff[0],'PATCH',path,{title,reason,payload,expected_version:3}),e=>e.getStatus()===409);
  let retention=await call(a,staff[0],'POST','/admin/retention-policies',{title:'Срок документов',reason,payload:{document_id:document.id,document_days:30}});
  retention=await call(a,staff[0],'PATCH','/admin/retention-policies/'+retention.id,{title:'Уточнённый срок',reason,expected_version:1,payload:{document_id:document.id,document_days:15}});assert.equal(retention.version,2);
  const preview=await call(a,staff[1],'POST','/admin/retention-policies/'+retention.id+'/preview',{reason,expected_version:2});assert.equal(preview.source_version,2);assert.equal(preview.applied,false);
  await a.store.put({...document,status:'published',country:'KG'});await assert.rejects(()=>call(a,staff[1],'POST','/admin/retention-policies/'+retention.id+'/publish',{reason,expected_version:2}),e=>e.getResponse().error.code==='LEGAL_VERSION_UNAPPROVED');
 }finally{await a.store.close();}
});
