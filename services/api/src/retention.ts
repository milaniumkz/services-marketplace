import {Store,RecordData} from './store';
/** Runs inside the maintenance transaction; bytes are removed only after commit. */
export async function planFileRetention(store:Store,now:Date,onExpired?:(verification:RecordData)=>Promise<void>):Promise<string[]> {
 const policies=(await store.all('retention_policy')).filter(r=>r.status==='effective');
 const holds=(await store.all('legal_hold')).filter(r=>r.status==='active');
 const cases=(await store.all('case')).filter(r=>!['resolved','closed','dismissed'].includes(r.status));
 const verifications=await store.all('verification');
 const protectedFiles=new Set<string>();
 for(const incident of cases)for(const id of [...incident.upload_ids??[],...incident.appeal_upload_ids??[],...incident.target_snapshot?.upload_ids??[],...incident.target_snapshot?.gallery_ids??[],...incident.target_snapshot?.photos??[],...incident.target_snapshot?.document_refs??[]])protectedFiles.add(incident.country+':'+id);
 for(const hold of holds){
  const target=await store.get(hold.target_id);if(!target||target.country!==hold.country)continue;
  if(target.kind==='upload')protectedFiles.add(hold.country+':'+target.id);
  for(const field of hold.fields)for(const id of Array.isArray(target[field])?target[field]:typeof target[field]==='string'?[target[field]]:[])protectedFiles.add(hold.country+':'+id);
 }
 const removals:string[]=[];
 for(const file of await store.all('upload')){
  if(file.status==='purge_pending'){removals.push(file.id);continue;}
  if(file.status==='purged'||protectedFiles.has(file.country+':'+file.id))continue;
  const policy=policies.find(p=>p.country===file.country);if(!policy)continue;
  let reason:string|undefined;
  if(['initiated','uploaded','rejected','infected','failed'].includes(file.status)&&Date.parse(file.created_at)+86400000<=now.getTime())reason='abandoned_upload_24h';
  if(file.purpose==='export'&&file.expires_at<=now.toISOString())reason='export_link_expired';
  if(file.purpose==='identity'){
   const verification=verifications.find(v=>v.id===file.verification_id&&v.country===file.country);
   if(verification&&['passed','rejected','expired'].includes(verification.status)&&verification.decided_at&&Date.parse(verification.decided_at)+policy.payload.document_days*86400000<=now.getTime())reason='document_retention_expired';
   if(verification&&['draft','pending_review'].includes(verification.status)&&Date.parse(verification.created_at)+14*86400000<=now.getTime()){
    const held=holds.some(h=>h.country===verification.country&&h.target_id===verification.id&&h.fields.includes('document_refs'));
    if(!held){reason='verification_incomplete_14d';if(verification.status!=='expired'){const current=await store.get(verification.id);if(current?.status!=='expired'){const expired=await store.put({...current!,status:'expired',failure_code:'DOCUMENT_WINDOW_EXPIRED',version:current!.version+1});if(onExpired)await onExpired(expired);}}}
   }
  }
  if(reason){await store.put({...file,status:'purge_pending',purge_reason:reason,policy_id:policy.id,purge_requested_at:now.toISOString(),version:file.version+1});removals.push(file.id);}
 }
 return removals;
}
export function purgedUpload(file:RecordData,now:Date):RecordData {
 return {id:file.id,kind:file.kind,owner:file.owner,country:file.country,created_at:file.created_at,version:file.version+1,purpose:file.purpose,status:'purged',purged_at:now.toISOString(),policy_id:file.policy_id,purge_reason:file.purge_reason};
}
