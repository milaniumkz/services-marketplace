const {test}=require('node:test'),assert=require('node:assert/strict'),{randomUUID}=require('node:crypto');
const {Marketplace}=require('../dist/marketplace'),{Store}=require('../dist/store');
test('admin order filters combine country, status, participants, category, money, work mode, dates and attachments before pagination; invalid bounds are explained',async()=>{
 const api=new Marketplace(new Store('memory://'));await api.initialize();try{
 const password='Order filters test password',u=await api.handle('POST','/auth/register',{country:'KZ',phone:'+77000000791',password});await api.store.put({...await api.store.get(u.user.id),staff_permissions:['platform_owner']});const staff=await api.handle('POST','/auth/staff-login',{country:'KZ',phone:u.user.phone,password});
 const owner=randomUUID(),executor=randomUUID(),category=randomUUID();
 for(const [id,name] of [[owner,'Заказчик тестирования'],[executor,'Мастер тестирования']])await api.store.put({id,kind:'user',owner:id,country:'BY',version:1,created_at:new Date().toISOString(),display_name:name,roles:['customer'],status:'active'});
 const base={kind:'order',owner,country:'BY',version:1,created_at:'2026-10-29T23:59:59.999Z',status:'in_progress',city:'Минск',category_id:category,category_snapshot:{title:'Штукатурка стен'},budget_amount:100050,agreed_amount:90025,currency:'BYN',work_mode:'onsite',executor_id:executor,upload_ids:[randomUUID()],exact_address:'Минск, улица Ленина 1',moderation_status:'approved'};
 const order={...base,id:randomUUID()};await api.store.put(order);await api.store.put({...base,id:randomUUID(),country:'KZ',currency:'KZT',status:'open',budget_amount:50});await api.store.put({...base,id:randomUUID(),status:'deleted'});
 const list=q=>api.handle('GET','/admin/orders',{},'Bearer '+staff.access_token,undefined,{admin_country:'ALL',...q});
 const combined={customer:'заказчик',executor:'мастер',address:'ленина',status:'in_progress',city:'мин',category:'штукатурка',customer_id:owner,executor_id:executor,category_id:category,currency:'BYN',budget_min:'1000.50',budget_max:'1000.50',agreed_min:'900,25',agreed_max:'900.25',work_mode:'onsite',has_executor:'yes',has_photos:'yes',has_address:'yes',budget_mode:'fixed',moderation_status:'approved',date_field:'created_at',date_from:'2026-10-29',date_to:'2026-10-29',limit:1};
 assert.deepEqual((await list(combined)).items.map(x=>x.id),[order.id]);assert.equal((await list({...combined,admin_country:'KZ'})).items.length,0);
 for(const query of [{has_executor:'no'},{has_photos:'no'},{has_address:'no'},{budget_mode:'negotiable'},{date_from:'2026-10-30',date_to:'2026-10-30'},{date_from:'2026-10-28',date_to:'2026-10-28'},{order_id:randomUUID()}])assert.equal((await list({...combined,...query})).items.length,0);
 assert.equal((await list({order_id:order.id})).items.length,1);
 for(const [query,field] of [[{budget_min:'-1'},'budget_min'],[{budget_min:'100'},'currency'],[{currency:'BYN',budget_min:'200',budget_max:'100'},'budget_max'],[{date_from:'2026-02-30'},'date_from'],[{date_from:'2026-10-30',date_to:'2026-10-29'},'date_to'],[{date_field:'data);DROP TABLE records'},'date_field'],[{work_mode:'wrong'},'work_mode'],[{customer_id:'wrong'},'customer_id']])await assert.rejects(()=>list(query),e=>e.getStatus()===400&&e.getResponse().error.details.field===field);
 }finally{await api.store.close();}
});
