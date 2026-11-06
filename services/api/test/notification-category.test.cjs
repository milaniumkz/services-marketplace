const {test}=require('node:test');const assert=require('node:assert/strict');const {randomUUID}=require('node:crypto');
const {Store}=require('../dist/store');const {Marketplace}=require('../dist/marketplace');
test('notification categories paginate the complete owned history newest first and reject reused cursors',async()=>{
 const a=new Marketplace(new Store('memory://'));await a.initialize();try{
  const reg=n=>a.handle('POST','/auth/register',{country:'KZ',phone:'+77000000'+n,password:'Isolated notification password!'},undefined,randomUUID(),{},'notice-category-'+n);
  const u=await reg('623'),v=await reg('624');
  const get=(q={},user=u)=>a.handle('GET','/me/notifications',{},'Bearer '+user.access_token,undefined,q,'notice-category');
  const put=async(type,year,extra={})=>{const r={id:randomUUID(),kind:'notification',country:'KZ',owner:u.user.id,created_at:`${year}-01-01T00:00:00.000Z`,read:false,version:1,type,...extra};await a.store.put(r);return r;};
  const old=await put('order.created',2020),newer=await put('offer.created',2022),account=await put('verification.updated',2021),support=await put('support.message.created',2023),campaign=await put('service.campaign',2024,{deep_link:{route:'offer',id:randomUUID()}});
  await put('order.created',2025,{owner:v.user.id});await put('order.created',2025,{country:'KG'});
  const first=await get({category:'orders',limit:'1'});assert.equal(first.items[0].id,campaign.id);assert.equal(first.meta.unread_count,5);assert.equal(first.meta.total,3);
  const second=await get({category:'orders',limit:'1',cursor:first.meta.next_cursor});assert.equal(second.items[0].id,newer.id);
  const third=await get({category:'orders',limit:'1',cursor:second.meta.next_cursor});assert.equal(third.items[0].id,old.id);assert.equal(third.meta.next_cursor,null);
  assert.deepEqual((await get({category:'account'})).items.map(x=>x.id),[account.id]);
  assert.deepEqual((await get()).items.map(x=>x.id),[campaign.id,support.id,newer.id,account.id,old.id]);
  for(const query of [{category:'bad'},{category:'account',cursor:first.meta.next_cursor}])await assert.rejects(()=>get(query),e=>e.getStatus()===400);
  await assert.rejects(()=>get({category:'orders',limit:'1',cursor:first.meta.next_cursor},v),e=>e.getStatus()===400);
  await a.store.db.query('DELETE FROM records WHERE id=$1',[campaign.id]);
  await assert.rejects(()=>get({category:'orders',limit:'1',cursor:first.meta.next_cursor}),e=>e.getResponse().error.details.restart_required===true);
 }finally{await a.store.close();}
});
