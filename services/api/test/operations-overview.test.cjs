const {test}=require('node:test');
const assert=require('node:assert/strict');
const {randomUUID}=require('node:crypto');
const {Store}=require('../dist/store');
const {operationsOverview,operationJob}=require('../dist/operations-overview');
test('dashboard series and totals use the same UTC period and remain region-scoped without invented financial data',async()=>{
 const store=new Store('memory://');await store.initialize();
 try{
  const now=new Date('2026-10-13T12:00:00Z'),user=randomUUID(),other=randomUUID();
  const put=(kind,data={},country='KZ',owner=user)=>store.put({id:randomUUID(),kind,country,owner,version:1,created_at:'2026-10-01T00:00:00.000Z',...data});
  await put('user',{id:user,status:'active'});await put('user',{id:other,status:'active'},'RS',other);
  await put('user',{status:'active',staff_permissions:['administrator']});
  await put('order',{status:'completed',published_at:'2026-10-07T01:00:00.000Z',completed_at:'2026-10-13T11:00:00.000Z'});
  await put('order',{status:'open',published_at:'2026-10-06T23:59:59.999Z'});
  await put('order',{status:'open',published_at:'2026-10-14T00:00:00.000Z'});
  await put('order',{status:'open',published_at:'2026-10-13T08:00:00.000Z'},'RS',other);
  await put('support',{status:'new'});await put('verification',{status:'pending_review'});
  const data=await operationsOverview(store,'KZ',7,now);
  assert.equal(data.users,1);assert.equal(data.active_users,1);assert.equal(data.published_orders,1);assert.equal(data.completed_orders,1);
  assert.equal(data.series.length,7);assert.equal(data.series.reduce((sum,row)=>sum+row.published,0),data.published_orders);
  assert.equal(data.series.reduce((sum,row)=>sum+row.completed,0),data.completed_orders);assert.equal(data.from,'2026-10-07T00:00:00.000Z');
  assert.equal(data.active_subscriptions,0);assert.equal(data.revenue,undefined);assert.equal(data.attention.unassigned_support,1);
  const job=operationJob({id:randomUUID(),kind:'upload',status:'processing',version:3,created_at:now.toISOString(),upload_token_hash:'private',original_name:'passport-private.png',document_refs:['private']});
  assert.equal(job.upload_token_hash,undefined);assert.equal(job.original_name,undefined);assert.equal(job.document_refs,undefined);
 }finally{await store.close();}
});

test('operational retries require staff MFA, current version and an eligible transient job without leaking private metadata',async()=>{
 const {Marketplace}=require('../dist/marketplace'),{totp}=require('../dist/totp');
 const api=new Marketplace(new Store('memory://'));await api.initialize();
 try{
  const password='Isolated operational password!';
  const account=await api.handle('POST','/auth/register',{country:'KZ',phone:'+77000000095',password,display_name:'Оператор'},undefined,undefined,{},'operations-test');
  const user=await api.store.get(account.user.id),secret='00112233445566778899aabbccddeeff00112233';
  await api.store.put({...user,staff_permissions:['administrator','security'],totp_secret:secret});
  const staff=await api.handle('POST','/auth/staff-login',{country:'KZ',phone:user.phone,password,mfa_code:totp(secret)},undefined,undefined,{},'operations-staff');
  const call=(session,method,path,body={},query={})=>api.handle(method,path,body,'Bearer '+session.access_token,randomUUID(),query,'operations-test');
  const id=randomUUID(),job={id,kind:'privacy',type:'export',owner:user.id,country:'KZ',version:1,created_at:new Date().toISOString(),status:'failed',attempts:5,private_note:'must not leak'};
  await api.store.put(job);
  await assert.rejects(()=>call(account,'GET','/admin/jobs'),e=>e.getResponse().error.code==='FORBIDDEN');
  const list=await call(staff,'GET','/admin/jobs');assert.equal(list.items.find(item=>item.id===id).private_note,undefined);
  assert.equal((await call(staff,'GET','/admin/jobs/'+id)).private_note,undefined);
  await assert.rejects(()=>call(account,'GET','/admin/jobs/'+id),e=>e.getStatus()===403);
  const foreign={...job,id:randomUUID(),country:'RS'};await api.store.put(foreign);
  await assert.rejects(()=>call(staff,'GET','/admin/jobs/'+foreign.id),e=>e.getStatus()===404);
  const future={...job,id:randomUUID(),status:'retry',next_attempt_at:new Date(Date.now()+3600000).toISOString()};await api.store.put(future);
  await api.store.put({...future,id:randomUUID(),status:'completed'});
  const scheduled=await call(staff,'GET','/admin/jobs',{}, {scheduled:'true',limit:1});assert.deepEqual(scheduled.items.map(r=>r.id),[future.id]);assert.equal(scheduled.counts.scheduled,1);assert.equal(scheduled.meta.next_cursor,null);
  await assert.rejects(()=>call(staff,'GET','/admin/jobs',{}, {scheduled:'invalid'}),e=>e.getStatus()===400);
  await assert.rejects(()=>call(staff,'POST','/admin/jobs/'+id+'/retry',{expected_version:9,reason:'Повтор после исправления причины'}),e=>e.getResponse().error.code==='STATE_CONFLICT');
  const retried=await call(staff,'POST','/admin/jobs/'+id+'/retry',{expected_version:1,reason:'Повтор после исправления причины'});assert.equal(retried.status,'requested');assert.equal(retried.attempts,0);
  await assert.rejects(()=>call(staff,'POST','/admin/jobs/'+id+'/retry',{expected_version:2,reason:'Нельзя повторять выполняемую задачу'}),e=>e.getResponse().error.code==='STATE_CONFLICT');
  assert.ok((await api.store.all('audit','KZ')).some(item=>item.action==='job.retry_requested'));
  const events=await call(staff,'GET','/admin/security-events',{}, {q:user.id});assert.ok(events.items.length);assert.equal(events.items[0].ip,undefined);assert.equal(events.items[0].session_family,undefined);
 }finally{await api.store.close();}
});
