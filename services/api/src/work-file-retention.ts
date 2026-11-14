import {Store,RecordData} from './store';
const referenceFields=new Set(['file','upload_id','upload_ids','document_refs','photos','gallery_ids','avatar_id','cover_id','appeal_upload_ids','completion_upload_ids','revision_upload_ids','source_file_id','source_upload_id','bundle_file_id','preview_file_id']);
/** Nested snapshots/drafts are live references; retention_file_ids is only a cleanup trail. */
export function liveFileReferences(value:any):string[]{
 const found=new Set<string>();
 const walk=(node:any)=>{if(!node||typeof node!=='object')return;if(Array.isArray(node)){for(const item of node)walk(item);return;}for(const [key,v] of Object.entries(node)){if(key==='retention_file_ids')continue;if(referenceFields.has(key)){for(const id of Array.isArray(v)?v:[v])if(typeof id==='string')found.add(id);}walk(v);}};walk(value);return [...found];
}
export async function eligibleWorkFiles(store:Store,now=new Date()){
 const rows=await store.db.query<{data:RecordData,policy:RecordData}>("SELECT r.data,p.data AS policy FROM records r JOIN records p ON p.id::text=r.data->>'retention_policy_id' AND p.country=r.country AND p.kind='retention_policy' AND p.data->>'status' IN ('effective','superseded') WHERE COALESCE(r.data->>'retention_minimized_at',r.data->>'evidence_minimized_at') IS NOT NULL AND jsonb_typeof(r.data->'retention_file_ids')='array'");
 const candidates=new Map<string,{owners:string[],country:string,source_id:string,policy_id:string}>();
 for(const {data:r,policy:p} of rows.rows){
  const field=['case','case_message','case_decision','support','support_message','support_note'].includes(r.kind)?'audit_days':'chat_days',stamp=r.retention_minimized_at??r.evidence_minimized_at;
  if(!Number.isSafeInteger(p.payload?.[field])||p.payload[field]<1||!Number.isFinite(Date.parse(stamp))||Date.parse(stamp)>now.getTime())continue;
  const owners=r.kind==='case'?[...(r.reporter_evidence_minimized_at?[r.owner]:[]),...(r.subject_evidence_minimized_at?[r.subject_user_id]:[])]:[r.owner];
  for(const id of r.retention_file_ids)if(typeof id==='string'){const key=r.country+':'+id,previous=candidates.get(key);candidates.set(key,{owners:[...new Set([...(previous?.owners??[]),...owners])],country:r.country,source_id:r.id,policy_id:r.retention_policy_id});}
 }
 if(!candidates.size)return candidates;
 const countries=[...new Set([...candidates.values()].map(x=>x.country))];
 const references=await store.db.query<{data:RecordData}>("SELECT data FROM records WHERE country=ANY($1::text[]) AND kind NOT IN ('audit','security_event','payment_transaction','privacy','notification','outbox','download_ticket')",[countries]);
 for(const {data:r} of references.rows){if(r.kind==='legal_hold'&&r.status!=='active')continue;for(const id of liveFileReferences(r))candidates.delete(r.country+':'+id);}
 return candidates;
}
/** This reflects physical outcomes, including failures left pending for retry. */
export async function refreshWorkFileProgress(store:Store,now:Date){
 const jobs=await store.db.query<{data:RecordData}>("SELECT data FROM records WHERE kind='privacy' AND data->>'type'='delete' AND data->>'status'='limited_retention'");
 for(const {data:job} of jobs.rows){
  const rows=await store.db.query<{purpose:string,status:string,count:string}>("SELECT data->>'purpose' AS purpose,data->>'status' AS status,count(*)::text AS count FROM records WHERE kind='upload' AND country=$1 AND owner=$2 AND data->>'purpose' IN ('order','chat') GROUP BY 1,2",[job.country,job.owner]);
  const summarize=(items:typeof rows.rows)=>{const purged=items.filter(r=>r.status==='purged').reduce((sum,r)=>sum+Number(r.count),0),pending=items.filter(r=>r.status==='purge_pending').reduce((sum,r)=>sum+Number(r.count),0),remaining=items.reduce((sum,r)=>sum+Number(r.count),0)-purged;return {state:remaining?'waiting_references_retention_or_retry':'physically_purged',purged,purge_pending:pending,retained_or_unclassified:remaining-pending,last_run_at:now.toISOString()};};
  const plan=job.retention_plan?{...job.retention_plan,file_categories:(job.retention_plan.file_categories??[]).map((c:any)=>{if(!['order','chat'].includes(c.category))return c;const summary=summarize(rows.rows.filter(r=>r.purpose===c.category));return {...c,execution_state:summary.state,physical_purged_count:summary.purged,physical_pending_count:summary.purge_pending,physical_retained_or_unclassified_count:summary.retained_or_unclassified};})}:undefined;
  await store.put({...job,...(plan?{retention_plan:plan}:{}),category_progress:{...job.category_progress,work_files:summarize(rows.rows)},fully_erased:false,version:job.version+1});
 }
}
