const {test}=require('node:test'),assert=require('node:assert/strict'),{randomUUID}=require('node:crypto');
const {mkdtemp,rm}=require('node:fs/promises'),{join}=require('node:path'),{tmpdir}=require('node:os');
const {Marketplace}=require('../dist/marketplace'),{Store}=require('../dist/store'),{PrivateFiles}=require('../dist/private-files'),{Providers}=require('../dist/providers');
const {verificationPages,verificationPhotoLayout,refreshVerificationWording}=require('../dist/verification-pages');
const {bootstrapStaff}=require('../dist/staff-bootstrap'),{publishRoleAccess}=require('../../../scripts/publish-role-access.cjs'),sharp=require('sharp');
test('Russia/Belarus passport spread and Kyrgyz ID/passport work through private submission and approved selfie avatar',async()=>{
 const directory=await mkdtemp(join(tmpdir(),'joba-passport-')),api=new Marketplace(new Store('memory://'),new Providers(),new PrivateFiles(directory));await api.initialize();try{
 await publishRoleAccess(api.store);await refreshVerificationWording(api.store);await refreshVerificationWording(api.store);await bootstrapStaff(api.store,api.files,{country:'KZ',identifier:'passport-reviewer',display_name:'Проверяющий',password:'Country review password 123',authentication:'password',permissions:['platform_owner'],reason:'Country document regression'},async()=>{});
 const staff=await api.handle('POST','/auth/staff-login',{country:'KZ',phone:'passport-reviewer',password:'Country review password 123'});
 for(const[country,phone]of [['RU','+79161234567'],['BY','+375291234567'],['KG','+996700123456']]){
  const session=await api.handle('POST','/auth/register',{country,phone,password:'Country document password123'},undefined,randomUUID(),{},randomUUID());
  const call=(m,p,b={})=>api.handle(m,p,b,'Bearer '+session.access_token,randomUUID(),{},randomUUID());
  const policy=(await call('GET','/me/verification')).policy;
  assert.deepEqual(policy.document_types,country==='KG'?['id_card','passport']:['passport']);
  assert.equal(policy.required_pages.passport.length,2);assert.ok((await api.store.get(policy.document_id)).content.includes(country==='KG'?'ID-карты':'разворота паспорта'));assert.equal((await api.store.all('legal_revision',country)).length,1);
  if(country==='KG')assert.equal(policy.required_pages.id_card.length,3);
  const doc=await api.store.get(policy.document_id);await call('POST','/me/consents',{document_id:doc.id,document_hash:doc.hash,accepted:true});
  if(country!=='KG')await assert.rejects(()=>call('POST','/me/verification-sessions',{document_type:'id_card'}),e=>e.getResponse().error.code==='VALIDATION_ERROR');
  const v=await call('POST','/me/verification-sessions',{document_type:'passport'});assert.equal(v.selfie_index,1);
  const ids=[];for(const background of ['#ff0000','#00ff00']){const bytes=await sharp({create:{width:16,height:24,channels:3,background}}).jpeg().toBuffer();const upload=await call('POST','/uploads/initiate',{purpose:'identity',verification_id:v.id,mime:'image/jpeg',size:bytes.length});await api.files.write(upload.id,bytes);await api.store.put({...upload,status:'clean'});ids.push(upload.id);}
  const sent=await call('POST','/me/verification-sessions/'+v.id+'/submit',{expected_version:1,upload_ids:ids});assert.equal(sent.status,'pending_review');
  await api.handle('POST','/admin/verifications/'+v.id+'/decision',{expected_version:sent.version,document_revision:sent.document_revision,decision:'passed',reason:'Проверены паспорт и селфи'},'Bearer '+staff.access_token,randomUUID(),{admin_country:country});
  const me=await call('GET','/me');assert.equal(me.verification,'passed');const avatar=await api.store.get(me.avatar_id);assert.equal(avatar.derived_from,ids[1]);assert.equal(avatar.purpose,'avatar');
 }
 assert.deepEqual(verificationPages({},'id_card','KZ'),['Лицевая сторона удостоверения','Обратная сторона удостоверения','Селфи']);
 assert.deepEqual(verificationPhotoLayout({document_type:'id_card',required_pages:['Front','Back','Selfie'],selfie_index:2}),{count:3,selfie:2});
 assert.equal(verificationPhotoLayout({document_type:'id_card',required_pages:['Front','Selfie'],selfie_index:1}),null);
 }finally{await api.store.close();await rm(directory,{recursive:true,force:true});}
});
test('passport-only and optional video reviews keep their images private after approval',async()=>{
 const directory=await mkdtemp(join(tmpdir(),'joba-manual-passport-')),api=new Marketplace(new Store('memory://'),new Providers(),new PrivateFiles(directory));await api.initialize();try{
 await publishRoleAccess(api.store);await refreshVerificationWording(api.store);
 await bootstrapStaff(api.store,api.files,{country:'KZ',identifier:'manual-passport-reviewer',display_name:'Проверяющий',password:'Manual review password123',authentication:'password',permissions:['platform_owner'],reason:'Manual passport review regression'},async()=>{});
 const staff=await api.handle('POST','/auth/staff-login',{country:'KZ',phone:'manual-passport-reviewer',password:'Manual review password123'});
 for(const video of [false,true]){
 const user=await api.handle('POST','/auth/register',{country:'RU',phone:video?'+79161234569':'+79161234568',password:'Manual passport password123'},undefined,randomUUID(),{},randomUUID());const call=(m,p,b={})=>api.handle(m,p,b,'Bearer '+user.access_token,randomUUID(),{},randomUUID());
 const policy=(await call('GET','/me/verification')).policy,doc=await api.store.get(policy.document_id);await call('POST','/me/consents',{document_id:doc.id,document_hash:doc.hash,accepted:true});
 const v=await call('POST','/me/verification-sessions',{document_type:'passport',...(video?{video_selfie:true}:{document_only:true})});assert.equal(v.selfie_index,video?1:null);assert.equal(v.required_pages.length,video?2:1);
 if(video){assert.equal(v.required_pages[1],'Кадр видеоидентификации');assert.ok(v.video_selfie_consent_at);}
 const uploads=[];for(const background of (video?['#ff0000','#00ff00']:['#ff0000'])){const bytes=await sharp({create:{width:16,height:24,channels:3,background}}).jpeg().toBuffer();const upload=await call('POST','/uploads/initiate',{purpose:'identity',verification_id:v.id,mime:'image/jpeg',size:bytes.length});await api.files.write(upload.id,bytes);await api.store.put({...upload,status:'clean'});uploads.push(upload.id);}
 const sent=await call('POST','/me/verification-sessions/'+v.id+'/submit',{expected_version:1,upload_ids:uploads});const review=confirmed=>api.handle('POST','/admin/verifications/'+v.id+'/decision',{expected_version:sent.version,document_revision:sent.document_revision,decision:'passed',document_check_confirmed:confirmed},'Bearer '+staff.access_token,randomUUID(),{admin_country:'RU'});
 if(!video)await assert.rejects(()=>review(false),e=>e.getResponse().error.code==='DOCUMENT_CHECK_REQUIRED');await review(true);const me=await call('GET','/me');assert.equal(me.verification,'passed');assert.equal(me.avatar_id??null,null);assert.equal((await api.store.all('upload','RU')).filter(u=>u.purpose==='avatar').length,0);
 }
 }finally{await api.store.close();await rm(directory,{recursive:true,force:true});}
});
