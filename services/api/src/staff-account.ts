import {Store, RecordData} from './store';

export function securityEventSummary(event:RecordData) {
  return {id:event.id,owner:event.owner,country:event.country,version:event.version,
    event:event.event,screen:event.screen,method:event.method,action_path:event.action_path,target_id:event.target_id,created_at:event.created_at,occurred_at:event.occurred_at,mfa:event.mfa,
    ip_summary:typeof event.ip==='string'&&/^\d{1,3}(\.\d{1,3}){3}$/.test(event.ip)
      ?event.ip.split('.').slice(0,2).join('.')+'.*.*':'Не раскрывается'};
}

// Immutable audit history is ordered by timestamp and UUID, not by random UUID
// alone. Both the cursor pivot and every related object remain region-scoped.
export async function accountDecisions(store:Store,country:string,userId:string,limit:number,after?:RecordData) {
  const values:any[]=[country,userId,limit];
  let boundary='';
  if(after){values.push(after.created_at,after.id);boundary="AND (r.data->>'created_at',r.id)<($4::text,$5::uuid)";}
  const rows=(await store.db.query<{data:RecordData}>(`
    SELECT r.data FROM records r WHERE r.kind='audit' AND r.country=$1
    AND (r.data->>'target_id'=$2 OR EXISTS(
      SELECT 1 FROM records target WHERE target.country=r.country
      AND target.id::text=r.data->>'target_id' AND target.owner=$2
      AND target.kind IN ('verification','contractor','portfolio','privacy')))
    ${boundary} ORDER BY r.data->>'created_at' DESC,r.id DESC LIMIT $3`,values)).rows;
  return rows.map(({data:r})=>({id:r.id,action:r.action,target_id:r.target_id,
    actor_id:r.actor_id,reason:r.reason,created_at:r.created_at}));
}

export async function accountEvents(store:Store,country:string,userId:string,limit:number,after?:RecordData) {
 const values:any[]=[country,userId,limit];let boundary='';
 if(after){values.push(after.created_at,after.id);boundary="AND (data->>'created_at',id)<($4::text,$5::uuid)";}
 return (await store.db.query<{data:RecordData}>(`SELECT data FROM records WHERE kind='security_event' AND country=$1 AND owner=$2 ${boundary} ORDER BY data->>'created_at' DESC,id DESC LIMIT $3`,values)).rows.map(x=>x.data);
}
