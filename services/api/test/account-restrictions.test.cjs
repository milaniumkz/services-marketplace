const {test}=require('node:test');
const assert=require('node:assert/strict');
const {randomUUID}=require('node:crypto');
const {Store}=require('../dist/store');
const {Marketplace}=require('../dist/marketplace');
test('account restrictions expose only current own regional limits and subject-safe appeal references',async()=>{
 const api=new Marketplace(new Store('memory://'));await api.initialize();
 try{
  const session=await api.handle('POST','/auth/register',{country:'KZ',phone:'+77000000094',password:'An isolated restriction password!'},undefined,undefined,{},'restriction-test');
  const actor=session.user.id,other=randomUUID(),now=new Date().toISOString(),future=new Date(Date.now()+86400000).toISOString();
  const put=(kind,data={},country='KZ')=>api.store.put({id:randomUUID(),kind,owner:other,country,version:1,created_at:now,...data});
  const get=()=>api.handle('GET','/me/restrictions',{},'Bearer '+session.access_token);
  const initial=await get();assert.equal(initial.meta.restricted,false);assert.deepEqual(initial.items,[]);
  await api.store.put({...await api.store.get(actor),status:'restricted'});
  const incident=await put('case',{subject_user_id:actor,status:'resolved',decision:'content_removed',reporter_private:true,description:'PRIVATE REPORT',public_reason:'Публичное объяснение решения'});
  const notice=await put('case',{owner:actor,subject_user_id:actor,source_private_case_id:incident.id,status:'resolved',decision:'content_removed',description:'Публичное объяснение решения'});
  await put('blacklist',{user_id:actor,case_id:incident.id,status:'active',ends_at:future,reason:'PRIVATE STAFF REASON'});
  await put('auto_hold',{user_id:actor,case_id:incident.id,status:'active',expires_at:future});
  await put('blacklist',{user_id:actor,case_id:incident.id,status:'active',ends_at:'2000-01-01T00:00:00Z'});
  await put('auto_hold',{user_id:actor,status:'released',expires_at:future});
  await put('blacklist',{user_id:other,status:'active',ends_at:future});
  await put('blacklist',{user_id:actor,status:'active',ends_at:future},'RS');
  const hidden=await put('case',{subject_user_id:other,status:'resolved',decision:'content_removed',public_reason:'PRIVATE OTHER SUBJECT'});
  await put('blacklist',{user_id:actor,case_id:hidden.id,status:'active',ends_at:future,reason:'PRIVATE STAFF REASON'});
  const result=await get();assert.equal(result.meta.restricted,true);assert.equal(result.items.length,3);
  const visible=result.items.filter(r=>r.case_id);assert.equal(visible.length,2);
  for(const r of visible){assert.equal(r.case_id,notice.id);assert.equal(r.can_appeal,true);assert.equal(r.reason,incident.public_reason);assert.equal(r.ends_at,future);}
  const safe=result.items.find(r=>!r.case_id);assert.equal(safe.can_appeal,false);assert.equal(safe.reason,'Проверка содержания');
  assert.ok(!JSON.stringify(result).includes('PRIVATE'));assert.ok(!JSON.stringify(result).includes(other));
  assert.ok(!JSON.stringify(result).includes(incident.id));
  const detail=await api.handle('GET','/cases/'+notice.id,{},'Bearer '+session.access_token);assert.equal(detail.id,notice.id);
  await api.store.put({...notice,status:'appealed'});
  assert.ok((await get()).items.every(r=>!r.can_appeal));
 }finally{await api.store.db.close();}
});
