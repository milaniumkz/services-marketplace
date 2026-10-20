const {test}=require('node:test'),assert=require('node:assert/strict'),{randomUUID}=require('node:crypto');
const {Marketplace}=require('../dist/marketplace'),{Store}=require('../dist/store'),{pricePayload}=require('../dist/price-payload');
const {bootstrapStaff}=require('../dist/staff-bootstrap');
test('standard and premium are exactly 30 days; premium rights, expiry and regional editable prices are independent',async()=>{
 const a=new Marketplace(new Store('memory://'));await a.initialize();
 try{
  const c=await a.handle('POST','/auth/register',{country:'KZ',phone:'+77000000691',password:'Isolated plan account password!'},undefined,randomUUID());
  await a.store.put({...await a.store.get(c.user.id),roles:['executor'],active_role:'executor',verification:'passed'});
  const customer=await a.handle('POST','/auth/register',{country:'KZ',phone:'+77000000692',password:'Isolated plan account password!'},undefined,randomUUID());
  assert.deepEqual((await a.handle('GET','/billing/offers',{},'Bearer '+customer.access_token)).items,[]);
  assert.deepEqual((await a.commerce.plans('KZ')).items.map(x=>x.amount_minor),[100000,150000]);
  await bootstrapStaff(a.store,a.files,{country:'KZ',identifier:'plan-owner',display_name:'Владелец',password:'Isolated plan owner password!',authentication:'password',permissions:['platform_owner'],reason:'Изолированная проверка изменения тарифов'},async()=>{});
  const boss=await a.handle('POST','/auth/staff-login',{country:'KZ',phone:'plan-owner',password:'Isolated plan owner password!'}),auth='Bearer '+boss.access_token;
  const update={prices:{standard:120000,premium:180000},expected_version:0,reason:'Изменение цен текущей страны владельцем'};
  await assert.rejects(()=>a.handle('POST','/admin/subscription-plans',update,'Bearer '+c.access_token,randomUUID()),e=>e.getStatus()===403);
  assert.equal((await a.handle('POST','/admin/subscription-plans',update,auth,randomUUID())).version,1);
  await assert.rejects(()=>a.handle('POST','/admin/subscription-plans',update,auth,randomUUID()),e=>e.getStatus()===409);
  assert.equal((await a.commerce.plans('KG')).items[0].amount_minor,100000);
  a.providers.billing.set('plan-test',{name:'plan-test'});
  for(const [plan,amount] of [['standard',120000],['premium',180000]]){
   const payload=pricePayload({plan,product_type:'subscription',provider:'plan-test',product_id:plan,amount_minor:amount,currency:'KZT',period:'days',duration_days:30,time_zone:'Asia/Almaty'},'KZ');
   assert.throws(()=>pricePayload({...payload,duration_days:31},'KZ'));
   await a.store.put({id:randomUUID(),kind:'price_version',owner:boss.user.id,country:'KZ',version:1,created_at:new Date().toISOString(),status:'effective',title:plan,payload});
   const purchase={user_id:c.user.id,country:'KZ',provider:'plan-test',product_id:plan,transaction_id:plan,original_transaction_id:plan,environment:'sandbox',amount_minor:amount,currency:'KZT',revision:1,state:'active',valid_until:new Date(Date.now()+30*86400000).toISOString()};
   const result=await a.commerce.apply(purchase);let grant=(await a.store.all('grant','KZ')).find(g=>g.source_id===result.subscription.id);
   assert.equal(grant.capabilities.includes('top100'),plan==='premium');assert.equal(grant.valid_until,purchase.valid_until);
   if(plan==='premium'){
    const profile=await a.store.put({id:randomUUID(),kind:'contractor',owner:c.user.id,country:'KZ',version:1,created_at:new Date().toISOString(),status:'published',title:'Премиальная услуга'});
    const other=await a.store.put({id:randomUUID(),kind:'contractor',owner:customer.user.id,country:'KZ',version:1,created_at:new Date().toISOString(),status:'published',title:'Обычная услуга'});await a.store.put({...await a.store.get(customer.user.id),verification:'passed'});
    const rows=await a.store.select('contractor','KZ',{publicActor:boss.user.id,ranking:{windowDays:30,ageDays:30,dislikeWeight:1,sort:'new'}});assert.equal(rows[0].id,profile.id);assert.equal(rows.length,2);
    await a.commerce.apply({...purchase,revision:2,state:'expired'});grant=(await a.store.all('grant','KZ')).find(g=>g.source_id===result.subscription.id);assert.ok(Date.parse(grant.valid_until)<=Date.now());
   }
  }
 }finally{await a.store.close();}
});
