import {minimizeVerificationHistory} from './verification-retention';
import {minimizeOptionalConsentHistory} from './processing-consent-retention';
import {minimizeCaseText} from './case-text-retention';
import {minimizeClosedSupport} from './support-retention';
import {minimizeClosedWork} from './work-retention';
import {Store,RecordData} from './store';
const rules=[{category:'advertising',kinds:['web_ad_session','web_ad_grant','web_ad_progress'],policy:'logs_days'},{category:'security',kinds:['security_event'],policy:'security_days'},{category:'notifications',kinds:['notification','outbox'],policy:'logs_days'}];
/** Bounded, restartable stages. Called inside the maintenance transaction. */
export async function processDeletionCategories(store:Store,job:RecordData,policy:RecordData|undefined,now:Date){
 const owner=await store.get(job.owner);if(owner?.status!=='deleted'||owner.country!==job.country)return;
 const progress:Record<string,any>={...job.category_progress};
 const subjectProtected=(await store.all('legal_hold',job.country)).some(h=>h.status==='active'&&h.subject_user_id===job.owner)||(await store.all('case',job.country)).some(c=>![ 'resolved','closed','dismissed'].includes(c.status)&&(c.owner===job.owner||c.subject_user_id===job.owner||c.target_id===job.owner||(Array.isArray(c.members)&&c.members.includes(job.owner))));
 const limitedLegalRules=policy?.payload?.account_removal==='immediate'?[
  {category:'finance',kinds:['payment_transaction','subscription','refund_request','purchase_check','grant','boost','entitlement_consumption','ad_reward','ad_session','web_ad_redemption','referral_code','referral_attribution','referral_reservation','referral_reward','referral_discount','checkout_quote','compensation_request'],policy:'financial_days'},
  {category:'audit',kinds:['audit','consent','processing_consent','processing_consent_event','biometric_consent','web_ad_consent'],policy:'audit_days'}
 ]:[];
 for(const rule of [...rules,...limitedLegalRules]){
  if(subjectProtected){progress[rule.category]={state:'protected',processed:progress[rule.category]?.processed??0};continue;}
  const days=policy?.payload?.[rule.policy];
  if(!Number.isSafeInteger(days)||days<1){progress[rule.category]={state:'awaiting_policy',processed:progress[rule.category]?.processed??0};continue;}
  const cutoffDate=new Date(now.getTime()-days*86400000);
  if(['finance','audit'].includes(rule.category)&&policy?.payload?.account_removal==='immediate'){cutoffDate.setTime(now.getTime());cutoffDate.setUTCFullYear(cutoffDate.getUTCFullYear()-3);}
  const cutoff=cutoffDate.toISOString();
  const scope="r.country=$1 AND r.kind=ANY($2::text[]) AND (CASE WHEN r.kind='outbox' THEN r.data->>'recipient_id' ELSE r.owner END)=$3 AND COALESCE(r.data->>'status','')<>'retention_minimized'";
  const candidates=await store.db.query<{data:RecordData}>(`SELECT r.data FROM records r WHERE ${scope} AND r.data->>'created_at'<=$4 AND NOT EXISTS(SELECT 1 FROM records h WHERE h.country=r.country AND h.kind='legal_hold' AND h.data->>'status'='active' AND h.data->>'target_id'=r.id::text) AND NOT EXISTS(SELECT 1 FROM records c WHERE c.country=r.country AND c.kind='case' AND c.data->>'target_id'=r.id::text AND COALESCE(c.data->>'status','') NOT IN ('resolved','closed','dismissed')) AND NOT(r.kind='outbox' AND r.data->>'status'='processing') ORDER BY r.data->>'created_at',r.id LIMIT 50 FOR UPDATE`,[job.country,rule.kinds,job.owner,cutoff]);
  let processed=0;
  for(const {data:r} of candidates.rows){
   if(!Number.isFinite(Date.parse(r.created_at)))continue;
   if(rule.category==='finance'&&!['succeeded','failed','cancelled','canceled','expired','refunded','completed','rejected','revoked','consumed','released','settled'].includes(r.status))continue;
   await store.put({id:r.id,kind:r.kind,owner:r.owner,country:r.country,created_at:r.created_at,version:r.version+1,status:'retention_minimized',retention_policy_id:policy!.id,retention_policy_version:policy!.version,minimized_at:now.toISOString(),...(r.kind==='security_event'?{type:r.type}:{})},{skipContentCheck:true});
   if(r.kind==='notification')await store.db.query('DELETE FROM events WHERE event_id=$1 AND recipient_id=$2 AND country=$3',[r.id,job.owner,job.country]);
   processed++;
  }
  const remaining=await store.db.query<{count:string}>(`SELECT count(*)::text AS count FROM records r WHERE ${scope}`,[job.country,rule.kinds,job.owner]);
  progress[rule.category]={state:Number(remaining.rows[0].count)?'waiting_retention_or_protection':'minimized',processed:(progress[rule.category]?.processed??0)+processed,remaining:Number(remaining.rows[0].count),policy_id:policy!.id,policy_version:policy!.version,last_run_at:now.toISOString()};
 }
 progress.documents=await minimizeVerificationHistory(store,job,policy,now);
 progress.optional_consents=await minimizeOptionalConsentHistory(store,job,policy,now);
 progress.support=await minimizeClosedSupport(store,job,policy,now);
 progress.case_text=await minimizeCaseText(store,job,policy,now);
 progress.work=await minimizeClosedWork(store,job,policy,now);
 await store.put({...job,...(job.retention_plan?{retention_plan:{...job.retention_plan,categories:job.retention_plan.categories.map((c:any)=>progress[c.category]?{...c,execution_state:progress[c.category].state}:c)}}:{}),category_progress:progress,last_retention_run_at:now.toISOString(),fully_erased:false,version:job.version+1});
}
