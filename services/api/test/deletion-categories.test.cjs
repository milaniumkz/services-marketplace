const {test}=require('node:test'),assert=require('node:assert/strict'),{randomUUID}=require('node:crypto');
const {mkdtemp,rm}=require('node:fs/promises'),{join}=require('node:path'),{tmpdir}=require('node:os');
const {Marketplace}=require('../dist/marketplace'),{Store}=require('../dist/store'),{PrivateFiles}=require('../dist/private-files');
const {validateRetentionCategories}=require('../dist/deletion-plan');
const password='Isolated deletion category password!';
const row=(kind,owner,data={})=>({id:randomUUID(),kind,owner,country:'KZ',version:1,created_at:new Date().toISOString(),...data});
test('deletion preview classifies actual scoped records and missing financial policy without borrowing document deadlines',async()=>{
 const a=new Marketplace(new Store('memory://'));await a.initialize();try{
  const u=await a.handle('POST','/auth/register',{country:'KZ',phone:'+77000000951',password},undefined,randomUUID());const owner=u.user.id;
  await a.store.put(row('retention_policy','system',{status:'effective',payload:{document_days:30,chat_days:365,security_days:90,logs_days:30}}));
  await a.store.put(row('upload',owner,{purpose:'identity',status:'clean'}));
  await a.store.put(row('payment_transaction',owner,{amount_minor:100,currency:'KZT'}));await a.store.put(row('order',owner,{status:'completed'}));await a.store.put(row('order','other',{status:'completed',executor_id:owner}));await a.store.put(row('future_private_record',owner,{private_field:'not exposed'}));await a.store.put(row('foreign_private_record',owner,{country:'KG'}));
  const result=await a.handle('GET','/me/deletion-preview',{},'Bearer '+u.access_token);const p=result.retention_plan;assert.equal(p.phase,'preview');assert.equal(p.fully_erased,false);assert.equal(p.categories.find(x=>x.category==='work').count,2);assert.equal(p.categories.find(x=>x.category==='work').retention_days,365);assert.equal(p.categories.find(x=>x.category==='finance').retention_days,null);assert.ok(p.missing_policy_categories.includes('finance'));assert.equal(p.unclassified_types,1);assert.equal(p.file_categories.find(x=>x.category==='identity').retention_days,30);assert.equal(JSON.stringify(result).includes('future_private_record'),false);assert.ok(p.categories.find(x=>x.category==='sessions').count>=2);
  for(const payload of [{chat_days:0},{security_days:-1},{financial_days:1.5},{audit_days:null},{logs_days:999999}])assert.throws(()=>validateRetentionCategories(payload),e=>e.getStatus()===422);assert.doesNotThrow(()=>validateRetentionCategories({document_days:30}));
 }finally{await a.store.close();}
});
test('deletion strips profile drafts and GPS, revokes capabilities, cancels exports and removes only unheld personal media',async()=>{
 const dir=await mkdtemp(join(tmpdir(),'joba-deletion-categories-')),files=new PrivateFiles(dir),a=new Marketplace(new Store('memory://'),undefined,files);await a.initialize();
 try{
  const u=await a.handle('POST','/auth/register',{country:'KZ',phone:'+77000000952',password},undefined,randomUUID()),owner=u.user.id,now=new Date();
  const file=async purpose=>{const r=row('upload',owner,{purpose,mime:'image/jpeg',status:'clean',expires_at:new Date(now.getTime()+86400000).toISOString()});await a.store.put(r);await files.write(r.id,Buffer.from('isolated file bytes'));return r;};
  const avatar=await file('avatar'),evidenceAvatar=await file('avatar'),held=await file('portfolio'),photo=await file('portfolio'),archive=await file('export');
  const previewId=randomUUID();await files.write(previewId,Buffer.from('isolated preview'));await a.store.put({...avatar,preview_file_id:previewId});
  const profile=row('contractor',owner,{status:'published',title:'Личный профиль',description:'Персональные данные',public_location:{latitude:43.25,longitude:76.91},exact_address:'Private address',gallery_ids:[held.id],draft:{title:'Private draft',public_location:{latitude:43.25,longitude:76.91}}});await a.store.put(profile);
  const portfolio=row('portfolio',owner,{status:'published',title:'Личный проект',description:'Private text',photos:[photo.id],draft:{description:'Private draft'}});await a.store.put(portfolio);
  const revision=row('content_revision',owner,{source_id:profile.id,source_kind:'contractor',content:{title:'Private historical text'}});await a.store.put(revision);
  await a.store.put(row('legal_hold','staff',{target_id:profile.id,subject_user_id:owner,fields:['gallery_ids'],status:'active',basis:'Active case file retention',review_at:new Date(now.getTime()+86400000).toISOString()}));
  const incident=row('case','reporter',{subject_user_id:owner,target_id:owner,target_type:'user',status:'new',target_snapshot:{avatar_id:evidenceAvatar.id,display_name:'Evidence stays private'}});await a.store.put(incident);
  const payment=row('payment_transaction',owner,{amount_minor:100,currency:'KZT',transaction_id:'immutable'});await a.store.put(payment);
  const ticket=row('download_ticket',owner,{upload_id:archive.id,status:'active',token_hash:'isolated-hash'}),device=row('push_token',owner,{token:'isolated-private-device',status:'active'}),exportJob=row('privacy',owner,{type:'export',status:'requested'});for(const r of [ticket,device,exportJob])await a.store.put(r);
  await a.store.put(row('retention_policy','system',{status:'effective',payload:{document_days:30,chat_days:365,security_days:90,logs_days:30}}));
  await a.store.put(row('dictionary','system',{status:'published',payload:{rules:[{type:'phrase',value:'Удалённый пользователь',surfaces:['user']}]}}));
  const request=row('privacy',owner,{type:'delete',status:'scheduled',execute_after:new Date(now.getTime()-1000).toISOString()});await a.store.put(request);await a.maintenance(now);
  assert.equal((await a.store.get(owner)).status,'deleted');assert.equal((await a.store.get(profile.id)).draft,undefined);assert.equal((await a.store.get(profile.id)).public_location,undefined);assert.equal((await a.store.get(profile.id)).exact_address,undefined);assert.deepEqual((await a.store.get(profile.id)).gallery_ids,[held.id]);assert.equal((await a.store.get(portfolio.id)).photos,undefined);assert.equal((await a.store.get(revision.id)).content,undefined);
  assert.equal((await a.store.get(ticket.id)).status,'revoked');assert.equal((await a.store.get(device.id)).token,undefined);assert.equal((await a.store.get(device.id)).status,'revoked');assert.equal((await a.store.get(exportJob.id)).status,'canceled');
  for(const r of [avatar,photo,archive]){assert.equal((await a.store.get(r.id)).status,'purged');await assert.rejects(()=>files.read(r.id),e=>e.code==='ENOENT');}
  await assert.rejects(()=>files.read(previewId),e=>e.code==='ENOENT');
  for(const r of [held,evidenceAvatar]){assert.equal((await a.store.get(r.id)).status,'clean');assert.equal((await files.read(r.id)).toString(),'isolated file bytes');}
  assert.deepEqual(await a.store.get(payment.id),payment);assert.deepEqual(await a.store.get(incident.id),incident);assert.equal((await a.store.all('case','KZ')).length,1);
  const result=await a.store.get(request.id);assert.equal(result.status,'limited_retention');assert.equal(result.retention_review_at,undefined);assert.equal(result.retention_plan.phase,'account_removed');assert.equal(result.retention_plan.fully_erased,false);assert.ok(result.retention_plan.missing_policy_categories.includes('finance'));assert.equal(result.retention_plan.active_holds,1);
  await assert.rejects(()=>a.handle('GET','/me',{},'Bearer '+u.access_token),e=>e.getStatus()===401);await a.maintenance(now);assert.equal((await a.store.get(owner)).status,'deleted');
 }finally{await a.store.close();await rm(dir,{recursive:true,force:true});}
});
test('an in-flight scanner cannot recreate personal files after account deletion',async()=>{
 const dir=await mkdtemp(join(tmpdir(),'joba-scan-delete-')),files=new PrivateFiles(dir),a=new Marketplace(new Store('memory://'),undefined,files);await a.initialize();
 let release,task;const gate=new Promise(resolve=>release=resolve);let entered;const started=new Promise(resolve=>entered=resolve);
 try{
  const u=await a.handle('POST','/auth/register',{country:'KZ',phone:'+77000000953',password},undefined,randomUUID()),now=new Date();
  a.providers.scanner={scan:async()=>{entered();await gate;return 'clean';}};
  const image=await require('sharp')({create:{width:12,height:12,channels:3,background:'#123456'}}).jpeg().toBuffer();
  const upload=row('upload',u.user.id,{purpose:'avatar',mime:'image/jpeg',status:'processing'});await a.store.put(upload);await files.write(upload.id,image);
  task=a.processUpload(upload.id);await started;
  await a.store.put(row('retention_policy','system',{status:'effective',payload:{document_days:30}}));
  await a.store.put(row('privacy',u.user.id,{type:'delete',status:'scheduled',execute_after:new Date(now.getTime()-1000).toISOString()}));
  await a.maintenance(now);assert.equal((await a.store.get(upload.id)).status,'purged');
  let writes=0;const original=files.write.bind(files);files.write=async(...args)=>{writes++;return original(...args);};release();await task;
  assert.equal(writes,0);assert.equal((await a.store.get(upload.id)).status,'purged');await assert.rejects(()=>files.read(upload.id),e=>e.code==='ENOENT');
 }finally{release();if(task)await task;await a.store.close();await rm(dir,{recursive:true,force:true});}
});
