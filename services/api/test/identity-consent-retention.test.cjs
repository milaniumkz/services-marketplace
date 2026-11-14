const {test}=require('node:test'),assert=require('node:assert/strict'),{randomUUID}=require('node:crypto');
const {Store}=require('../dist/store'),{minimizeVerificationHistory}=require('../dist/verification-retention'),{minimizeOptionalConsentHistory,revokeOptionalProcessing}=require('../dist/processing-consent-retention');
const row=(kind,owner,data={})=>({id:randomUUID(),kind,owner,country:'KZ',version:1,created_at:'2025-01-01T00:00:00.000Z',...data});
const now=new Date('2026-01-01T00:00:00Z');
async function fixture(){const store=new Store('memory://');await store.initialize();const owner=randomUUID();await store.put(row('user',owner,{id:owner,status:'deleted'}));return {store,owner,job:row('privacy',owner,{type:'delete',status:'limited_retention'}),policy:row('retention_policy','system',{status:'effective',payload:{audit_days:30,document_days:1}})};}
test('verification metadata waits for audit policy, actual decisions and purged bytes; preserves exact holds and cases',async()=>{
 const {store:s,owner,job,policy}=await fixture();try{
  const base={status:'rejected',decided_at:'2025-01-02T00:00:00.000Z',document_refs:[],reason:'private personal explanation',document_type:'passport',required_pages:['private page'],reviewer_id:'reviewer',document_revision:2};
  const ready=row('verification',owner,base),held=row('verification',owner,base),active=row('verification',owner,base),legacy=row('verification',owner,{...base,decided_at:undefined}),recent=row('verification',owner,{...base,decided_at:'2025-12-31T00:00:00.000Z'}),foreign=row('verification',owner,{...base,country:'KG'}),other=row('verification','other',base),pending=row('verification',owner,{...base,status:'pending_review'}),invalid=row('verification',owner,{...base,decided_at:'invalid'}),clean=row('verification',owner,base),unlinked=row('verification',owner,{...base,document_refs:[randomUUID()]}),extraFile=row('verification',owner,base);
  const purged=row('upload',owner,{purpose:'identity',status:'purged'});ready.document_refs=[purged.id];
  for(const r of [ready,held,active,legacy,recent,foreign,other,pending,invalid,clean,unlinked,extraFile,purged])await s.put(r);
  const file=row('upload',owner,{purpose:'identity',status:'clean',verification_id:clean.id});clean.document_refs=[file.id];await s.put({...clean,version:2});await s.put(file);
  await s.put(row('upload',owner,{purpose:'identity',status:'clean',verification_id:extraFile.id}));
  await s.put(row('legal_hold','staff',{status:'active',target_id:held.id,fields:['document_refs']}));await s.put(row('case','reporter',{target_id:active.id,status:'new'}));
  assert.equal((await minimizeVerificationHistory(s,job,{...policy,payload:{document_days:1}},now)).state,'awaiting_policy');
  let result=await minimizeVerificationHistory(s,job,policy,now);assert.equal(result.processed,1);
  const minimal=await s.get(ready.id);assert.equal(minimal.reason,undefined);assert.equal(minimal.document_type,undefined);assert.equal(minimal.required_pages,undefined);assert.equal(minimal.reviewer_id,'reviewer');assert.equal(minimal.status,'rejected');assert.equal(minimal.document_revision,2);assert.deepEqual(minimal.document_refs,[]);assert.equal(minimal.retention_policy_id,policy.id);
  for(const r of [held,active,legacy,recent,foreign,other,pending,invalid,unlinked,extraFile])assert.deepEqual(await s.get(r.id),JSON.parse(JSON.stringify(r)));
  assert.equal((await s.get(clean.id)).reason,base.reason);
  await s.put({...file,status:'purge_pending',version:2});result=await minimizeVerificationHistory(s,{...job,category_progress:{documents:result}},policy,now);assert.equal(result.processed,1);
  await s.put({...file,status:'purged',version:3});result=await minimizeVerificationHistory(s,{...job,category_progress:{documents:result}},policy,now);assert.equal(result.processed,2);assert.equal((await s.get(clean.id)).reason,undefined);
 }finally{await s.close();}
});
test('bounded verification scans rotate past ambiguous legacy rows, never erase active users and do not double count',async()=>{
 const {store:s,owner,job,policy}=await fixture();try{
  for(let i=0;i<52;i++)await s.put(row('verification',owner,{id:`00000000-0000-4000-8000-${String(i).padStart(12,'0')}`,status:'expired',document_refs:[],reason:'legacy without decision'}));
  const eligible=row('verification',owner,{id:'ffffffff-ffff-4fff-8fff-ffffffffffff',status:'expired',decided_at:'2025-01-02T00:00:00Z',document_refs:[],reason:'erase me'});await s.put(eligible);
  let result=await minimizeVerificationHistory(s,job,policy,now);assert.equal(result.processed,0);assert.ok(result.scan_cursor);
  result=await minimizeVerificationHistory(s,{...job,category_progress:{documents:result}},policy,now);assert.equal(result.processed,1);assert.equal(result.scan_cursor,null);
  result=await minimizeVerificationHistory(s,{...job,category_progress:{documents:result}},policy,now);assert.equal(result.processed,1);
  await s.put({...await s.get(owner),status:'active',version:2});assert.equal((await minimizeVerificationHistory(s,job,policy,now)).state,'awaiting_account_deletion');
 }finally{await s.close();}
});
test('optional consent is revoked once at account deletion; mutable history expires without changing mandatory proof',async()=>{
 const {store:s,owner,job,policy}=await fixture();try{
  const current=row('processing_consent',owner,{marketing:true,ad_personalization:true,optional_analytics:true,document_id:randomUUID(),document_hash:'proof',private_context:'old personal context'}),event=row('processing_consent_event',owner,{marketing:true,private_context:'erase old context',document_hash:'old-proof'}),mandatory=row('consent',owner,{accepted:true,document_hash:'mandatory-proof'}),audit=row('audit','staff',{target_id:owner,reason:'immutable reason'}),held=row('processing_consent_event',owner,{private_context:'keep held'}),foreign=row('processing_consent_event',owner,{country:'KG',private_context:'keep country'});
  for(const r of [current,event,mandatory,audit,held,foreign])await s.put(r);await s.put(row('legal_hold','staff',{status:'active',target_id:held.id,fields:['private_context']}));
  await revokeOptionalProcessing(s,owner,'KZ',now);const revoked=await s.get(current.id);assert.equal(revoked.marketing,false);assert.equal(revoked.ad_personalization,false);assert.equal(revoked.optional_analytics,false);assert.equal(revoked.revoked_at,now.toISOString());assert.equal(revoked.document_hash,'proof');
  await revokeOptionalProcessing(s,owner,'KZ',now);assert.equal((await s.all('processing_consent_event','KZ')).length,3);
  assert.equal((await minimizeOptionalConsentHistory(s,job,undefined,now)).state,'awaiting_policy');
  let result=await minimizeOptionalConsentHistory(s,job,policy,now);assert.equal(result.processed,1);assert.equal((await s.get(event.id)).private_context,undefined);assert.equal((await s.get(event.id)).marketing,undefined);assert.equal((await s.get(event.id)).document_hash,'old-proof');assert.equal((await s.get(current.id)).private_context,'old personal context');
  result=await minimizeOptionalConsentHistory(s,{...job,category_progress:{optional_consents:result}},policy,new Date('2026-03-01T00:00:00Z'));assert.equal(result.processed,3);assert.equal((await s.get(current.id)).private_context,undefined);assert.equal((await s.get(current.id)).marketing,false);assert.equal(result.mandatory_consent_audit,'separate_review');
  for(const r of [mandatory,audit,held,foreign])assert.deepEqual(await s.get(r.id),r);
 }finally{await s.close();}
});
test('maintenance revokes processing only after grace period, stores honest progress and rolls back a failed stage',async()=>{
 const {Marketplace}=require('../dist/marketplace'),a=new Marketplace(new Store('memory://'));await a.initialize();try{
  const u=await a.handle('POST','/auth/register',{country:'KZ',phone:'+77000000982',password:'Isolated optional consent deletion password!'},undefined,randomUUID()),owner=u.user.id;
  const current=row('processing_consent',owner,{marketing:true,ad_personalization:true,optional_analytics:true}),job=row('privacy',owner,{type:'delete',status:'scheduled',execute_after:'2026-01-02T00:00:00Z'}),policy=row('retention_policy','system',{status:'effective',payload:{document_days:30,audit_days:30}});
  for(const r of [current,job,policy])await a.store.put(r);
  await a.maintenance(now);assert.equal((await a.store.get(current.id)).marketing,true);
  const realPut=a.store.put.bind(a.store);a.store.put=async(r,opts)=>{if(r.kind==='processing_consent_event')throw Error('isolated consent persistence failure');return realPut(r,opts);};
  await assert.rejects(()=>a.maintenance(new Date('2026-01-03T00:00:00Z')),/isolated consent persistence failure/);assert.equal((await a.store.get(owner)).status,'active');assert.equal((await a.store.get(current.id)).marketing,true);assert.equal((await a.store.get(job.id)).status,'scheduled');
  a.store.put=realPut;await a.maintenance(new Date('2026-01-03T00:00:00Z'));assert.equal((await a.store.get(owner)).status,'deleted');assert.equal((await a.store.get(current.id)).marketing,false);const result=await a.store.get(job.id);assert.equal(result.status,'limited_retention');assert.equal(result.fully_erased,false);assert.ok(result.category_progress.optional_consents);assert.equal(result.retention_plan.categories.find(c=>c.category==='documents').retention_days,30);
 }finally{await a.store.close();}
});
test('privacy progress separates per-stage minimization from complete erasure and escapes record data',async()=>{
 const {privacyProgress}=await import('../../../apps/admin/privacy-progress.js');
 const esc=v=>String(v??'').replaceAll('&','&amp;').replaceAll('<','&lt;').replaceAll('>','&gt;').replaceAll('"','&quot;');
 const render=record=>privacyProgress({record,esc,card:(title,body)=>`<section><h2>${title}</h2>${body}</section>`,note:s=>`<p>${esc(s)}</p>`});
 assert.equal(render({type:'export'}),'');
 const html=render({type:'delete',status:'limited_retention',fully_erased:false,retention_plan:{active_holds:1,categories:[{label:'<img onerror=evil>',count:2,retention_days:30,execution_state:'pending_category_worker'}],file_categories:[{label:'Файлы',count:3,physical_purged_count:1,physical_pending_count:2}]},category_progress:{documents:{state:'minimized',processed:1,remaining:0},optional_consents:{state:'awaiting_policy'}}});
 assert.match(html,/Полное удаление не подтверждено/);assert.match(html,/История проверки личности/);assert.match(html,/Нужен опубликованный срок/);assert.match(html,/Обработано накопительно/);assert.match(html,/&lt;img onerror=evil&gt;/);assert.doesNotMatch(html,/<img/);assert.doesNotMatch(html,/Все предусмотренные этапы удаления подтверждены/);
});
