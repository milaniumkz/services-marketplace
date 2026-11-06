import {Store,RecordData} from './store';
import {liveFileReferences} from './work-file-retention';
/** Personal contributions may expire independently; business reasons require all parties deleted. */
export async function minimizeCaseText(store:Store,job:RecordData,policy:RecordData|undefined,now:Date){
 const previous=job.category_progress?.case_text?.processed??0,days=policy?.payload?.audit_days;
 if(!Number.isSafeInteger(days)||days<1)return {state:'awaiting_policy',processed:previous};
 const cutoff=new Date(now.getTime()-days*86400000).toISOString();
 const scope="r.country=$1 AND r.kind IN('case','case_message','case_decision') AND r.data->>'case_text_minimized_at' IS NULL AND (c.owner=$2 OR c.data->>'subject_user_id'=$2 OR r.owner=$2)";
 const join="JOIN records c ON c.id::text=CASE WHEN r.kind='case' THEN r.id::text ELSE r.data->>'case_id' END AND c.kind='case' AND c.country=r.country";
 const allDeleted="EXISTS(SELECT 1 FROM records reporter WHERE reporter.id::text=c.owner AND reporter.kind='user' AND reporter.country=c.country AND reporter.data->>'status'='deleted') AND EXISTS(SELECT 1 FROM records subject WHERE subject.id::text=c.data->>'subject_user_id' AND subject.kind='user' AND subject.country=c.country AND subject.data->>'status'='deleted')";
 const rows=await store.db.query<{data:RecordData,incident:RecordData}>(`SELECT r.data,c.data AS incident FROM records r ${join} WHERE ${scope}
 AND c.data->>'status'='resolved' AND c.data->>'decision' IN('no_violation','overturned') AND c.data->>'resolved_at'<=$3 AND r.data->>'created_at'<=$3
 AND ((r.kind='case_message' AND r.owner=$2) OR ((${allDeleted}) AND (r.kind IN('case','case_decision') OR r.kind='case_message' AND r.data->>'author_type'='staff')))
 AND NOT EXISTS(SELECT 1 FROM records recent WHERE recent.country=c.country AND recent.kind IN('case_message','case_decision') AND recent.data->>'case_id'=c.id::text AND (recent.data->>'created_at'>$3 OR recent.data->>'edited_at'>$3))
 AND NOT EXISTS(SELECT 1 FROM records h WHERE h.country=c.country AND h.kind IN('legal_hold','auto_hold','blacklist') AND h.data->>'status'='active' AND (h.data->>'target_id' IN(r.id::text,c.id::text,c.data->>'target_id',c.data->>'source_private_case_id') OR h.data->>'case_id'=c.id::text OR EXISTS(SELECT 1 FROM records child WHERE child.country=c.country AND child.data->>'case_id'=c.id::text AND child.id::text=h.data->>'target_id')))
 AND NOT EXISTS(SELECT 1 FROM records related WHERE related.kind='case' AND related.country=c.country AND related.id<>c.id AND (COALESCE(related.data->>'status','') NOT IN('resolved','closed','dismissed') OR related.data->>'decision' IN('content_removed','sanction_upheld')) AND (related.data->>'target_id'=c.data->>'target_id' OR related.data->>'source_private_case_id'=c.id::text OR related.id::text=c.data->>'source_private_case_id'))
 ORDER BY r.data->>'created_at',r.id LIMIT 50 FOR UPDATE OF r`,[job.country,job.owner,cutoff]);
 let processed=0;
 for(const {data:r,incident:c} of rows.rows){
  if([c.resolved_at,r.created_at,r.edited_at??r.created_at].some(v=>!Number.isFinite(Date.parse(v))||Date.parse(v)>Date.parse(cutoff)))continue;
  const marker={case_text_minimized_at:now.toISOString(),retention_policy_id:policy!.id,retention_policy_version:policy!.version,version:r.version+1};
  if(r.kind==='case')await store.put({...r,reason:'',internal_notes:undefined,retention_file_ids:[...new Set([...(r.retention_file_ids??[]),...liveFileReferences(r.internal_notes)])],...marker},{skipContentCheck:true});
  else{
   const keep=['id','kind','owner','country','created_at','status','case_id','decision','target_version','internal','author_type','sequence'];
   const data=Object.fromEntries(keep.filter(k=>r[k]!==undefined).map(k=>[k,r[k]])),files=[...new Set([...(r.retention_file_ids??[]),...liveFileReferences(r)])];
   await store.put({...data,id:r.id,kind:r.kind,owner:r.owner,country:r.country,created_at:r.created_at,...marker,retention_minimized_at:now.toISOString(),...(files.length?{retention_file_ids:files}:{}),...(r.kind==='case_message'?{text:'',upload_ids:[],tombstone:true}:{reason:'',reason_minimized:true})},{skipContentCheck:true});
  }
  processed++;
 }
 const remaining=await store.db.query<{count:string}>(`SELECT count(*)::text AS count FROM records r ${join} WHERE ${scope}`,[job.country,job.owner]);
 return {state:Number(remaining.rows[0].count)?'waiting_retention_protection_or_other_parties':'minimized',processed:previous+processed,remaining:Number(remaining.rows[0].count),policy_id:policy!.id,policy_version:policy!.version,last_run_at:now.toISOString()};
}
