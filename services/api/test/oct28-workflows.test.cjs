const {test}=require('node:test'),assert=require('node:assert/strict'),{randomUUID}=require('node:crypto');
const {Store}=require('../dist/store'),{Marketplace}=require('../dist/marketplace'),{migrateIdentityValidity}=require('../dist/identity-validity');
const {mkdtemp,rm}=require('node:fs/promises'),{join}=require('node:path'),{tmpdir}=require('node:os');
const {PrivateFiles}=require('../dist/private-files'),{Providers}=require('../dist/providers'),{bootstrapStaff}=require('../dist/staff-bootstrap');
const {publishRoleAccess}=require('../../../scripts/publish-role-access.cjs'),{paidCustomer}=require('./paid-customer-fixture.cjs');
const row=(kind,owner,data={})=>({id:randomUUID(),kind,owner,country:'KZ',version:1,created_at:new Date().toISOString(),...data});
test('indefinite identity migration restores only a previously approved automatic expiry, never a revoked consent or newer rejection',async()=>{
 const s=new Store('memory://');await s.initialize();try{
 const document=row('legal_document','system',{status:'published',hash:'proof'});await s.put(document);const policy=row('verification_policy','system',{status:'effective',payload:{document_id:document.id}});await s.put(policy);
 const cases=[];
 for(const mode of ['expired','passed','consent_revoked','newer_rejection','not_approved']){
  const owner=randomUUID();await s.put(row('user',owner,{id:owner,status:'active',verification:mode==='passed'?'passed':'expired'}));await s.put(row('consent',owner,{document_id:document.id,document_hash:'proof',accepted:mode!=='consent_revoked',sequence:1}));
  const record=row('verification',owner,{status:mode==='passed'?'passed':'expired',decided_at:'2026-10-27T10:00:00.000Z',expires_at:'2026-10-27T16:29:00.000Z',reviewer_id:mode==='not_approved'?undefined:'reviewer',policy_id:policy.id,document_refs:['existing-private-ref']});await s.put(record);cases.push({mode,owner,record});
  if(mode==='newer_rejection')await s.put(row('verification',owner,{status:'rejected',decided_at:'2026-10-28T10:00:00.000Z'}));
 }
 const result=await migrateIdentityValidity(s,'KZ');assert.deepEqual(result,{changed:2,restored:1});
 for(const {mode,owner,record} of cases){const current=await s.get(record.id);if(['expired','passed'].includes(mode)){assert.equal(current.status,'passed');assert.equal(current.expires_at,null);assert.equal(current.previous_expires_at,record.expires_at);assert.deepEqual(current.document_refs,record.document_refs);assert.equal((await s.get(owner)).verification,'passed');}else{assert.deepEqual(current,JSON.parse(JSON.stringify(record)));assert.equal((await s.get(owner)).verification,'expired');}}
 assert.deepEqual(await migrateIdentityValidity(s,'KZ'),{changed:0,restored:0});assert.equal((await s.all('audit','KZ')).filter(x=>x.action==='verification.validity_migrated').length,2);
 }finally{await s.close();}
});
test('documents then content can enter separate queues without a paid plan; identity approval is indefinite and can only be manually revoked',async()=>{
 const dir=await mkdtemp(join(tmpdir(),'joba-independent-')),a=new Marketplace(new Store('memory://'),new Providers(),new PrivateFiles(dir));await a.initialize();try{
 await publishRoleAccess(a.store);await bootstrapStaff(a.store,a.files,{country:'KZ',identifier:'independent-owner',display_name:'Проверка',password:'Independent test password!',authentication:'password',permissions:['platform_owner'],reason:'Изолированный сценарий проверки'},async()=>{});
 const staff=await a.handle('POST','/auth/staff-login',{country:'KZ',phone:'independent-owner',password:'Independent test password!'});
 const user=await a.handle('POST','/auth/register',{country:'KZ',phone:'+77000000981',password:'Independent user password!'});
 const call=(m,p,b={},u=user)=>a.handle(m,p,b,'Bearer '+u.access_token,randomUUID());
 const me=await call('GET','/me');await call('PATCH','/me',{expected_version:me.version,roles:['customer','executor'],active_role:'executor'});
 const profile=await call('PUT','/me/contractor-profile',{title:'Штукатурные работы',description:'Качественная штукатурка стен, опыт работы пять лет.',city:'Алматы',category_id:'1'});
 await assert.rejects(()=>call('POST','/me/contractor-profile/publish',{expected_version:profile.version}),e=>e.getResponse().error.code==='VERIFICATION_SUBMISSION_REQUIRED');
 const policy=(await call('GET','/me/verification')).policy,document=await a.store.get(policy.document_id);await call('POST','/me/consents',{document_id:document.id,document_hash:document.hash,accepted:true});
 const session=await call('POST','/me/verification-sessions',{document_type:'id_card'});const bytes=await require('sharp')({create:{width:24,height:32,channels:3,background:'green'}}).jpeg().toBuffer(),ids=[];
 for(let i=0;i<3;i++){const file=row('upload',user.user.id,{purpose:'identity',verification_id:session.id,status:'clean',mime:'image/jpeg',size:bytes.length});await a.files.write(file.id,bytes);await a.store.put(file);ids.push(file.id);}
 const sent=await call('POST','/me/verification-sessions/'+session.id+'/submit',{expected_version:session.version,upload_ids:ids});
 const queued=await call('POST','/me/contractor-profile/publish',{expected_version:profile.version});assert.equal(queued.status,'pending_review');
 const photo=row('upload',user.user.id,{purpose:'portfolio',status:'clean',mime:'image/jpeg',size:bytes.length});await a.store.put(photo);
 const portfolio=await call('POST','/me/portfolio-projects',{title:'Отделка квартиры',description:'Описание работ',category_id:'1',rights_confirmed:true});const edited=await call('PATCH','/me/portfolio-projects/'+portfolio.id,{expected_version:portfolio.version,upload_ids:[photo.id]});assert.equal((await call('POST','/me/portfolio-projects/'+portfolio.id+'/submit',{expected_version:edited.version})).status,'pending_review');
 await assert.rejects(()=>call('POST','/admin/contractors/'+profile.id+'/decision',{expected_version:queued.version,decision:'approve',reason:'Материал просмотрен сотрудником'},staff),e=>e.getResponse().error.code==='VERIFICATION_REQUIRED');
 const approved=await call('POST','/admin/verifications/'+session.id+'/decision',{expected_version:sent.version,document_revision:sent.document_revision,decision:'passed',expires_at:'2026-10-28T01:00:00.000Z',reason:'Фотографии проверены сотрудником'},staff);assert.equal(approved.expires_at,null);assert.equal(approved.validity_policy,'until_revoked');await assert.rejects(()=>call('POST','/me/verification-sessions',{document_type:'id_card'}),e=>e.getResponse().error.code==='VERIFICATION_ALREADY_PASSED');
 await a.maintenance(new Date(Date.now()+400*86400000));assert.equal((await call('GET','/me')).verification,'passed');
 const revoked=await call('POST','/admin/verifications/'+session.id+'/decision',{expected_version:approved.version,document_revision:approved.document_revision,decision:'revoked',reason:'Подтверждение отозвано после ручной проверки'},staff);assert.equal(revoked.status,'revoked');assert.equal((await call('GET','/me')).verification,'revoked');
 await assert.rejects(()=>call('POST','/admin/verifications/'+session.id+'/decision',{expected_version:revoked.version,document_revision:revoked.document_revision,decision:'passed',reason:'Нельзя восстановить устаревшее решение'},staff),e=>e.getStatus()===409);
 }finally{await a.store.close();await rm(dir,{recursive:true,force:true});}
});
test('customer decides offers from chat, all affected participants get notifications and unread counts track only their authorized threads',async()=>{
 const a=new Marketplace(new Store('memory://'));await a.initialize();try{
 const register=phone=>a.handle('POST','/auth/register',{country:'KZ',phone,password:'Chat actions test password!'},undefined,randomUUID());
 const customer=await register('+77000000982'),workers=[];await paidCustomer(a,customer);
 for(let i=0;i<3;i++){const worker=await register('+7700000098'+(3+i));workers.push(worker);await a.store.put({...await a.store.get(worker.user.id),roles:['executor'],active_role:'executor',verification:'passed'});await a.store.put(row('grant',worker.user.id,{valid_until:new Date(Date.now()+86400000).toISOString(),capabilities:['search_full','send_offer']}));}
 const call=(u,m,p,b={})=>a.handle(m,p,b,'Bearer '+u.access_token,randomUUID());
 const draft=await call(customer,'POST','/orders',{title:'Побелить стены дома',description:'Требуется побелить стены в комнатах дома.',category_id:'1',city:'Алматы',budget_amount:50000000});const order=await call(customer,'POST','/orders/'+draft.id+'/publish',{expected_version:draft.version}),offers=[];
 for(const worker of workers)offers.push(await call(worker,'POST','/orders/'+order.id+'/offers',{text:'Готов выполнить эту работу',amount:50000000,acknowledged_revision:order.revision}));
 const chat=await call(customer,'GET','/conversations/'+offers[0].conversation_id);assert.equal(chat.can_decide,true);assert.equal(chat.offer_version,offers[0].version);assert.equal((await call(workers[0],'GET','/conversations/'+chat.id)).can_decide,false);
 const message=await call(workers[0],'POST','/conversations/'+chat.id+'/messages',{text:'Здравствуйте, уточните площадь',client_message_id:randomUUID()});assert.equal((await call(customer,'GET','/me/unread-counts')).messages,1);assert.equal((await call(workers[1],'GET','/me/unread-counts')).messages,0);
 await call(customer,'POST','/conversations/'+chat.id+'/read',{sequence:message.sequence});assert.equal((await call(customer,'GET','/me/unread-counts')).messages,0);
 const secondMessage=await call(workers[0],'POST','/conversations/'+chat.id+'/messages',{text:'Уточнение перед решением',client_message_id:randomUUID()});
 await assert.rejects(()=>call(workers[0],'POST','/offers/'+offers[0].id+'/decline',{expected_version:offers[0].version,order_version:order.version}),e=>e.getStatus()===404);
 await call(customer,'POST','/offers/'+offers[0].id+'/decline',{expected_version:offers[0].version,order_version:order.version});assert.equal((await a.store.get(chat.id)).status,'closed');assert.equal((await call(customer,'GET','/me/unread-counts')).messages,1);await call(customer,'POST','/conversations/'+chat.id+'/read',{sequence:secondMessage.sequence});assert.equal((await call(customer,'GET','/me/unread-counts')).messages,0);assert.ok((await a.store.all('notification','KZ')).some(x=>x.owner===workers[0].user.id&&x.type==='offer.declined'));
 await call(customer,'POST','/orders/'+order.id+'/select',{expected_version:order.version,offer_id:offers[1].id,offer_version:offers[1].version,contact_consent:true});assert.equal((await a.store.get(offers[1].conversation_id)).status,'working');assert.equal((await a.store.get(offers[2].conversation_id)).status,'closed');
 const notices=await a.store.all('notification','KZ');assert.ok(notices.some(x=>x.owner===workers[1].user.id&&x.type==='order.selected'));assert.ok(notices.some(x=>x.owner===workers[2].user.id&&x.type==='offer.not_selected'));assert.ok(notices.some(x=>x.owner===customer.user.id&&x.type==='order.selection_confirmed'));
 const counts=await call(customer,'GET','/me/unread-counts');assert.equal(counts.notifications,notices.filter(x=>x.owner===customer.user.id&&!x.read).length);const unread=notices.find(x=>x.owner===customer.user.id&&!x.read);await call(customer,'POST','/me/notifications/'+unread.id+'/read');assert.equal((await call(customer,'GET','/me/unread-counts')).notifications,counts.notifications-1);
 }finally{await a.store.close();}
});
