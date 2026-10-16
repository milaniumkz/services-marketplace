import {minimizeClosedSupport} from './support-retention';
import {minimizeClosedWork} from './work-retention';
import {Store,RecordData} from './store';
const rules=[{category:'security',kinds:['security_event'],policy:'security_days'},{category:'notifications',kinds:['notification','outbox'],policy:'logs_days'}];
/** Bounded, restartable stages. Called inside the maintenance transaction. */
export async function processDeletionCategories(store:Store,job:RecordData,policy:RecordData|undefined,now:Date){
 const owner=await store.get(job.owner);if(owner?.status!=='deleted'||owner.country!==job.country)return;
 const progress:Record<string,any>={...job.category_progress};
 for(const rule of rules){
  const days=policy?.payload?.[rule.policy];
  if(!Number.isSafeInteger(days)||days<1){progress[rule.category]={state:'awaiting_policy',processed:progress[rule.category]?.processed??0};continue;}
  const cutoff=new Date(now.getTime()-days*86400000).toISOString();
  const scope="r.country=$1 AND r.kind=ANY($2::text[]) AND (CASE WHEN r.kind='outbox' THEN r.data->>'recipient_id' ELSE r.owner END)=$3 AND COALESCE(r.data->>'status','')<>'retention_minimized'";
  const candidates=await store.db.query<{data:RecordData}>(`SELECT r.data FROM records r WHERE ${scope} AND r.data->>'created_at'<=$4 AND NOT EXISTS(SELECT 1 FROM records h WHERE h.country=r.country AND h.kind='legal_hold' AND h.data->>'status'='active' AND h.data->>'target_id'=r.id::text) AND NOT EXISTS(SELECT 1 FROM records c WHERE c.country=r.country AND c.kind='case' AND c.data->>'target_id'=r.id::text AND COALESCE(c.data->>'status','') NOT IN ('resolved','closed','dismissed')) AND NOT(r.kind='outbox' AND r.data->>'status'='processing') ORDER BY r.data->>'created_at',r.id LIMIT 50 FOR UPDATE`,[job.country,rule.kinds,job.owner,cutoff]);
  let processed=0;
  for(const {data:r} of candidates.rows){
   if(!Number.isFinite(Date.parse(r.created_at)))continue;
   await store.put({id:r.id,kind:r.kind,owner:r.owner,country:r.country,created_at:r.created_at,version:r.version+1,status:'retention_minimized',retention_policy_id:policy!.id,retention_policy_version:policy!.version,minimized_at:now.toISOString(),...(r.kind==='security_event'?{type:r.type}:{})},{skipContentCheck:true});
   if(r.kind==='notification')await store.db.query('DELETE FROM events WHERE event_id=$1 AND recipient_id=$2 AND country=$3',[r.id,job.owner,job.country]);
   processed++;
  }
  const remaining=await store.db.query<{count:string}>(`SELECT count(*)::text AS count FROM records r WHERE ${scope}`,[job.country,rule.kinds,job.owner]);
  progress[rule.category]={state:Number(remaining.rows[0].count)?'waiting_retention_or_protection':'minimized',processed:(progress[rule.category]?.processed??0)+processed,remaining:Number(remaining.rows[0].count),policy_id:policy!.id,policy_version:policy!.version,last_run_at:now.toISOString()};
 }
 progress.support=await minimizeClosedSupport(store,job,policy,now);
 progress.work=await minimizeClosedWork(store,job,policy,now);
 await store.put({...job,...(job.retention_plan?{retention_plan:{...job.retention_plan,categories:job.retention_plan.categories.map((c:any)=>progress[c.category]?{...c,execution_state:progress[c.category].state}:c)}}:{}),category_progress:progress,last_retention_run_at:now.toISOString(),fully_erased:false,version:job.version+1});
}
