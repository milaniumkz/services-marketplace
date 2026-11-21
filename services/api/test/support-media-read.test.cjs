const {test}=require('node:test'),assert=require('node:assert/strict'),{randomUUID}=require('node:crypto'),{mkdtemp,rm}=require('node:fs/promises'),{join}=require('node:path'),{tmpdir}=require('node:os'),sharp=require('sharp');
const {Marketplace}=require('../dist/marketplace'),{Store}=require('../dist/store'),{Providers}=require('../dist/providers'),{PrivateFiles}=require('../dist/private-files');
test('support photos work in both directions; staff read receipts persist, are personal, and new messages become unread',async()=>{
 const dir=await mkdtemp(join(tmpdir(),'joba-support-media-')),providers=new Providers();providers.scanner={scan:async()=> 'clean'}; // Isolated upload scanner fixture only.
 const api=new Marketplace(new Store('memory://'),providers,new PrivateFiles(dir));await api.initialize();const password='Support media isolated password!';
 const call=(u,m,p,b={},q={})=>api.handle(m,p,b,u?'Bearer '+u.access_token:undefined,randomUUID(),q);
 const register=phone=>call(null,'POST','/auth/register',{phone,country:'KZ',password});
 try{
 const user=await register('+77000006901'),stranger=await register('+77000006902');async function staff(phone,permissions){const s=await register(phone);await api.store.put({...await api.store.get(s.user.id),staff_permissions:permissions});return call(null,'POST','/auth/staff-login',{country:'KZ',phone,password});}
 const owner=await staff('+77000006903',['platform_owner']),agent=await staff('+77000006904',['support']);
 const bytes=await sharp({create:{width:12,height:10,channels:3,background:'#245bdb'}}).png().toBuffer();
 const upload=async actor=>{const u=await call(actor,'POST','/uploads/initiate',{purpose:'chat',mime:'image/png',size:bytes.length});await call(actor,'PUT','/uploads/'+u.id+'/content',bytes);return call(actor,'POST','/uploads/'+u.id+'/finalize');};
 const photo=await upload(user);assert.equal(photo.status,'clean');const thread=await call(user,'POST','/support/threads',{subject:'Скриншот неисправности',text:'Посмотрите снимок экрана',upload_ids:[photo.id]});
 let t=await api.store.get(thread.id);await call(owner,'POST','/admin/support-threads/'+t.id+'/commands',{command:'assign',expected_version:t.version});
 const list=async actor=>(await call(actor,'GET','/admin/support-threads')).items.find(x=>x.id===thread.id);assert.equal((await list(owner)).unread_count,1);assert.equal((await list(owner)).is_read,false);
 await call(owner,'POST','/admin/support-threads/'+t.id+'/read',{sequence:1});assert.equal((await list(owner)).is_read,true);assert.equal((await list(agent)).is_read,false);
 await assert.rejects(()=>call(user,'POST','/admin/support-threads/'+t.id+'/read',{sequence:1}),e=>e.getStatus()===403);
 const adminPhoto=await upload(owner),body={text:'',client_message_id:randomUUID(),upload_ids:[adminPhoto.id]};const reply=await call(owner,'POST','/admin/support-threads/'+t.id+'/messages',body);assert.equal((await call(owner,'POST','/admin/support-threads/'+t.id+'/messages',body)).id,reply.id);
 assert.deepEqual((await call(user,'GET','/support/threads/'+t.id+'/messages')).items.find(x=>x.id===reply.id).upload_ids,[adminPhoto.id]);
 const received=await call(user,'GET','/uploads/'+adminPhoto.id+'/download');assert.ok(received.download_buffer.length);await assert.rejects(()=>call(stranger,'GET','/uploads/'+adminPhoto.id+'/download'),e=>[403,404].includes(e.getStatus()));await assert.rejects(()=>call(user,'POST','/support/threads/'+t.id+'/messages',{text:'Чужой файл',client_message_id:randomUUID(),upload_ids:[adminPhoto.id]}),e=>[403,404].includes(e.getStatus()));
 const next=await call(user,'POST','/support/threads/'+t.id+'/messages',{text:'Ещё один вопрос',client_message_id:randomUUID()});assert.equal((await list(owner)).unread_count,1);
 const newer=await call(user,'POST','/support/threads/'+t.id+'/messages',{text:'Новое во время чтения',client_message_id:randomUUID()});await call(owner,'POST','/admin/support-threads/'+t.id+'/read',{sequence:next.sequence});assert.equal((await list(owner)).unread_count,1);
 assert.equal((await call(owner,'GET','/me/notifications',{}, {read:'unread'})).items.filter(n=>n.target_id===t.id).length,1);
 await call(owner,'POST','/admin/support-threads/'+t.id+'/read',{sequence:newer.sequence});assert.equal((await list(owner)).is_read,true);assert.equal((await call(owner,'GET','/admin/support-threads',{}, {read:'unread'})).items.some(x=>x.id===t.id),false);assert.equal((await call(owner,'GET','/me/notifications',{}, {read:'unread'})).items.some(n=>n.target_id===t.id),false);
 await assert.rejects(()=>call(owner,'POST','/admin/support-threads/'+t.id+'/read',{sequence:newer.sequence+1}),e=>e.getStatus()===422);
 }finally{await api.store.close();await rm(dir,{recursive:true,force:true});}
});
