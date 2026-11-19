const {test}=require('node:test'),assert=require('node:assert/strict'),{randomUUID,randomBytes}=require('node:crypto');
const {Marketplace}=require('../dist/marketplace'),{Store}=require('../dist/store'),{totp}=require('../dist/totp');
test('owner publishes only promotion price and placement without second operator; 100 KZT buys a 24 hour reservation; other configurations retain independent approval',async()=>{
 const a=new Marketplace(new Store('memory://'));await a.initialize();try{
 const password='Isolated promotion owner password!',staff=[];
 for(const [phone,permissions] of [['+77000000871',['platform_owner']],['+77000000872',['billing','content']]]){const u=await a.handle('POST','/auth/register',{country:'KZ',phone,password}),secret=randomBytes(20).toString('hex');await a.store.put({...await a.store.get(u.user.id),staff_permissions:permissions,totp_secret:secret});staff.push(await a.handle('POST','/auth/staff-login',{country:'KZ',phone,password,mfa_code:totp(secret)}));}
 const call=(who,m,p,b={})=>a.handle(m,p,b,'Bearer '+who.access_token,randomUUID(),{admin_country:'KZ'});
 const payload={product_type:'boost',provider:'isolated',product_id:'joba.KZ.boost.24h',amount_minor:10000,currency:'KZT',period:'days',duration_days:1,time_zone:'Asia/Almaty'};
 a.providers.billing.set('isolated',{name:'isolated',validateProduct:async product_id=>({product_id,amount_minor:10000,currency:'KZT'})});
 const price=await call(staff[0],'POST','/admin/price-versions',{title:'Продвижение на 24 часа',payload});
 assert.equal((await call(staff[0],'POST','/admin/price-versions/'+price.id+'/publish',{expected_version:price.version})).status,'effective');
 const policy=await call(staff[0],'POST','/admin/placement-policies',{title:'Каталог услуг',payload:{placement_id:'search.services.promoted',capacity:1}});
 assert.equal((await call(staff[0],'POST','/admin/placement-policies/'+policy.id+'/publish',{expected_version:policy.version})).status,'effective');
 const ownEmployee=await call(staff[1],'POST','/admin/price-versions',{title:'Сотрудник не может подтвердить сам',payload:{...payload,product_id:'employee'}});
 await assert.rejects(()=>call(staff[1],'POST','/admin/price-versions/'+ownEmployee.id+'/publish',{expected_version:1}),e=>e.getResponse().error.code==='SECOND_APPROVAL_REQUIRED');
 const control=await call(staff[0],'POST','/admin/country-controls',{title:'Не меняем режим страны',payload:{registration_enabled:true,stop_new_business:false}});
 await assert.rejects(()=>call(staff[0],'POST','/admin/country-controls/'+control.id+'/publish',{expected_version:1}),e=>e.getResponse().error.code==='SECOND_APPROVAL_REQUIRED');
 const subscription=await call(staff[0],'POST','/admin/price-versions',{title:'Подписка не является продвижением',payload:{...payload,product_type:'subscription',plan:'standard',duration_days:30,product_id:'subscription'}});
 await assert.rejects(()=>call(staff[0],'POST','/admin/price-versions/'+subscription.id+'/publish',{expected_version:1}),e=>e.getResponse().error.code==='SECOND_APPROVAL_REQUIRED');
 const target={id:randomUUID(),kind:'contractor',owner:staff[0].user.id,country:'KZ',version:1,created_at:new Date().toISOString(),status:'published',city:'Алматы'};await a.store.put(target);
 await a.store.put({id:randomUUID(),kind:'grant',owner:target.owner,country:'KZ',version:1,created_at:new Date().toISOString(),valid_until:new Date(Date.now()+7*86400000).toISOString(),capabilities:['search_full']});
 const reservation=await a.growth.reserveBoost(target.owner,'KZ',{target_id:target.id,placement_id:'search.services.promoted',price_id:price.id});
 assert.equal(reservation.price_snapshot.amount_minor,10000);assert.equal(reservation.price_snapshot.currency,'KZT');assert.ok(Math.abs(Date.parse(reservation.ends_at)-Date.parse(reservation.starts_at)-86400000)<100);
 assert.equal(reservation.status,'reserved');assert.equal((await a.store.all('purchase','KZ')).length,0);
 }finally{await a.store.close();}
});
