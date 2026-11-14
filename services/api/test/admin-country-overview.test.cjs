const {test}=require('node:test'),assert=require('node:assert/strict'),{randomUUID}=require('node:crypto');
const {Marketplace}=require('../dist/marketplace'),{Store}=require('../dist/store');
test('owner sees all four countries with scoped pagination and filters and can open and manage a Belarus account without changing sessions; employees stay regional',async()=>{
 const api=new Marketplace(new Store('memory://'));await api.initialize();try{
 const password='Regional owner test password',boss=await api.handle('POST','/auth/register',{country:'KZ',phone:'+77000000601',password});await api.store.put({...await api.store.get(boss.user.id),staff_permissions:['platform_owner']});
 const owner=await api.handle('POST','/auth/staff-login',{country:'KZ',phone:boss.user.phone,password});
 const call=(m,p,b={},q={admin_country:'ALL'},token=owner.access_token)=>api.handle(m,p,b,'Bearer '+token,randomUUID(),q);
 const users=[];for(const [country,phone] of [['KZ','+77000000602'],['BY','+375291234567'],['KG','+996555123456'],['RU','+79001234567']]){
  const u=await api.handle('POST','/auth/register',{country,phone,password});users.push(u);
  const id=randomUUID();await api.store.put({id,kind:'order',owner:u.user.id,country,version:1,created_at:new Date().toISOString(),status:'open',title:'Региональный заказ '+country});
 }
 const rows=(await call('GET','/admin/users')).items;assert.equal(rows.length,4);assert.deepEqual(new Set(rows.map(x=>x.country)),new Set(['KZ','BY','KG','RU']));
 let cursor,seen=[];do{const result=await call('GET','/admin/users',{}, {admin_country:'ALL',limit:1,...cursor?{cursor}:{}});seen.push(...result.items.map(x=>x.id));cursor=result.meta.next_cursor;}while(cursor);assert.equal(new Set(seen).size,4);
 const by=users.find(x=>x.user.country==='BY');assert.equal((await call('GET','/admin/users',{}, {admin_country:'BY'})).items[0].id,by.user.id);
 const detail=await call('GET','/admin/users/'+by.user.id);assert.equal(detail.country,'BY');
 const blocked=await call('POST','/admin/users/'+by.user.id+'/block',{expected_version:detail.version});assert.equal((await api.store.get(by.user.id)).status,'blocked');
 assert.equal((await api.store.get(boss.user.id)).country,'KZ');assert.equal((await call('GET','/admin/orders')).items.length,4);
 assert.equal((await call('GET','/admin/dashboard')).users,3);assert.equal((await call('GET','/admin/dashboard',{}, {admin_country:'BY'})).users,0);
 assert.ok((await call('GET','/admin/search',{}, {admin_country:'ALL',q:by.user.id})).items.some(x=>x.id===by.user.id));
 const local=users[0];await api.store.put({...await api.store.get(local.user.id),staff_permissions:['administrator']});const staff=await api.handle('POST','/auth/staff-login',{country:'KZ',phone:local.user.phone,password});
 await assert.rejects(()=>call('GET','/admin/users',{}, {admin_country:'ALL'},staff.access_token),e=>e.getStatus()===403);
 await assert.rejects(()=>call('GET','/admin/users/'+by.user.id,{}, {admin_country:'BY'},staff.access_token),e=>e.getStatus()===403);
 await assert.rejects(()=>call('GET','/admin/users',{}, {admin_country:'INVALID'}),e=>e.getStatus()===400);
 assert.ok((await call('GET','/admin/users',{}, {},staff.access_token)).items.every(x=>x.country==='KZ'));
 }finally{await api.store.close();}
});
