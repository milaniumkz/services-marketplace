import {randomUUID} from 'node:crypto';
import {Store,RecordData} from './store';

/** Effective optional processing ends at the irreversible account step, not when history expires. */
export async function revokeOptionalProcessing(store:Store,owner:string,country:string,now:Date){
 const rows=await store.db.query<{data:RecordData}>("SELECT data FROM records WHERE kind='processing_consent' AND owner=$1 AND country=$2 FOR UPDATE",[owner,country]);
 for(const {data:r} of rows.rows){
  if(r.revocation_source==='account_deletion'&&r.marketing===false&&r.ad_personalization===false&&r.optional_analytics===false)continue;
  const values={marketing:false,ad_personalization:false,optional_analytics:false,revoked_at:now.toISOString(),revocation_source:'account_deletion'};
  await store.put({...r,...values,updated_at:now.toISOString(),version:r.version+1});
  await store.put({id:randomUUID(),kind:'processing_consent_event',owner,country,created_at:now.toISOString(),version:1,...values,document_id:r.document_id??null,document_hash:r.document_hash??null});
 }
}

/** Only mutable optional history. Mandatory consent and immutable audit remain untouched. */
export async function minimizeOptionalConsentHistory(store:Store,job:RecordData,policy:RecordData|undefined,now:Date){
 const previous=job.category_progress?.optional_consents??{},days=policy?.payload?.audit_days;
 if(!policy||policy.country!==job.country||policy.status!=='effective'||!Number.isSafeInteger(days)||days<1)return {state:'awaiting_policy',processed:previous.processed??0,mandatory_consent_audit:'separate_review'};
 const owner=await store.get(job.owner);
 if(owner?.kind!=='user'||owner.status!=='deleted'||owner.country!==job.country)return {state:'awaiting_account_deletion',processed:previous.processed??0};
 const scope="r.kind IN('processing_consent','processing_consent_event') AND r.country=$1 AND r.owner=$2 AND r.data->>'retention_minimized_at' IS NULL";
 const rows=await store.db.query<{data:RecordData}>(`SELECT r.data FROM records r WHERE ${scope} AND ($3::uuid IS NULL OR r.id>$3) ORDER BY r.id LIMIT 50 FOR UPDATE`,[job.country,job.owner,previous.scan_cursor??null]);
 const cutoff=now.getTime()-days*86400000;let processed=0;
 for(const {data:r} of rows.rows){
  if([r.created_at,r.updated_at??r.created_at,r.revoked_at??r.created_at].some(v=>typeof v!=='string'||!Number.isFinite(Date.parse(v))||Date.parse(v)>cutoff))continue;
  if(r.kind==='processing_consent'&&(r.marketing!==false||r.ad_personalization!==false||r.optional_analytics!==false))continue;
  const protection=await store.db.query<{id:string}>(`SELECT id::text AS id FROM records h WHERE h.country=$1 AND (h.kind='legal_hold' AND h.data->>'status'='active' AND h.data->>'target_id'=$2 OR h.kind='case' AND h.data->>'target_id'=$2 AND (h.data->>'evidence_minimized_at' IS NULL OR COALESCE(h.data->>'status','') NOT IN('resolved','closed','dismissed'))) LIMIT 1`,[job.country,r.id]);
  if(protection.rows.length)continue;
  const keep=['id','kind','owner','country','created_at','document_id','document_hash','revoked_at','revocation_source'];
  const minimal=Object.fromEntries(keep.filter(k=>r[k]!==undefined).map(k=>[k,r[k]]));
  await store.put({...minimal,id:r.id,kind:r.kind,owner:r.owner,country:r.country,created_at:r.created_at,version:r.version+1,status:'retention_minimized',...(r.kind==='processing_consent'?{marketing:false,ad_personalization:false,optional_analytics:false}:{}),retention_minimized_at:now.toISOString(),retention_policy_id:policy.id,retention_policy_version:policy.version},{skipContentCheck:true});processed++;
 }
 const remaining=await store.db.query<{count:string}>(`SELECT count(*)::text AS count FROM records r WHERE ${scope}`,[job.country,job.owner]);
 return {state:Number(remaining.rows[0].count)?'waiting_retention_protection_or_review':'minimized',processed:(previous.processed??0)+processed,remaining:Number(remaining.rows[0].count),scan_cursor:rows.rows.length===50?rows.rows.at(-1)!.data.id:null,policy_id:policy.id,policy_version:policy.version,last_run_at:now.toISOString(),mandatory_consent_audit:'separate_review'};
}
