const {test}=require('node:test'),assert=require('node:assert/strict'),{randomUUID}=require('node:crypto');
const {Marketplace}=require('../dist/marketplace'),{Store}=require('../dist/store');
const row=(kind,owner,extra={})=>({id:randomUUID(),kind,owner,country:'KZ',version:1,created_at:new Date().toISOString(),...extra});
test('unverified participants publish and choose through responses; profiles, photos, portfolios and real badges remain visible; cancellation and deletion close responses',async()=>{
 const api=new Marketplace(new Store('memory://'));await api.initialize();
 const call=(u,m,p,b={},q={})=>api.handle(m,p,b,'Bearer '+u.access_token,randomUUID(),q);
 const register=phone=>api.handle('POST','/auth/register',{country:'KZ',phone,password:'Voluntary document test password',display_name:'Участник'});
 try{
 const customer=await register('+77000000901'),executor=await register('+77000000902'),stranger=await register('+77000000903');
 for(const u of [customer,executor])await api.store.put(row('grant',u.user.id,{role:u===customer?'customer':'executor',plan:u===customer?'customer':'standard',valid_until:new Date(Date.now()+86400000).toISOString(),capabilities:u===customer?['publish_order']:['publish_profile','search_full','send_offer']}));
 const category=(await call(customer,'GET','/catalog/categories')).items[0].id;
 let profile=await call(executor,'PUT','/me/contractor-profile',{title:'Исполнитель без проверки',description:'Выполняю работы качественно и в удобное время.',city:'Астана',category_id:category});
 profile=await call(executor,'POST','/me/contractor-profile/publish',{expected_version:profile.version});
 assert.equal((await call(executor,'GET','/me')).verification,'not_started');
 const photo=await api.store.put(row('upload',executor.user.id,{purpose:'portfolio',mime:'image/jpeg',size:10,status:'clean',fixture:true}));
 let project=await call(executor,'POST','/me/portfolio-projects',{title:'Выполненные работы',description:'Описание выполненных работ',category_id:category,rights_confirmed:true});
 project=await call(executor,'PATCH','/me/portfolio-projects/'+project.id,{expected_version:project.version,upload_ids:[photo.id]});
 await call(executor,'POST','/me/portfolio-projects/'+project.id+'/submit',{expected_version:project.version});
 let draft=await call(customer,'POST','/orders',{title:'Установить новую дверь',description:'Нужно установить входную дверь в квартире.',city:'Астана',category_id:category});
 let order=await call(customer,'POST','/orders/'+draft.id+'/publish',{expected_version:draft.version});
 assert.equal(order.status,'open');assert.ok((await call(customer,'GET','/me/orders',{}, {bucket:'active'})).items.some(r=>r.id===order.id));
 assert.ok((await call(executor,'GET','/orders')).items.some(r=>r.id===order.id));
 const offer=await call(executor,'POST','/orders/'+order.id+'/offers',{text:'Готов выполнить работу',amount:120000,acknowledged_revision:order.revision});
 const shown=(await call(customer,'GET','/orders/'+order.id+'/offers')).items[0];assert.equal(shown.executor.available,true);assert.equal(shown.executor.verified,false);assert.equal(shown.executor.profile_id,profile.id);
 assert.equal((await call(customer,'GET','/contractors/'+profile.id)).verification.status,'not_started');
 assert.equal((await call(customer,'GET','/contractors/'+profile.id+'/portfolio')).items.length,1);
 assert.equal((await call(customer,'GET','/uploads/'+photo.id+'/metadata')).id,photo.id);
 assert.equal((await call(customer,'GET','/contractors',{}, {verified_only:'true'})).items.length,0);
 await api.store.put({...await api.store.get(executor.user.id),verification:'passed'});
 assert.equal((await call(customer,'GET','/orders/'+order.id+'/offers')).items[0].executor.verified,true);
 await api.store.put({...await api.store.get(executor.user.id),verification:'revoked'});
 assert.equal((await call(customer,'GET','/orders/'+order.id+'/offers')).items[0].executor.verified,false);
 order=await call(customer,'POST','/orders/'+order.id+'/select',{expected_version:order.version,offer_id:offer.id,offer_version:offer.version});assert.equal(order.status,'assigned');
 await assert.rejects(()=>call(customer,'DELETE','/orders/'+order.id,{expected_version:order.version}),e=>e.getStatus()===409);
 draft=await call(customer,'POST','/orders',{title:'Установить ещё одну дверь',description:'Нужно установить входную дверь в квартире.',city:'Астана',category_id:category});
 let second=await call(customer,'POST','/orders/'+draft.id+'/publish',{expected_version:draft.version});
 const secondOffer=await call(executor,'POST','/orders/'+second.id+'/offers',{text:'Выполню работу',amount:100000,acknowledged_revision:second.revision});
 await assert.rejects(()=>call(stranger,'DELETE','/orders/'+second.id,{expected_version:second.version}),e=>e.getStatus()===404);
 second=await call(customer,'POST','/orders/'+second.id+'/cancel',{expected_version:second.version});assert.equal(second.status,'cancelled');assert.equal((await api.store.get(secondOffer.id)).status,'not_selected');assert.equal((await api.store.get(secondOffer.conversation_id)).status,'closed');
 await call(customer,'DELETE','/orders/'+second.id,{expected_version:second.version});
 assert.ok(!(await call(customer,'GET','/me/orders')).items.some(r=>r.id===second.id));
 assert.equal((await call(customer,'GET','/me')).verification,'not_started');
 }finally{await api.store.close();}
});
test('legacy profile form rebases unrelated background updates after a photo upload but preserves true edit conflicts',async()=>{
 const api=new Marketplace(new Store('memory://'));await api.initialize();
 try{
 const u=await api.handle('POST','/auth/register',{country:'KZ',phone:'+77000000904',password:'Profile rebase test password'});
 const call=(m,p,b={})=>api.handle(m,p,b,'Bearer '+u.access_token,randomUUID());
 const category=(await call('GET','/catalog/categories')).items[0].id;
 let p=await call('PUT','/me/contractor-profile',{title:'Услуги исполнителя',description:'Описание услуг исполнителя достаточно подробное.',city:'Астана',category_id:category});
 const original=p;
 // Simulate a concurrent edit while the old app is choosing/uploading a photo.
 p=await call('PUT','/me/contractor-profile',{...p,expected_version:p.version,description:'Новое подробное описание с другого устройства.'});
 const photo=await api.store.put(row('upload',u.user.id,{purpose:'portfolio',mime:'image/jpeg',size:10,status:'clean',fixture:true}));
 p=await call('PUT','/me/contractor-profile',{...original,expected_version:original.version,gallery_ids:[photo.id]});
 assert.equal(p.description,'Новое подробное описание с другого устройства.');assert.deepEqual(p.gallery_ids,[photo.id]);
 await assert.rejects(()=>call('PUT','/me/contractor-profile',{...original,expected_version:original.version,description:'Другое описание конфликтующего изменения.'}),e=>e.getStatus()===409);
 await assert.rejects(()=>call('PUT','/me/contractor-profile',{...p,expected_version:99999}),e=>e.getStatus()===409);
 p=await call('POST','/me/contractor-profile/publish',{expected_version:p.version});assert.equal(p.status,'published');
 assert.equal((await call('GET','/me/contractor-profile')).profile.public_visible,true);
 }finally{await api.store.close();}
});
