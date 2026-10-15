const {test}=require('node:test');
const assert=require('node:assert/strict');
const {randomUUID}=require('node:crypto');
const {Marketplace}=require('../dist/marketplace');
const {Store}=require('../dist/store');
test('own boost history is free scoped paged by current lifecycle and excludes staff notes and provider secrets',async()=>{
 const api=new Marketplace(new Store('memory://'));await api.initialize();
 const call=(u,p,q={})=>api.handle('GET',p,{},'Bearer '+u.access_token,randomUUID(),q,'boost-history');
 const reg=phone=>api.handle('POST','/auth/register',{country:'KZ',phone,password:'Isolated boost history password!'},undefined,randomUUID(),{},phone);
 try{
  const u=await reg('+77000000761'),other=await reg('+77000000762'),now=new Date().toISOString(),future=new Date(Date.now()+86400000).toISOString();
  const target={id:randomUUID(),kind:'contractor',owner:u.user.id,country:'KZ',version:1,created_at:now,title:'Собственная карточка',status:'published'};await api.store.put(target);
  const base={kind:'boost',owner:u.user.id,country:'KZ',version:1,created_at:now,target_id:target.id,placement_id:'home.promoted.services',starts_at:now,ends_at:future,reason:'PRIVATE STAFF NOTE',actor_id:'PRIVATE STAFF ID',policy_snapshot:{internal:'PRIVATE POLICY'},transaction_id:'PRIVATE PROVIDER TOKEN'};
  const active={...base,id:randomUUID(),status:'active',provenance:'admin_grant'};await api.store.put(active);
  const expired={...base,id:randomUUID(),status:'active',ends_at:'2000-01-01T00:00:00Z'};await api.store.put(expired);
  const pending={...base,id:randomUUID(),status:'payment_pending',reservation_expires_at:future};await api.store.put(pending);
  const resolution={...base,id:randomUUID(),status:'resolution_required',provenance:'paid',confirmed_at:now,price_snapshot:{amount_minor:199000,currency:'KZT',period:'week',provider_secret:'PRIVATE PRICE'}};await api.store.put(resolution);
  const list=await call(u,'/me/boosts',{bucket:'active'});assert.equal(list.items.length,3);assert.ok(!JSON.stringify(list).includes('PRIVATE'));
  assert.equal(list.items.find(r=>r.id===active.id).price.amount_minor,0);assert.equal(list.items.find(r=>r.id===pending.id).payment_confirmed,false);
  assert.equal((await call(u,'/me/boosts/'+resolution.id)).payment_confirmed,true);
  const old=await call(u,'/me/boosts',{bucket:'history'});assert.equal(old.items.length,1);assert.equal(old.items[0].status,'expired');
  await assert.rejects(()=>call(other,'/me/boosts/'+active.id),e=>e.getStatus()===404);
  assert.deepEqual((await call(other,'/me/boosts')).items,[]);
  await assert.rejects(()=>call(u,'/me/boosts',{bucket:'invalid'}),e=>e.getStatus()===400);
  const first=await call(u,'/me/boosts',{bucket:'active',limit:1});assert.equal(first.items.length,1);assert.ok(first.meta.next_cursor);
  await assert.rejects(()=>call(u,'/me/boosts',{bucket:'history',limit:1,cursor:first.meta.next_cursor}),e=>e.getStatus()===400);
 }finally{await api.store.close();}
});
