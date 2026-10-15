const {test}=require('node:test');const assert=require('node:assert/strict');
const {randomUUID,randomBytes}=require('node:crypto');
const {Marketplace}=require('../dist/marketplace');const {Store}=require('../dist/store');
const {normalizePromotionPayload,promoEnd}=require('../dist/configuration');const {totp}=require('../dist/totp');
const row=(kind,owner,extra)=>({id:randomUUID(),kind,owner,country:'KZ',version:1,created_at:new Date().toISOString(),...extra});
const call=(a,u,method,path,body={})=>a.handle(method,path,body,'Bearer '+u.access_token,randomUUID());
const password='Isolated promotion contract password!';
async function register(a,phone){return a.handle('POST','/auth/register',{country:'KZ',phone,password},undefined,randomUUID(),{},phone);}
test('promotion local start rejects DST ambiguity and uses the specified country timezone',()=>{
 assert.equal(normalizePromotionPayload({start_local:'2027-10-15T00:00',time_zone:'Asia/Almaty'}).valid_from,'2027-10-14T19:00:00.000Z');
 for(const start_local of ['2027-03-28T02:30','2027-10-31T02:30'])assert.throws(()=>normalizePromotionPayload({start_local,time_zone:'Europe/Belgrade'}));
});
test('promotion grants are executor-only, start-bounded and audience-bounded with a fixed end and no automatic charge',async()=>{
 const a=new Marketplace(new Store('memory://'));await a.initialize();
 try{
  const customer=await register(a,'+77000000921'),newUser=await register(a,'+77000000922'),oldUser=await register(a,'+77000000923');
  const start=new Date(Date.now()-86400000).toISOString(),end=new Date(Date.now()+2*86400000).toISOString();
  for(const u of [newUser,oldUser])await a.store.put({...await a.store.get(u.user.id),active_role:'executor',roles:['customer','executor']});
  await a.store.put({...await a.store.get(oldUser.user.id),created_at:new Date(Date.now()-2*86400000).toISOString()});
  const promotion=row('promotion','system',{status:'effective',published_at:new Date().toISOString(),payload:{audience:'new',role:'executor',valid_from:start},preview:{promo_end_exclusive:end,amount_minor:0}});await a.store.put(promotion);
  assert.deepEqual((await call(a,customer,'GET','/me/entitlements')).items,[]);
  assert.deepEqual((await call(a,oldUser,'GET','/me/entitlements')).items,[]);
  const granted=(await call(a,newUser,'GET','/me/entitlements')).items;assert.equal(granted.length,1);assert.equal(granted[0].valid_until,end);assert.equal(granted[0].source,'subscription_promotion');
  assert.equal((await call(a,newUser,'GET','/me/entitlements')).items.length,1);
  await a.store.put({...promotion,payload:{...promotion.payload,audience:'existing'}});
  assert.equal((await call(a,oldUser,'GET','/me/entitlements')).items.length,1);
  await a.store.put({...promotion,payload:{audience:'all',valid_from:new Date(Date.now()+86400000).toISOString()}});
  await a.store.put({...await a.store.get(customer.user.id),active_role:'executor',roles:['customer','executor']});
  assert.deepEqual((await call(a,customer,'GET','/me/entitlements')).items,[]);
  assert.deepEqual(await a.store.all('payment_transaction','KZ'),[]);
 }finally{await a.store.close();}
});
test('structured promotion drafts retain versions, enforce independent approval and cannot use a boost price',async()=>{
 const a=new Marketplace(new Store('memory://'));await a.initialize();
 try{
  const staff=[];
  for(const phone of ['+77000000924','+77000000925']){
   const u=await register(a,phone),secret=randomBytes(20).toString('hex');
   await a.store.put({...await a.store.get(u.user.id),staff_permissions:['billing'],totp_secret:secret});
   staff.push(await a.handle('POST','/auth/staff-login',{country:'KZ',phone,password,mfa_code:totp(secret)},undefined,randomUUID(),{},phone));
  }
  const price=row('price_version','system',{title:'Следующий тариф',status:'effective',payload:{product_type:'subscription',product_id:'monthly',period:'month',amount_minor:20000,currency:'KZT'}});await a.store.put(price);
  const payload={start_local:new Date(Date.now()+3600000).toISOString().slice(0,16),time_zone:'UTC',end_date:new Date(Date.now()+3*86400000).toISOString().slice(0,10),next_price_id:price.id,audience:'new',role:'executor',user_terms:'Бесплатный период без автоматического списания.'};
  let draft=await call(a,staff[0],'POST','/admin/promotions',{title:'Новый промо-период',reason:'Создание проверяемого черновика',payload});
  assert.ok(draft.payload.valid_from.endsWith('Z'));assert.equal(draft.payload.start_local,undefined);
  await assert.rejects(()=>call(a,staff[1],'PATCH','/admin/promotions/'+draft.id,{expected_version:1,title:draft.title,payload,reason:'Чужой черновик требует новой версии'}),e=>e.getStatus()===409);
  draft=await call(a,staff[0],'PATCH','/admin/promotions/'+draft.id,{expected_version:1,title:'Исправленный промо-период',payload:{...payload,audience:'all'},reason:'Согласованная корректировка аудитории'});assert.equal(draft.version,2);
  await assert.rejects(()=>call(a,staff[0],'PATCH','/admin/promotions/'+draft.id,{expected_version:1,title:'Старая версия',payload,reason:'Проверка конфликта версий'}),e=>e.getStatus()===409);
  const preview=await call(a,staff[0],'POST','/admin/promotions/'+draft.id+'/preview',{expected_version:2,reason:'Предварительная проверка периода и аудитории'});assert.equal(preview.promo_end_exclusive,promoEnd(payload.end_date,'UTC'));
  await assert.rejects(()=>call(a,staff[0],'POST','/admin/promotions/'+draft.id+'/publish',{expected_version:2,reason:'Автор не подтверждает собственную версию'}),e=>e.getStatus()===403);
  const published=await call(a,staff[1],'POST','/admin/promotions/'+draft.id+'/publish',{expected_version:2,reason:'Независимая проверка условий промо-периода'});assert.equal(published.status,'effective');
  await a.store.put({...price,payload:{...price.payload,product_type:'boost'}});
  await assert.rejects(()=>a.configuration.validate({...draft,payload:{...draft.payload,next_price_id:price.id}}),e=>e.getResponse().error.code==='NEXT_PRICE_UNVERIFIED');
 }finally{await a.store.close();}
});
