const {test}=require('node:test');const assert=require('node:assert/strict');const {randomUUID}=require('node:crypto');
const {Store}=require('../dist/store');const {planFileRetention,purgedUpload}=require('../dist/retention');
const record=(kind,extra={})=>({id:randomUUID(),kind,owner:randomUUID(),country:'KZ',version:1,created_at:'2026-01-01T00:00:00Z',...extra});
test('retention requires a published regional policy and protects exact held files even when review is overdue',async()=>{
 const store=new Store('memory://');await store.initialize();try{
  const now=new Date('2026-03-01T00:00:00Z'),verification=record('verification',{status:'passed',decided_at:'2026-01-15T00:00:00Z'});await store.put(verification);
  const held=record('upload',{owner:verification.owner,purpose:'identity',status:'clean',verification_id:verification.id,mime:'image/jpeg'}),free={...held,id:randomUUID()};await store.put(held);await store.put(free);
  const foreign=record('upload',{country:'KG',purpose:'identity',status:'uploaded'});await store.put(foreign);
  assert.deepEqual(await planFileRetention(store,now),[]);
  await store.put(record('retention_policy',{status:'effective',payload:{document_days:30}}));
  const hold=record('legal_hold',{target_id:held.id,fields:['file'],status:'active',review_at:'2026-02-01T00:00:00Z'});await store.put(hold);
  const pending=record('verification',{status:'pending_review'});await store.put(pending);for(let i=0;i<2;i++)await store.put(record('upload',{purpose:'identity',status:'clean',verification_id:pending.id}));let expiryNotices=0;
  const first=await planFileRetention(store,now,async r=>{assert.equal(r.id,pending.id);expiryNotices++;});assert.equal(expiryNotices,1);assert.equal((await store.get(pending.id)).status,'expired');assert.ok(first.includes(free.id));assert.ok(!first.includes(held.id));assert.ok(!first.includes(foreign.id));assert.equal((await store.get(held.id)).status,'clean');
  assert.ok((await planFileRetention(store,now)).includes(free.id),'failed physical deletion remains retryable');
  const tombstone=purgedUpload(await store.get(free.id),now);assert.equal(tombstone.status,'purged');assert.equal(tombstone.mime,undefined);await store.put(tombstone);
  await store.put({...hold,status:'released',version:2});assert.ok((await planFileRetention(store,now)).includes(held.id));
 }finally{await store.close();}
});
test('maintenance removes encrypted bytes only after the marker commits and retries a failed physical removal',async()=>{
 const {mkdtemp,rm}=require('node:fs/promises'),{tmpdir}=require('node:os'),{join}=require('node:path');
 const {Marketplace}=require('../dist/marketplace'),{PrivateFiles}=require('../dist/private-files'),{Providers}=require('../dist/providers');
 const dir=await mkdtemp(join(tmpdir(),'joba-retention-')),files=new PrivateFiles(dir),a=new Marketplace(new Store('memory://'),new Providers(),files);await a.initialize();
 try{
  const verification=record('verification',{status:'passed',decided_at:'2026-01-15T00:00:00Z'});await a.store.put(verification);
  const file=record('upload',{owner:verification.owner,purpose:'identity',status:'clean',verification_id:verification.id,mime:'image/jpeg'});await a.store.put(file);await files.write(file.id,Buffer.from('isolated encrypted bytes'));
  await a.store.put(record('retention_policy',{status:'effective',payload:{document_days:30}}));
  const realRemove=files.remove.bind(files);let failed=false;
  files.remove=async id=>{assert.equal((await a.store.get(id)).status,'purge_pending');if(!failed){failed=true;throw Error('isolated transient disk failure');}return realRemove(id);};
  const removedUser=record('user',{status:'active',phone:'isolated-private-contact',totp_secret:'isolated-mfa-secret',staff_permissions:['administrator']});await a.store.put({...removedUser,owner:removedUser.id});
  await a.store.put(record('privacy',{owner:removedUser.id,type:'delete',status:'scheduled',execute_after:'2026-02-28T00:00:00Z'}));
  const now=new Date('2026-03-01T00:00:00Z');await a.maintenance(now);const anonymous=await a.store.get(removedUser.id);assert.equal(anonymous.status,'deleted');assert.equal(anonymous.totp_secret,undefined);assert.equal(anonymous.staff_permissions,undefined);assert.equal(anonymous.phone,null);assert.equal((await a.store.get(file.id)).status,'purge_pending');assert.equal((await files.read(file.id)).toString(),'isolated encrypted bytes');
  await a.maintenance(now);assert.equal((await a.store.get(file.id)).status,'purged');await assert.rejects(()=>files.read(file.id),e=>e.code==='ENOENT');
 }finally{await a.store.close();await rm(dir,{recursive:true,force:true});}
});
