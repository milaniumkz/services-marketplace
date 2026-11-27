import {eraseProfileViews} from './listing-reactions';
import {randomUUID} from 'node:crypto';
import {Store,RecordData} from './store';
import {PrivateFiles} from './private-files';
import {anonymizeProfile} from './deletion-plan';
import {revokeOptionalProcessing} from './processing-consent-retention';

/** Run within the authenticated request transaction, before returning success. */
export async function removeAccountNow(store:Store,files:PrivateFiles,user:RecordData,job:RecordData,now=new Date()) {
 const until=new Date(now);until.setUTCFullYear(until.getUTCFullYear()+3);
 const archiveId=randomUUID();
 const identity={user_id:user.id,display_name:user.display_name,phone:user.phone,country:user.country,created_at:user.created_at};
 await store.put({id:archiveId,kind:'account_legal_archive',owner:'operator',country:user.country,version:1,created_at:now.toISOString(),subject_user_id:user.id,privacy_request_id:job.id,status:'retained',expires_at:until.toISOString(),purpose:'Owner-approved restricted claims and lawful-request archive',sealed_identity:await files.sealSecret(JSON.stringify(identity),'account-archive:'+archiveId)});
 await store.put({id:user.id,kind:'user',owner:user.id,country:user.country,created_at:user.created_at,version:user.version+1,status:'deleted',display_name:'Удалённый пользователь',phone:null,roles:[],languages:[],deleted_at:now.toISOString()},{skipContentCheck:true});
 await eraseProfileViews(store,user.id,user.country);
 await store.db.query('DELETE FROM credentials WHERE user_id=$1',[user.id]);
 await store.db.query('UPDATE tokens SET revoked=true WHERE user_id=$1',[user.id]);
 await store.db.query('DELETE FROM idempotency WHERE scope LIKE $1',[user.id+':%']);
 for(const kind of ['contractor','portfolio','content_revision','contractor_edit_snapshot'])
  for(const {data:r} of (await store.db.query<{data:RecordData}>('SELECT data FROM records WHERE country=$1 AND owner=$2 AND kind=$3',[user.country,user.id,kind])).rows)await anonymizeProfile(store,r);
 await revokeOptionalProcessing(store,user.id,user.country,now);
 await store.db.query("UPDATE records SET version=version+1,data=jsonb_build_object('id',id::text,'kind',kind,'owner',owner,'country',country,'created_at',data->'created_at','status','revoked','version',version+1) WHERE country=$1 AND owner=$2 AND kind IN ('push_token','download_ticket')",[user.country,user.id]);
 await store.db.query("UPDATE records SET version=version+1,data=data||jsonb_build_object('status','canceled','failure_code','ACCOUNT_DELETED','lease_expires_at',NULL,'version',version+1) WHERE kind='privacy' AND country=$1 AND owner=$2 AND data->>'type'='export' AND data->>'status' IN ('requested','processing','failed')",[user.country,user.id]);
 const result={...job,status:'limited_retention',account_deleted:true,completed_at:now.toISOString(),legal_archive_id:archiveId,legal_archive_until:until.toISOString(),version:job.version+1};
 await store.put(result);return result;
}

export async function purgeExpiredAccountArchives(store:Store,now:Date) {
 for(const r of await store.all('account_legal_archive')){
  if(r.status!=='retained'||r.expires_at>now.toISOString())continue;
  const held=(await store.all('legal_hold',r.country)).some(h=>h.status==='active'&&h.subject_user_id===r.subject_user_id);
  const dispute=(await store.all('case',r.country)).some(c=>(c.owner===r.subject_user_id||c.subject_user_id===r.subject_user_id||c.target_id===r.subject_user_id||(Array.isArray(c.members)&&c.members.includes(r.subject_user_id)))&&!['resolved','closed','dismissed'].includes(c.status));
  if(held||dispute)continue;
  await store.put({...r,sealed_identity:undefined,status:'expired',purged_at:now.toISOString(),version:r.version+1});
 }
}
