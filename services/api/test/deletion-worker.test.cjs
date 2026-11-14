const {test}=require('node:test'),assert=require('node:assert/strict'),{randomUUID}=require('node:crypto');
const {Store}=require('../dist/store'),{processDeletionCategories}=require('../dist/deletion-worker');
const row=(kind,owner,data={})=>({id:randomUUID(),kind,owner,country:'KZ',version:1,created_at:'2025-01-01T00:00:00.000Z',...data});
test('deletion stages are bounded, regional, recipient-scoped and restart without double processing',async()=>{
 const s=new Store('memory://');await s.initialize();try{
 const owner=randomUUID();await s.put(row('user',owner,{id:owner,status:'deleted'}));const job=row('privacy',owner,{type:'delete',status:'limited_retention'});await s.put(job);
 const policy=row('retention_policy','system',{payload:{security_days:30,logs_days:30}}),now=new Date('2026-01-01T00:00:00Z');
 const notificationIds=[];for(let i=0;i<52;i++){const n=row('notification',owner,{target_id:randomUUID(),type:'private',private_text:'erase'});await s.put(n);notificationIds.push(n.id);await s.db.query('INSERT INTO events(event_id,recipient_id,country,data) VALUES($1,$2,$3,$4)',[n.id,owner,'KZ',JSON.stringify({private:'erase'})]);}
 const security=row('security_event',owner,{ip:'private-ip',user_agent:'private-agent',type:'login'}),recent=row('security_event',owner,{created_at:'2025-12-31T00:00:00.000Z',ip:'keep-recent'}),foreign=row('security_event',owner,{country:'KG',ip:'keep-country'}),held=row('security_event',owner,{ip:'keep-held'}),cased=row('security_event',owner,{ip:'keep-case'}),other=row('outbox',owner,{recipient_id:randomUUID(),status:'pending',payload:'belongs to another recipient'}),pending=row('outbox','staff',{recipient_id:owner,status:'processing',payload:'in flight'}),outbox=row('outbox','staff',{recipient_id:owner,status:'suppressed',payload:'erase'}),payment=row('payment_transaction',owner,{amount_minor:123,currency:'KZT'});
 for(const r of [security,recent,foreign,held,cased,other,pending,outbox,payment])await s.put(r);await s.put(row('legal_hold','staff',{target_id:held.id,status:'active',fields:['ip']}));await s.put(row('case','staff',{target_id:cased.id,status:'new'}));
 await processDeletionCategories(s,job,undefined,now);assert.equal((await s.get(job.id)).category_progress.security.state,'awaiting_policy');
 await processDeletionCategories(s,await s.get(job.id),policy,now);assert.equal((await s.get(job.id)).category_progress.notifications.processed,50);assert.equal((await s.get(security.id)).ip,undefined);assert.equal((await s.get(security.id)).type,'login');
 await processDeletionCategories(s,await s.get(job.id),policy,now);const progress=(await s.get(job.id)).category_progress;assert.equal(progress.notifications.processed,53);assert.equal(progress.notifications.remaining,1);assert.equal(progress.security.processed,1);assert.equal((await s.db.query('SELECT count(*)::int AS count FROM events')).rows[0].count,0);
 for(const r of [recent,foreign,held,cased,other,pending,payment])assert.deepEqual(await s.get(r.id),r);
 await processDeletionCategories(s,await s.get(job.id),policy,now);assert.equal((await s.get(job.id)).category_progress.notifications.processed,53);assert.equal((await s.get(job.id)).fully_erased,false);
 }finally{await s.close();}
});
test('failed stage rolls back data and progress together, then retries after restart',async()=>{
 const s=new Store('memory://');await s.initialize();try{
 const owner=randomUUID();await s.put(row('user',owner,{id:owner,status:'deleted'}));const job=row('privacy',owner,{type:'delete',status:'limited_retention'}),event=row('security_event',owner,{ip:'erase-on-retry'});await s.put(job);await s.put(event);const policy=row('retention_policy','system',{payload:{security_days:1,logs_days:1}}),now=new Date('2026-01-01T00:00:00Z'),original=s.put.bind(s);
 s.put=async r=>{if(r.id===job.id)throw Error('isolated persistence failure');return original(r);};await s.db.exec('BEGIN');await assert.rejects(()=>processDeletionCategories(s,job,policy,now),/isolated persistence failure/);await s.db.exec('ROLLBACK');assert.equal((await s.get(event.id)).ip,'erase-on-retry');assert.equal((await s.get(job.id)).category_progress,undefined);
 s.put=original;await s.db.exec('BEGIN');await processDeletionCategories(s,job,policy,now);await s.db.exec('COMMIT');assert.equal((await s.get(event.id)).ip,undefined);assert.equal((await s.get(job.id)).category_progress.security.processed,1);
 }finally{await s.close();}
});
test('maintenance runs category stages only after the irreversible account step and updates the saved plan',async()=>{
 const {Marketplace}=require('../dist/marketplace'),a=new Marketplace(new Store('memory://'));await a.initialize();try{
 const u=await a.handle('POST','/auth/register',{country:'KZ',phone:'+77000000971',password:'Isolated deletion worker password!'},undefined,randomUUID()),now=new Date();
 const job=row('privacy',u.user.id,{type:'delete',status:'scheduled',execute_after:new Date(now.getTime()-1000).toISOString()}),event=row('security_event',u.user.id,{ip:'private-old-address',type:'login'});await a.store.put(job);await a.store.put(event);await a.store.put(row('retention_policy','system',{status:'effective',payload:{document_days:30,security_days:1,logs_days:1}}));
 await a.maintenance(now);const result=await a.store.get(job.id);assert.equal((await a.store.get(u.user.id)).status,'deleted');assert.equal((await a.store.get(event.id)).ip,undefined);assert.equal(result.category_progress.security.processed,1);assert.equal(result.retention_plan.categories.find(c=>c.category==='security').execution_state,result.category_progress.security.state);assert.equal(result.fully_erased,false);assert.equal(result.status,'limited_retention');
 await a.maintenance(now);assert.equal((await a.store.get(job.id)).category_progress.security.processed,1);
 }finally{await a.store.close();}
});
