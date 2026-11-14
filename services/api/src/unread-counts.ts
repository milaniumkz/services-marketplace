import {Store} from './store';
export async function unreadCounts(store:Store,country:string,owner:string){
 const counts=(await store.db.query<{messages:string,notifications:string}>(`SELECT
  (SELECT count(*) FROM records m JOIN records c ON c.id::text=m.data->>'thread_id' AND c.kind='conversation' AND c.country=m.country WHERE m.country=$1 AND m.kind='message' AND m.owner<>$2 AND c.data->'members' ? $2 AND COALESCE(c.data->>'status','open') NOT IN ('frozen','restricted') AND COALESCE(m.data->>'tombstone','false')<>'true' AND COALESCE(m.data->>'moderation_status','') NOT IN ('quarantined','hidden','rejected') AND (m.data->>'sequence')::bigint>COALESCE((c.data->'read_sequences'->>$2)::bigint,0)) AS messages,
  (SELECT count(*) FROM records n WHERE n.country=$1 AND n.owner=$2 AND n.kind='notification' AND COALESCE(n.data->>'read','false')<>'true') AS notifications`,[country,owner])).rows[0];
 return {messages:Number(counts.messages),notifications:Number(counts.notifications)};
}
