const {test}=require('node:test');
const assert=require('node:assert/strict');
const {randomUUID}=require('node:crypto');
const {Marketplace}=require('../dist/marketplace');
const {Store}=require('../dist/store');
test('mobile detail ACL, portfolio order, draft editing and privacy cancellation',async()=>{
 const api=new Marketplace(new Store('memory://'));await api.initialize();
 const call=(u,m,p,b={})=>api.handle(m,p,b,u?'Bearer '+u.access_token:undefined,randomUUID(),{},'mobile-query-test');
 const register=p=>call(null,'POST','/auth/register',{country:'KZ',phone:p,password:'Isolated mobile queries password!'});
 try{
  const owner=await register('+77000000501'),other=await register('+77000000502');
  const identity=await call(owner,'GET','/me');
  const preferences=await call(owner,'PATCH','/me',{expected_version:identity.version,roles:['customer','executor'],active_role:'executor',languages:['ru','kk']});
  assert.equal(preferences.active_role,'executor');assert.deepEqual((await call(owner,'GET','/me')).languages,['ru','kk']);
  await assert.rejects(()=>call(owner,'PATCH','/me',{expected_version:preferences.version,roles:['administrator']}),e=>e.getStatus()===400);
  const order=await call(owner,'POST','/orders',{title:'Первый черновик','description':'Описание реального редактируемого черновика в изолированном тесте.',city:'Алматы',category_id:'1',budget_amount:null});
  const edited=await call(owner,'PATCH','/orders/'+order.id,{expected_version:order.version,title:'Изменённый черновик',budget_amount:25000,work_mode:'remote'});
  assert.equal(edited.budget_amount,25000);assert.equal(edited.description,order.description);assert.equal(edited.revision,order.revision+1);
  const report=await call(owner,'POST','/cases',{target_type:'order',target_id:order.id,reason_code:'other',description:'Проверка доступности обращения для владельца'});
  assert.equal((await call(owner,'GET','/cases/'+report.id)).id,report.id);
  await assert.rejects(()=>call(other,'GET','/cases/'+report.id),e=>e.getResponse().error.code==='NOT_FOUND');
  const message=await call(owner,'POST','/cases/'+report.id+'/messages',{text:'Уточнение обстоятельств обращения'});
  assert.equal((await call(owner,'GET','/cases/'+report.id+'/messages')).items[0].id,message.id);
  await assert.rejects(()=>call(other,'GET','/cases/'+report.id+'/messages'),e=>e.getStatus()===404);
  const profile=await call(owner,'PUT','/me/contractor-profile',{title:'Ремонт и обслуживание',description:'Описание услуг и опыта исполнителя для проверки настоящего профиля.',category_id:'1',city:'Алматы',work_modes:['onsite','remote'],languages:['ru','kk'],service_cities:['Алматы','Астана'],experience_years:7,travel_radius_km:25,price:{mode:'per_unit',currency:'KZT',amount_min:25000,amount_max:35000,unit:'m2'}});
  assert.equal(profile.price.amount_min,25000);assert.deepEqual(profile.languages,['ru','kk']);
  await assert.rejects(()=>call(owner,'PUT','/me/contractor-profile',{...profile,expected_version:profile.version,price:{mode:'fixed',currency:'USD',amount_min:0}}),e=>e.getStatus()===400);
  assert.equal((await call(owner,'GET','/me/contractor-profile')).profile.version,profile.version);
  const first=await call(owner,'POST','/me/portfolio-projects',{title:'Первый проект',description:'Описание проекта',category_id:'1',rights_confirmed:true});
  const second=await call(owner,'POST','/me/portfolio-projects',{title:'Второй проект',description:'Описание второго проекта',category_id:'1'});
  const body={project_ids:[second.id,first.id],expected_versions:{[first.id]:first.version,[second.id]:second.version}};
  const sorted=await call(owner,'POST','/me/portfolio-projects/reorder',body);
  assert.equal(sorted.items[0].id,second.id);assert.equal(sorted.items[0].position,0);
  await assert.rejects(()=>call(owner,'POST','/me/portfolio-projects/reorder',body),e=>e.getStatus()===409);
  await assert.rejects(()=>call(other,'POST','/me/portfolio-projects/reorder',body),e=>e.getStatus()===400);
  const request=await call(owner,'POST','/me/privacy-requests',{type:'delete',current_password:'Isolated mobile queries password!'});
  const cancelled=await call(owner,'POST','/me/privacy-requests/'+request.id+'/cancel',{expected_version:request.version});
  assert.equal(cancelled.status,'cancelled');await api.maintenance();
  assert.equal((await call(owner,'GET','/me')).status,'active');
 }finally{await api.store.close();}
});

test('published portfolio media require access, visibility and country ACL',async()=>{
 const {mkdtemp,rm}=require('node:fs/promises'),{tmpdir}=require('node:os'),{join}=require('node:path');
 const {PrivateFiles}=require('../dist/private-files'),{Providers}=require('../dist/providers');
 const files=await mkdtemp(join(tmpdir(),'joba-mobile-media-'));
 const api=new Marketplace(new Store('memory://'),new Providers(),new PrivateFiles(files));await api.initialize();
 const call=(u,m,p,b={})=>api.handle(m,p,b,u?'Bearer '+u.access_token:undefined,randomUUID(),{},'mobile-media-test');
 const register=(p,country='KZ')=>call(null,'POST','/auth/register',{country,phone:p,password:'Isolated media ACL password!'});
 try{
  const owner=await register('+77000000511'),reader=await register('+77000000512'),unpaid=await register('+77000000513'),foreign=await register('+375291234568','BY');
  await api.store.put({id:randomUUID(),kind:'grant',owner:reader.user.id,country:'KZ',version:1,created_at:new Date().toISOString(),valid_until:new Date(Date.now()+86400000).toISOString(),capabilities:['search_full'],source:'isolated_acl_fixture'});
  const image=await require('sharp')({create:{width:2,height:2,channels:3,background:'#245BDB'}}).png().toBuffer();
  const upload={id:randomUUID(),kind:'upload',owner:owner.user.id,country:'KZ',version:1,created_at:new Date().toISOString(),purpose:'portfolio',mime:'image/png',size:image.length,status:'clean',fixture:true};
  await api.store.put(upload);await api.files.write(upload.id,image);
  const category=(await call(owner,'GET','/catalog/categories')).items[0];
  const project=await call(owner,'POST','/me/portfolio-projects',{title:'Проверка публичного проекта',description:'Изолированные данные',category_id:category.id,rights_confirmed:true});
  await api.store.put({...project,status:'published',photos:[upload.id]});
  const profile={id:randomUUID(),kind:'contractor',owner:owner.user.id,country:'KZ',version:1,created_at:new Date().toISOString(),title:'Тестовый профиль',description:'Тестовая публикация для проверки файловой ACL',status:'published',fixture:true};
  await api.store.put(profile);
  assert.equal((await call(reader,'GET','/uploads/'+upload.id+'/metadata')).mime,'image/png');
  await assert.rejects(()=>call(unpaid,'GET','/uploads/'+upload.id+'/metadata'),e=>e.getResponse().error.code==='ENTITLEMENT_REQUIRED');
  await assert.rejects(()=>call(foreign,'GET','/uploads/'+upload.id+'/metadata'),e=>e.getResponse().error.code==='NOT_FOUND');
  await api.store.put({...profile,status:'draft',version:2});
  await assert.rejects(()=>call(reader,'GET','/uploads/'+upload.id+'/metadata'),e=>e.getResponse().error.code==='NOT_FOUND');
 }finally{await api.store.close();await rm(files,{recursive:true,force:true});}
});

test('chat history pages, edit tombstones and scoped read events stay consistent',async()=>{
 const api=new Marketplace(new Store('memory://'));await api.initialize();
 const call=(u,m,p,b={},q={})=>api.handle(m,p,b,u?'Bearer '+u.access_token:undefined,randomUUID(),q,'mobile-history-test');
 const reg=p=>call(null,'POST','/auth/register',{country:'KZ',phone:p,password:'Isolated history verification password!'});
 try{
  const sender=await reg('+77000000521'),reader=await reg('+77000000522'),other=await reg('+77000000523');
  const conversation={id:randomUUID(),kind:'conversation',owner:sender.user.id,country:'KZ',version:1,created_at:new Date().toISOString(),members:[sender.user.id,reader.user.id],status:'working',fixture:true};
  await api.store.put(conversation);
  const rows=[];
  for(let sequence=1;sequence<=130;sequence++){
   const row={id:randomUUID(),kind:'message',owner:sender.user.id,country:'KZ',version:1,created_at:new Date().toISOString(),thread_id:conversation.id,sequence,text:'History fixture '+sequence,upload_ids:[],fixture:true};rows.push(row);await api.store.put(row);
  }
  const path='/conversations/'+conversation.id+'/messages';
  const recent=await call(reader,'GET',path);assert.equal(recent.items.length,100);assert.equal(recent.items[0].sequence,31);assert.equal(recent.meta.has_more,true);
  const older=await call(reader,'GET',path,{}, {before_sequence:31});assert.equal(older.items.length,30);assert.equal(older.meta.has_more,false);
  await assert.rejects(()=>call(other,'GET',path),e=>e.getStatus()===404);
  const edited=await call(sender,'PATCH','/messages/'+rows[0].id,{text:'Updated real fixture',expected_version:1});
  const delta=await call(reader,'GET',path,{}, {after_sequence:130,updated_since:'1970-01-01T00:00:00.000Z'});assert.equal(delta.items.length,0);assert.equal(delta.updates[0].id,edited.id);
  await call(reader,'POST','/conversations/'+conversation.id+'/read',{sequence:130});
  const events=await call(sender,'GET','/events');assert.equal(events.items[0].type,'conversation.read');assert.equal(events.items[0].aggregate_id,conversation.id);
  assert.equal((await call(sender,'GET','/me/notifications')).items.length,0);
  await call(sender,'DELETE','/messages/'+edited.id,{expected_version:edited.version});
  const deleted=await call(reader,'GET',path,{}, {before_sequence:2});assert.equal(deleted.items[0].tombstone,true);assert.equal(deleted.items[0].text,'');
 }finally{await api.store.close();}
});

test('public search filters blocked and hidden records before cursor pagination',async()=>{
 const api=new Marketplace(new Store('memory://'));await api.initialize();
 const call=(u,m,p,b={},q={})=>api.handle(m,p,b,u?'Bearer '+u.access_token:undefined,randomUUID(),q,'search-visibility-test');
 try{
  const users=[];for(let i=0;i<4;i++)users.push(await call(null,'POST','/auth/register',{country:'KZ',phone:'+7700000060'+i,password:'Isolated search visibility password!'}));
  const [reader,blocked,hidden,visible]=users;
  for(const u of users){const account=await api.store.get(u.user.id);await api.store.put({...account,roles:['customer','executor'],verification:'passed'});}
  await api.store.put({id:randomUUID(),kind:'grant',owner:reader.user.id,country:'KZ',version:1,created_at:new Date().toISOString(),valid_until:new Date(Date.now()+86400000).toISOString(),capabilities:['search_full']});
  await call(reader,'POST','/me/blocks',{target_user_id:blocked.user.id});
  const category=(await call(reader,'GET','/catalog/categories')).items[0].id;
  const base={kind:'contractor',country:'KZ',version:1,created_at:new Date().toISOString(),title:'Проверяемая услуга',description:'Проверка видимости каталога в изолированном тесте.',city:'Алматы',category_id:category,status:'published'};
  await api.store.put({...base,id:'00000000-0000-4000-8000-000000000001',owner:blocked.user.id});
  await api.store.put({...base,id:'00000000-0000-4000-8000-000000000002',owner:hidden.user.id,moderation_status:'quarantined'});
  await api.store.put({...base,id:'00000000-0000-4000-8000-000000000003',owner:visible.user.id});
  await api.store.put({...base,id:'00000000-0000-4000-8000-000000000004',owner:visible.user.id});
  const first=await call(reader,'GET','/contractors',{}, {limit:1});assert.equal(first.items[0].id,'00000000-0000-4000-8000-000000000003');assert.ok(first.meta.next_cursor);
  const second=await call(reader,'GET','/contractors',{}, {limit:1,cursor:first.meta.next_cursor});assert.equal(second.items[0].id,'00000000-0000-4000-8000-000000000004');assert.equal(second.meta.next_cursor,null);
  await assert.rejects(()=>call(reader,'GET','/contractors/00000000-0000-4000-8000-000000000001'),e=>e.getStatus()===404);
  const order={...base,kind:'order',owner:visible.user.id,id:randomUUID(),status:'open',expires_at:new Date(Date.now()+86400000).toISOString(),exact_address:'Секретный адрес теста'};
  await api.store.put(order);await api.store.put({...order,id:randomUUID(),expires_at:new Date(Date.now()-1000).toISOString()});
  const orders=await call(reader,'GET','/orders');assert.equal(orders.items.length,1);assert.equal(orders.items[0].exact_address,undefined);
 }finally{await api.store.close();}
});
