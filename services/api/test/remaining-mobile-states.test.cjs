const {test}=require('node:test');
const assert=require('node:assert/strict');
const {randomUUID}=require('node:crypto');
const {Store}=require('../dist/store');
const {Marketplace}=require('../dist/marketplace');
const fixture=()=>new Marketplace(new Store('memory://'));
const record=(kind,owner,extra={})=>({id:randomUUID(),kind,owner,country:'KZ',version:1,created_at:new Date().toISOString(),...extra});
const password='Isolated mobile states password!';
const reg=(a,n)=>a.handle('POST','/auth/register',{country:'KZ',phone:'+77000000'+n,password},undefined,randomUUID(),{},'mobile-states');
const call=(a,u,m,p,b={},q={})=>a.handle(m,p,b,'Bearer '+u.access_token,randomUUID(),q,'mobile-states');
test('deletion has a cancellable scheduled window, blocks active work and deduplicates requests; optional consents need an actual published policy',async()=>{
 const a=fixture();await a.initialize();try{
  const u=await reg(a,'741'),owner=u.user.id;
  const legal=record('legal_document',owner,{status:'published',type:'privacy',locale:'ru',hash:'isolated-hash',published_at:new Date().toISOString()});await a.store.put(legal);
  const policy=record('retention_policy',owner,{status:'effective',payload:{document_id:legal.id,document_days:30}});await a.store.put(policy);
  const prefs=await call(a,u,'POST','/me/processing-consents',{marketing:true,ad_personalization:false,optional_analytics:false,expected_version:0});assert.equal(prefs.document_id,legal.id);assert.equal((await call(a,u,'GET','/me/processing-consents')).marketing,true);
  await assert.rejects(()=>call(a,u,'POST','/me/processing-consents',{marketing:false,ad_personalization:false,optional_analytics:false,expected_version:0}),e=>e.getStatus()===409);
  let r=await call(a,u,'POST','/me/privacy-requests',{type:'delete',current_password:password});assert.equal((await call(a,u,'POST','/me/privacy-requests',{type:'delete',current_password:password})).id,r.id);
  await a.maintenance();r=await call(a,u,'GET','/me/privacy-requests/'+r.id);assert.equal(r.status,'scheduled');assert.ok(Date.parse(r.execute_after)>Date.now());assert.equal((await call(a,u,'GET','/me')).status,'active');
  await call(a,u,'POST','/me/privacy-requests/'+r.id+'/cancel',{expected_version:r.version});await a.maintenance(new Date(Date.now()+2*86400000));assert.equal((await call(a,u,'GET','/me')).status,'active');
  r=await call(a,u,'POST','/me/privacy-requests',{type:'delete',current_password:password});await a.maintenance();
  const order=record('order',owner,{status:'assigned',executor_id:randomUUID()});await a.store.put(order);
  await a.maintenance(new Date(Date.now()+2*86400000));assert.equal((await a.store.get(r.id)).status,'awaiting_resolution');assert.equal((await call(a,u,'GET','/me/deletion-preview')).active_orders,1);
 }finally{await a.store.close();}
});
test('work-state details are participant-only, amendments preserve date proposals until accepted and frozen chats reject sends',async()=>{
 const a=fixture();await a.initialize();try{
  const u=await reg(a,'742'),v=await reg(a,'743'),stranger=await reg(a,'744');
  const order=record('order',u.user.id,{status:'assigned',title:'Изолированный заказ',description:'Достаточно подробное описание изолированного заказа.',executor_id:v.user.id,revision:1});await a.store.put(order);
  const window={start_date:'2027-01-01',end_date:'2027-01-01',time_zone:'Asia/Almaty'};
  const change=await call(a,u,'POST','/orders/'+order.id+'/amendments',{expected_version:1,amount:50000,description:order.description,reason:'Изменить дату и стоимость',time_window:window});
  assert.equal((await a.store.get(order.id)).time_window,undefined);assert.equal((await call(a,v,'GET','/amendments/'+change.id)).time_window.start_date,'2027-01-01');
  await assert.rejects(()=>call(a,stranger,'GET','/amendments/'+change.id),e=>e.getStatus()===404);
  await call(a,v,'POST','/amendments/'+change.id+'/respond',{expected_version:1,decision:'accept'});assert.equal((await a.store.get(order.id)).time_window.start_date,'2027-01-01');
  const c=record('conversation',u.user.id,{members:[u.user.id,v.user.id],order_id:order.id,status:'frozen'});await a.store.put(c);assert.equal((await call(a,u,'GET','/conversations/'+c.id)).blocked,true);
  await assert.rejects(()=>call(a,v,'POST','/conversations/'+c.id+'/messages',{text:'Не должно отправиться',client_message_id:randomUUID()}),e=>e.getStatus()===409);
 }finally{await a.store.close();}
});
test('provider pending evidence creates no entitlement; client reward completion cannot grant access',async()=>{
 const a=fixture();await a.initialize();try{
  const u=await reg(a,'745'),owner=u.user.id;
  await a.store.put(record('price_version',owner,{status:'effective',payload:{provider:'isolated',product_id:'monthly',product_type:'subscription',amount_minor:100,currency:'KZT'}}));
  const proof={provider:'isolated',transaction_id:'isolated-transaction',original_transaction_id:'isolated-original',user_id:owner,country:'KZ',product_id:'monthly',environment:'sandbox',amount_minor:100,currency:'KZT',valid_until:new Date(Date.now()+86400000).toISOString(),revision:1,state:'pending'};
  a.providers.billing.set('isolated',{name:'isolated',verifyPurchase:async()=>proof});
  const result=await call(a,u,'POST','/billing/verify-purchase',{provider:'isolated',transaction_reference:'isolated-receipt'});assert.equal(result.pending,true);assert.equal((await a.store.all('grant','KZ')).length,0);
  const safe=await call(a,u,'GET','/me/purchase-checks/'+result.check.id);assert.equal(safe.transaction_id,undefined);
  proof.state='active';proof.revision=2;await call(a,u,'POST','/billing/verify-purchase',{provider:'isolated',transaction_reference:'isolated-receipt'});assert.equal((await call(a,u,'GET','/me/purchase-checks/'+result.check.id)).status,'confirmed');assert.equal((await a.store.all('grant','KZ')).length,1);
  const reward=record('ad_session',owner,{status:'pending'});await a.store.put(reward);
  await call(a,u,'POST','/ads/reward-sessions/'+reward.id+'/outcome',{outcome:'completed'});assert.equal((await call(a,u,'GET','/ads/reward-sessions/'+reward.id)).grant,null);
 }finally{await a.store.close();}
});
test('map exposes only eligible rounded public service areas and applies distance before limit',async()=>{
 const a=fixture();await a.initialize();try{
  const u=await reg(a,'746'),v=await reg(a,'747');await a.store.put({...await a.store.get(v.user.id),verification:'passed'});
  await a.store.put(record('grant',u.user.id,{valid_until:new Date(Date.now()+86400000).toISOString(),capabilities:['search_full']}));
  const near=record('contractor',v.user.id,{status:'published',public_location:{latitude:43.24,longitude:76.91,approximate:true},title:'Профиль на карте'});await a.store.put(near);
  await a.store.put({...near,id:randomUUID(),public_location:{latitude:50,longitude:80,approximate:true}});
  const result=await call(a,u,'GET','/contractors/map',{}, {near_lat:43.24,near_lon:76.91,radius_km:5});assert.equal(result.items.length,1);assert.equal(result.items[0].id,near.id);
  await a.store.put({...near,moderation_status:'hidden'});assert.equal((await call(a,u,'GET','/contractors/map',{}, {near_lat:43.24,near_lon:76.91,radius_km:5})).items.length,0);
 }finally{await a.store.close();}
});
test('portfolio square crop creates an owned private derivative and rejects another account',async()=>{
 const {mkdtemp,rm}=require('node:fs/promises'),{join}=require('node:path'),{tmpdir}=require('node:os');
 const sharp=require('sharp'),{PrivateFiles}=require('../dist/private-files'),{Providers}=require('../dist/providers');
 const dir=await mkdtemp(join(tmpdir(),'joba-crop-')),files=new PrivateFiles(dir),a=new Marketplace(new Store('memory://'),new Providers(),files);await a.initialize();try{
  const u=await reg(a,'748'),v=await reg(a,'749');const bytes=await sharp({create:{width:80,height:40,channels:3,background:'#245bdb'}}).png().toBuffer();
  const source=record('upload',u.user.id,{purpose:'portfolio',status:'clean',mime:'image/png',size:bytes.length});await files.write(source.id,bytes);await a.store.put(source);
  await assert.rejects(()=>call(a,v,'POST','/uploads/'+source.id+'/crop',{mode:'square'}),e=>e.getStatus()===404);
  const cropped=await call(a,u,'POST','/uploads/'+source.id+'/crop',{mode:'square'});assert.notEqual(cropped.id,source.id);assert.equal(cropped.owner,u.user.id);assert.equal(cropped.derived_from,source.id);
  const meta=await sharp(await files.read(cropped.id)).metadata();assert.equal(meta.width,40);assert.equal(meta.height,40);assert.equal(meta.format,'jpeg');
 }finally{await a.store.close();await rm(dir,{recursive:true,force:true});}
});
test('offer revision edits and acknowledgement commit together and reject a stale revision without mutation',async()=>{
 const a=fixture();await a.initialize();try{
  const u=await reg(a,'750'),v=await reg(a,'751');await a.store.put({...await a.store.get(u.user.id),verification:'passed',roles:['customer','executor']});
  await a.store.put(record('grant',u.user.id,{valid_until:new Date(Date.now()+86400000).toISOString(),capabilities:['send_offer']}));
  const order=record('order',v.user.id,{status:'open',revision:2,expires_at:new Date(Date.now()+86400000).toISOString()});await a.store.put(order);
  const offer=record('offer',u.user.id,{order_id:order.id,status:'active',amount:10000,text:'Исходный комментарий',acknowledged_revision:1});await a.store.put(offer);
  await assert.rejects(()=>call(a,u,'PATCH','/offers/'+offer.id,{expected_version:1,amount:20000,text:'Обновлённый комментарий',acknowledged_revision:1}),e=>e.getStatus()===409);
  assert.equal((await a.store.get(offer.id)).amount,10000);
  const updated=await call(a,u,'PATCH','/offers/'+offer.id,{expected_version:1,amount:20000,text:'Обновлённый комментарий',acknowledged_revision:2});assert.equal(updated.amount,20000);assert.equal(updated.acknowledged_revision,2);assert.equal(updated.version,2);
 }finally{await a.store.close();}
});
