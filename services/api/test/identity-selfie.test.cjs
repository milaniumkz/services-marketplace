const {test}=require('node:test');const assert=require('node:assert/strict');const {randomUUID}=require('node:crypto');
const {mkdtemp,rm}=require('node:fs/promises');const {join}=require('node:path');const {tmpdir}=require('node:os');
const {Marketplace}=require('../dist/marketplace'),{Store}=require('../dist/store'),{PrivateFiles}=require('../dist/private-files'),{Providers}=require('../dist/providers');
const {bootstrapStaff}=require('../dist/staff-bootstrap');const {publishRoleAccess}=require('../../../scripts/publish-role-access.cjs');
const sharp=require('sharp');
test('both roles submit three private photographs; reviewer sees labeled files and only approved selfie becomes a sanitized avatar',async()=>{
 const directory=await mkdtemp(join(tmpdir(),'joba-identity-')),api=new Marketplace(new Store('memory://'),new Providers(),new PrivateFiles(directory));await api.initialize();
 try{
  const first=await publishRoleAccess(api.store);assert.equal(first.length,4);assert.ok((await publishRoleAccess(api.store)).every(r=>r.status==='already_applied'));
  await bootstrapStaff(api.store,api.files,{country:'KZ',identifier:'identity-owner',display_name:'Проверка',password:'Isolated identity staff!',authentication:'password',permissions:['platform_owner'],reason:'Изолированная проверка фотографий'},async()=>{});
  const staff=await api.handle('POST','/auth/staff-login',{country:'KZ',phone:'identity-owner',password:'Isolated identity staff!'});
  for(const [index,role] of ['customer','executor'].entries()){
   const user=await api.handle('POST','/auth/register',{country:'KZ',phone:'+7700000072'+index,password:'Isolated identity account!'},undefined,randomUUID());
   await api.store.put({...await api.store.get(user.user.id),roles:[role],active_role:role});
   const call=(m,p,b={},q={},who=user)=>api.handle(m,p,b,'Bearer '+who.access_token,randomUUID(),q);
   const policy=(await call('GET','/me/verification')).policy;assert.equal(policy.required_pages.id_card.length,3);
   const doc=await api.store.get(policy.document_id);await call('POST','/me/consents',{document_id:doc.id,document_hash:doc.hash,accepted:true});
   const session=await call('POST','/me/verification-sessions',{document_type:'id_card'});assert.equal(session.selfie_index,2);
   const ids=[];
   for(const color of ['#ff0000','#0000ff','#00ff00']){
    const bytes=await sharp({create:{width:16,height:24,channels:3,background:color}}).jpeg().toBuffer();
    const upload=await call('POST','/uploads/initiate',{purpose:'identity',verification_id:session.id,mime:'image/jpeg',size:bytes.length});
    await api.files.write(upload.id,bytes);await api.store.put({...upload,status:'clean'});ids.push(upload.id);
   }
   await assert.rejects(()=>call('POST','/me/verification-sessions/'+session.id+'/submit',{expected_version:1,upload_ids:ids.slice(0,2)}),e=>e.getResponse().error.code==='VALIDATION_ERROR');
   const sent=await call('POST','/me/verification-sessions/'+session.id+'/submit',{expected_version:1,upload_ids:ids});assert.equal(sent.status,'pending_review');assert.equal((await call('GET','/me')).avatar_id,undefined);
   const path='/admin/verifications/'+session.id;
   await assert.rejects(()=>call('GET',path,{}, {include_documents:'true',reason:'Недопустимый самостоятельный просмотр'}),e=>e.getStatus()===403);
   const detail=await call('GET',path,{}, {include_documents:'true',reason:'Проверка двух сторон и селфи'},staff);assert.deepEqual(detail.document_refs,ids);assert.equal(detail.document_labels[2],'Селфи');
   await call('POST',path+'/decision',{expected_version:sent.version,document_revision:sent.document_revision,decision:'passed',expires_at:new Date(Date.now()+365*86400000).toISOString(),reason:'Фотографии проверены сотрудником'}, {},staff);
   const me=await call('GET','/me');assert.equal(me.verification,'passed');assert.ok(me.avatar_id);assert.equal(ids.includes(me.avatar_id),false);
   const avatar=await api.store.get(me.avatar_id);assert.equal(avatar.purpose,'avatar');assert.equal(avatar.derived_from,ids[2]);assert.equal(avatar.status,'clean');
   const data=await api.files.read(avatar.id),metadata=await sharp(data).metadata(),stats=await sharp(data).stats();assert.equal(metadata.width,512);assert.equal(metadata.height,512);assert.equal(metadata.exif,undefined);assert.ok(stats.dominant.g>stats.dominant.r);
   assert.equal((await call('GET','/me/verification')).items[0].document_refs,undefined);
   await call('POST','/me/consents',{document_id:doc.id,document_hash:doc.hash,accepted:false});
   const revoked=await call('GET','/me');assert.equal(revoked.verification,'not_started');assert.equal(revoked.avatar_id,null);
  }
 }finally{await api.store.close();await rm(directory,{recursive:true,force:true});}
});
