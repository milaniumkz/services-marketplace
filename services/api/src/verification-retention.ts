import {Store,RecordData} from './store';

/** Record metadata uses audit retention; document bytes have their own document_days policy. */
export async function minimizeVerificationHistory(store:Store,job:RecordData,policy:RecordData|undefined,now:Date){
 const previous=job.category_progress?.documents??{},days=policy?.payload?.audit_days;
 if(!policy||policy.country!==job.country||policy.status!=='effective'||!Number.isSafeInteger(days)||days<1)return {state:'awaiting_policy',processed:previous.processed??0};
 const owner=await store.get(job.owner);
 if(owner?.kind!=='user'||owner.country!==job.country||owner.status!=='deleted')return {state:'awaiting_account_deletion',processed:previous.processed??0};
 const cutoff=now.getTime()-days*86400000;
 const scope="r.kind='verification' AND r.country=$1 AND r.owner=$2 AND r.data->>'retention_minimized_at' IS NULL";
 // Rotate past protected/ambiguous legacy rows so they cannot starve eligible rows.
 const rows=await store.db.query<{data:RecordData}>(`SELECT r.data FROM records r WHERE ${scope} AND ($3::uuid IS NULL OR r.id>$3) ORDER BY r.id LIMIT 50 FOR UPDATE`,[job.country,job.owner,previous.scan_cursor??null]);
 let processed=0;
 for(const {data:r} of rows.rows){
  if(!['passed','rejected','expired','revoked'].includes(r.status))continue;
  if([r.created_at,r.decided_at,r.updated_at??r.decided_at].some(v=>typeof v!=='string'||!Number.isFinite(Date.parse(v))||Date.parse(v)>cutoff))continue;
  if(!Array.isArray(r.document_refs)||r.document_refs.some((v:any)=>typeof v!=='string'))continue;
  const protection=await store.db.query<{id:string}>(`SELECT id::text AS id FROM records h WHERE h.country=$1 AND (
   h.kind IN('legal_hold','auto_hold','blacklist') AND h.data->>'status'='active' AND (h.data->>'target_id'=$2 OR h.data->>'user_id'=$3)
   OR h.kind='case' AND (h.data->>'target_id'=$2 AND (h.data->>'evidence_minimized_at' IS NULL OR COALESCE(h.data->>'status','') NOT IN('resolved','closed','dismissed')) OR h.data->>'subject_user_id'=$3 AND COALESCE(h.data->>'status','') NOT IN('resolved','closed','dismissed'))
  ) LIMIT 1`,[job.country,r.id,job.owner]);
  if(protection.rows.length)continue;
  const linked=await store.db.query<{data:RecordData}>("SELECT data FROM records WHERE kind='upload' AND country=$1 AND data->>'verification_id'=$2",[job.country,r.id]);
  let safe=true;
  for(const id of r.document_refs){
   const f=await store.get(id);
   if(!f||f.kind!=='upload'||f.country!==job.country||f.owner!==job.owner||f.purpose!=='identity'||f.status!=='purged'||f.verification_id!==undefined&&f.verification_id!==r.id){safe=false;break;}
  }
  if(!safe||linked.rows.some(({data:f})=>f.status!=='purged'||f.owner!==job.owner||f.purpose!=='identity'))continue;
  const keep=['id','kind','owner','country','created_at','status','decided_at','expires_at','reviewer_id','policy_id','policy_version','document_revision'];
  const minimal=Object.fromEntries(keep.filter(k=>r[k]!==undefined).map(k=>[k,r[k]]));
  await store.put({...minimal,id:r.id,kind:r.kind,owner:r.owner,country:r.country,created_at:r.created_at,version:r.version+1,document_refs:[],retention_minimized_at:now.toISOString(),retention_policy_id:policy.id,retention_policy_version:policy.version},{skipContentCheck:true});
  processed++;
 }
 const remaining=await store.db.query<{count:string}>(`SELECT count(*)::text AS count FROM records r WHERE ${scope}`,[job.country,job.owner]);
 return {state:Number(remaining.rows[0].count)?'waiting_retention_files_protection_or_review':'minimized',processed:(previous.processed??0)+processed,remaining:Number(remaining.rows[0].count),scan_cursor:rows.rows.length===50?rows.rows.at(-1)!.data.id:null,policy_id:policy.id,policy_version:policy.version,last_run_at:now.toISOString()};
}
