import {Store,RecordData} from './store';
import {liveFileReferences} from './work-file-retention';
/** Closed support belongs to its requester; decisions allowing appeal remain protected. */
export async function minimizeClosedSupport(store:Store,job:RecordData,policy:RecordData|undefined,now:Date){
 const previous=job.category_progress?.support?.processed??0,days=policy?.payload?.audit_days;
 if(!Number.isSafeInteger(days)||days<1)return {state:'awaiting_policy',processed:previous};
 const cutoff=new Date(now.getTime()-days*86400000).toISOString();let processed=0;
 const rows=await store.db.query<{data:RecordData,root:RecordData}>(`SELECT r.data,t.data AS root FROM records r JOIN records t ON t.id::text=CASE WHEN r.kind='support' THEN r.id::text ELSE r.data->>'thread_id' END AND t.kind='support' AND t.country=r.country
 WHERE r.country=$1 AND t.owner=$2 AND r.kind IN('support','support_message','support_note') AND r.data->>'retention_minimized_at' IS NULL AND t.data->>'status'='resolved' AND t.data->>'resolved_at'<=$3 AND COALESCE(t.data->>'reopen_until',t.data->>'resolved_at')<=$3 AND COALESCE(t.data->>'last_activity',t.data->>'resolved_at')<=$3 AND r.data->>'created_at'<=$3 AND COALESCE(r.data->>'edited_at',r.data->>'created_at')<=$3
 AND NOT EXISTS(SELECT 1 FROM records recent WHERE recent.country=t.country AND recent.kind IN('support_message','support_note') AND recent.data->>'thread_id'=t.id::text AND (recent.data->>'created_at'>$3 OR recent.data->>'edited_at'>$3))
 AND NOT EXISTS(SELECT 1 FROM records h WHERE h.country=r.country AND h.kind='legal_hold' AND h.data->>'status'='active' AND (h.data->>'target_id' IN(r.id::text,t.id::text,t.data->>'order_id') OR EXISTS(SELECT 1 FROM records child WHERE child.country=t.country AND child.data->>'thread_id'=t.id::text AND child.id::text=h.data->>'target_id')))
 AND NOT EXISTS(SELECT 1 FROM records o WHERE o.id::text=t.data->>'order_id' AND o.country=t.country AND o.kind='order' AND COALESCE(o.data->>'status','') NOT IN('completed','cancelled','expired'))
 AND NOT EXISTS(SELECT 1 FROM records c WHERE c.country=r.country AND c.kind='case' AND COALESCE(c.data->>'status','') NOT IN('resolved','closed','dismissed') AND (c.data->>'target_id' IN(r.id::text,t.id::text,t.data->>'order_id') OR c.data->>'order_id'=t.data->>'order_id'))
 ORDER BY r.data->>'created_at',r.id LIMIT 50 FOR UPDATE OF r`,[job.country,job.owner,cutoff]);
 for(const {data:r,root:t} of rows.rows){
  if([r.created_at,r.edited_at??r.created_at,t.resolved_at,t.reopen_until??t.resolved_at,t.last_activity??t.resolved_at].some(value=>!Number.isFinite(Date.parse(value))||Date.parse(value)>Date.parse(cutoff)))continue;
  const keep=['id','kind','owner','country','created_at','status','thread_id','order_id','members','assignee_id','sequence','resolved_at','reopen_until','last_activity'];
  const minimal=Object.fromEntries(keep.filter(k=>r[k]!==undefined).map(k=>[k,r[k]])),files=[...new Set([...(r.retention_file_ids??[]),...liveFileReferences(r)])];
  await store.put({...minimal,id:r.id,kind:r.kind,owner:r.owner,country:r.country,created_at:r.created_at,version:r.version+1,...(r.kind==='support'?{subject:'Архив обращения'}:{text:'',upload_ids:[],tombstone:true}),...(files.length?{retention_file_ids:files}:{}),retention_minimized_at:now.toISOString(),retention_policy_id:policy!.id,retention_policy_version:policy!.version},{skipContentCheck:true});processed++;
 }
 const cases=await store.db.query<{data:RecordData}>(`SELECT c.data FROM records c WHERE c.kind='case' AND c.country=$1 AND ((c.owner=$2 AND c.data->>'reporter_evidence_minimized_at' IS NULL) OR (c.data->>'subject_user_id'=$2 AND c.data->>'subject_evidence_minimized_at' IS NULL)) AND c.data->>'status'='resolved' AND c.data->>'decision' IN('no_violation','overturned') AND c.data->>'resolved_at'<=$3
 AND NOT EXISTS(SELECT 1 FROM records recent WHERE recent.kind IN('case_message','case_decision') AND recent.country=c.country AND recent.data->>'case_id'=c.id::text AND recent.data->>'created_at'>$3)
 AND NOT EXISTS(SELECT 1 FROM records h WHERE h.country=c.country AND h.kind IN('legal_hold','auto_hold','blacklist') AND h.data->>'status'='active' AND (h.data->>'target_id' IN(c.id::text,c.data->>'target_id',c.data->>'source_private_case_id') OR h.data->>'case_id'=c.id::text))
 AND NOT EXISTS(SELECT 1 FROM records related WHERE related.kind='case' AND related.country=c.country AND related.id<>c.id AND (COALESCE(related.data->>'status','') NOT IN('resolved','closed','dismissed') OR related.data->>'decision' IN('content_removed','sanction_upheld')) AND (related.data->>'target_id'=c.data->>'target_id' OR related.data->>'source_private_case_id'=c.id::text OR related.id::text=c.data->>'source_private_case_id'))
 ORDER BY c.data->>'resolved_at',c.id LIMIT 25 FOR UPDATE OF c`,[job.country,job.owner,cutoff]);
 for(const {data:c} of cases.rows){
  if(!Number.isFinite(Date.parse(c.resolved_at))||Date.parse(c.resolved_at)>Date.parse(cutoff))continue;
  const subject=c.subject_user_id===job.owner,reporter=c.owner===job.owner,patch:any={},files=new Set<string>(c.retention_file_ids??[]);
  if(subject){patch.subject_evidence_minimized_at=now.toISOString();for(const id of liveFileReferences(c.target_snapshot))files.add(id);patch.target_snapshot=undefined;patch.target_hash=undefined;patch.target_content_hash=undefined;}
  if(reporter){patch.reporter_evidence_minimized_at=now.toISOString();for(const field of ['upload_ids','appeal_upload_ids'])for(const id of c[field]??[])files.add(id);Object.assign(patch,{description:undefined,appeal_reason:undefined,upload_ids:[],appeal_upload_ids:[]});}
  await store.put({...c,...patch,evidence_minimized_at:now.toISOString(),evidence_scope:subject&&reporter?'subject_and_reporter':subject?'subject':'reporter',...(files.size?{retention_file_ids:[...files]}:{}),retention_policy_id:policy!.id,retention_policy_version:policy!.version,version:c.version+1},{skipContentCheck:true});processed++;
 }
 return {state:'partial_minimization',processed:previous+processed,last_run_at:now.toISOString(),policy_id:policy!.id,policy_version:policy!.version,case_text_stage:'separate',pending_moderation_and_other_support_records:true};
}
