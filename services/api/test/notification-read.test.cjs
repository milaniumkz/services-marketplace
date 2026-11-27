const {test}=require('node:test');const assert=require('node:assert/strict');const {randomUUID}=require('node:crypto');
const {Store}=require('../dist/store');const {Marketplace}=require('../dist/marketplace');
test('notification watermark validates before writes, preserves newer/foreign events and counts all unread pages',async()=>{
 const a=new Marketplace(new Store('memory://'));await a.initialize();try{
  const reg=n=>a.handle('POST','/auth/register',{country:'KZ',phone:'+77000000'+n,password:'Isolated notification password!'},undefined,randomUUID(),{},'notice-'+n);
  const u=await reg('621'),other=await reg('622');
  const call=(user,m,p,b={},q={})=>a.handle(m,p,b,'Bearer '+user.access_token,randomUUID(),q,'notification-test');
  const put=async(owner,country,created_at)=>{const r={id:randomUUID(),kind:'notification',owner,country,version:1,read:false,created_at,type:'isolated.notice'};await a.store.put(r);return r;};
  const old=await put(u.user.id,'KZ','2020-01-01T00:00:00.000Z');
  const page=await call(u,'GET','/me/notifications',{}, {limit:'1'});assert.equal(page.meta.unread_count,1);assert.ok(Number.isFinite(Date.parse(page.meta.read_before)));
  const later=await put(u.user.id,'KZ',new Date(Date.parse(page.meta.read_before)+1).toISOString());
  const stranger=await put(other.user.id,'KZ',old.created_at),foreign=await put(u.user.id,'KG',old.created_at);
  const split=await call(u,'GET','/me/notifications',{}, {limit:'1'});assert.equal(split.items.length,1);assert.equal(split.meta.unread_count,2);
  for(const before of [undefined,null,{},'invalid','2020-02-30T00:00:00.000Z','2020-01-01',new Date(Date.now()+86400000).toISOString()]) {
    await assert.rejects(()=>call(u,'POST','/me/notifications/read-all',{before}),e=>e.getStatus()===400);
    assert.equal((await a.store.get(old.id)).read,false);
  }
  await call(u,'POST','/me/notifications/read-all',{before:page.meta.read_before});
  assert.equal((await a.store.get(old.id)).read,true);assert.equal((await a.store.get(later.id)).read,false);
  assert.equal((await a.store.get(stranger.id)).read,false);assert.equal((await a.store.get(foreign.id)).read,false);
  const updated=await call(u,'GET','/me/notifications',{}, {limit:'1'});assert.equal(updated.meta.unread_count,1);
  const read=await call(u,'POST','/me/notifications/'+later.id+'/read');const again=await call(u,'POST','/me/notifications/'+later.id+'/read');assert.equal(again.version,read.version);
  assert.equal((await call(u,'GET','/me/notifications',{}, {limit:'1'})).meta.unread_count,0);
  await assert.rejects(()=>call(other,'POST','/me/notifications/'+old.id+'/read'),e=>e.getStatus()===404);
 }finally{await a.store.close();}
});
