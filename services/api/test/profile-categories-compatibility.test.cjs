const {test}=require('node:test'),assert=require('node:assert/strict'),{randomUUID}=require('node:crypto');
const {mkdtemp,rm}=require('node:fs/promises'),{tmpdir}=require('node:os'),{join}=require('node:path');
const {Marketplace}=require('../dist/marketplace'),{Store}=require('../dist/store'),{Providers}=require('../dist/providers'),{PrivateFiles}=require('../dist/private-files');
const {profileFields}=require('../dist/contractor-profile');
test('existing RU app saves more than ten selected service categories, reloads and publishes without losing text or gallery',async()=>{
 const dir=await mkdtemp(join(tmpdir(),'joba-profile-categories-')),api=new Marketplace(new Store('memory://'),new Providers(),new PrivateFiles(dir));await api.initialize();try{
 const session=await api.handle('POST','/auth/register',{country:'RU',phone:'+79123456789',password:'Isolated profile categories password'}),token='Bearer '+session.access_token;
 const call=(method,path,body={},key=randomUUID())=>api.handle(method,path,body,token,key);
 const categoryIds=[];for(let i=0;i<12;i++){const id=randomUUID();categoryIds.push(id);await api.store.put({id,kind:'category',country:'RU',owner:'system',version:1,created_at:new Date().toISOString(),status:'effective',title:'Тестовая услуга '+i,payload:{category_id:id,labels:{ru:'Тестовая услуга '+i},parent_id:null,schema:{properties:{},required:[]}}});}
 const body={title:'Ремонт квартир и бытовые услуги',description:'Опыт работы восемь лет, ремонт помещений и установка оборудования.',city:'Самара',category_id:categoryIds[0],category_ids:categoryIds,work_modes:['onsite'],service_cities:['Самара'],languages:['ru'],travel_radius_km:10,experience_years:8,price:{mode:'negotiable',currency:'RUB'}};
 const key=randomUUID();let saved=await call('PUT','/me/contractor-profile',body,key);assert.equal((await call('PUT','/me/contractor-profile',body,key)).id,saved.id);
 let reloaded=(await call('GET','/me/contractor-profile')).profile;assert.deepEqual(reloaded.category_ids,categoryIds);assert.equal(reloaded.title,body.title);assert.equal(reloaded.description,body.description);
 const before=await api.store.get(saved.id);for(const bad of [[...categoryIds,randomUUID()],[],['<script>'],[123],null])await assert.rejects(()=>call('PUT','/me/contractor-profile',{...body,expected_version:saved.version,category_ids:bad}),e=>e.getStatus()===400&&e.getResponse().error.details.field==='category_ids');assert.deepEqual(await api.store.get(saved.id),before);
 const bytes=await require('sharp')({create:{width:8,height:8,channels:3,background:'blue'}}).jpeg().toBuffer(),photo=randomUUID();await api.files.write(photo,bytes);await api.store.put({id:photo,kind:'upload',country:'RU',owner:session.user.id,version:1,created_at:new Date().toISOString(),purpose:'portfolio',mime:'image/jpeg',size:bytes.length,status:'clean'});
 saved=await call('PUT','/me/contractor-profile',{...saved,expected_version:saved.version,gallery_ids:[photo]});saved=await call('POST','/me/contractor-profile/publish',{expected_version:saved.version});
 reloaded=(await call('GET','/me/contractor-profile')).profile;assert.equal(reloaded.status,'published');assert.equal(reloaded.id,saved.id);assert.deepEqual(reloaded.category_ids,categoryIds);assert.deepEqual(reloaded.gallery_ids,[photo]);assert.equal(reloaded.description,body.description);
 saved=await call('PUT','/me/contractor-profile',{...reloaded,expected_version:reloaded.version,category_ids:[...categoryIds,categoryIds[0]],description:'Обновлённое описание услуги сохраняется вместе со всеми направлениями.'});
 reloaded=(await call('GET','/me/contractor-profile')).profile;assert.deepEqual(reloaded.category_ids,categoryIds);assert.equal(reloaded.description,saved.description);assert.deepEqual(reloaded.gallery_ids,[photo]);
 }finally{await api.store.close();await rm(dir,{recursive:true,force:true});}
});
test('category compatibility accepts all available choices and canonicalizes duplicates while retaining strict validation of other fields',()=>{
 const ids=Array.from({length:15},()=>randomUUID()),allowed=new Set(ids),base={category_id:ids[0],category_ids:[...ids,ids[0]],city:'Тест',price:{mode:'negotiable',currency:'RUB'}};
 assert.deepEqual(profileFields(base,null,'RUB',allowed).category_ids,ids);
 const alias=randomUUID();assert.deepEqual(profileFields({...base,category_ids:[alias,...ids]},null,'RUB',allowed,new Map([[alias,ids[0]]])).category_ids,ids);
 assert.throws(()=>profileFields({...base,work_modes:['onsite','onsite']},null,'RUB',allowed),/work_modes/);
 assert.throws(()=>profileFields({...base,category_ids:[...ids,randomUUID()]},null,'RUB',allowed),/category_ids/);
});
