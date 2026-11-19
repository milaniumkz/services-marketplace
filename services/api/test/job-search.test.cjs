const {test}=require('node:test');
const assert=require('node:assert/strict');
const {randomUUID}=require('node:crypto');
const {Store}=require('../dist/store');
const {Marketplace}=require('../dist/marketplace');
test('job search finds descriptions and category names; GPS filters legacy city-based orders and keeps visibility rules',async()=>{
 const api=new Marketplace(new Store('memory://'));await api.initialize();
 try{
  const register=phone=>api.handle('POST','/auth/register',{country:'KZ',phone,password:'Isolated job search password'},undefined,randomUUID(),{},phone);
  const customer=await register('+77000000691'),worker=await register('+77000000692');
  await api.store.put({...await api.store.get(worker.user.id),roles:['customer','executor'],active_role:'executor',verification:'passed'});
  const put=(kind,fields={},country='KZ')=>api.store.put({id:randomUUID(),kind,owner:customer.user.id,country,version:1,created_at:new Date().toISOString(),...fields});
  await put('grant',{owner:worker.user.id,valid_until:new Date(Date.now()+86400000).toISOString(),capabilities:['search_full']});
  await put('city',{name:'Изолированная Караганда',status:'active',latitude:49.8,longitude:73.1,population:1000});
  await put('city',{name:'Изолированная Алматы',status:'active',latitude:43.2,longitude:76.9,population:1000});
  const category=await put('category',{title:'Изолированные штукатурные работы',status:'effective',payload:{labels:{ru:'Штукатурка стен'}}});
  const base={status:'open',title:'Нужен мастер для дома',description:'Требуется штукатурка стен внутри дома',city:'Изолированная Караганда',category_id:category.id,expires_at:new Date(Date.now()+86400000).toISOString()};
  const nearby=await put('order',base),far=await put('order',{...base,city:'Изолированная Алматы'});
  await put('order',{...base,status:'draft'});await put('order',{...base,moderation_status:'hidden'});await put('order',{...base,expires_at:new Date(Date.now()-1000).toISOString()});
  const get=q=>api.handle('GET','/orders',{},'Bearer '+worker.access_token,undefined,q,'job-search');
  assert.deepEqual((await get({city:base.city,q:'штукатурка'})).items.map(r=>r.id),[nearby.id]);
  const q={near_lat:'49.8',near_lon:'73.1',radius_km:'50',city:'Изолированная Алматы',q:'штукатурка'};
  assert.deepEqual((await get(q)).items.map(r=>r.id),[nearby.id]);
  const categorySearch=await get({q:'Изолированные штукатурные'});assert.equal(categorySearch.items.length,2);assert.ok(categorySearch.items.some(r=>r.id===far.id));
  await assert.rejects(()=>get({near_lat:'bad',near_lon:'73'}),e=>e.getStatus()===400);
  await assert.rejects(()=>get({near_lat:'49',near_lon:'73',radius_km:'501'}),e=>e.getStatus()===400);
  await api.store.put({...await api.store.get(customer.user.id),status:'blocked'});assert.equal((await get(q)).items.length,0);
 }finally{await api.store.close();}
});
