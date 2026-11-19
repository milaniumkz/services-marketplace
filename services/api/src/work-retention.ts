import {heldFileIds} from './legal-holds';
import {Store,RecordData} from './store';
const kinds=['order','offer','invite','assignment','conversation','message','message_revision','review','review_revision','amendment','cancel_request'];
const common=['id','kind','owner','country','created_at','status','order_id','thread_id','message_id','review_id','conversation_id','offer_id','assignment_id','executor_id','customer_id','recipient_id','target_id','members','sequence','read_sequences','delivered_sequences','revision','rating','amount','agreed_amount','budget_amount','currency','completed_at','cancelled_at','expires_at','published_at','started_at'];
/** Only an author's own records: a departed executor never erases the customer's order. */
export async function minimizeClosedWork(store:Store,job:RecordData,policy:RecordData|undefined,now:Date){
 const days=policy?.payload?.chat_days;if(!Number.isSafeInteger(days)||days<1)return {state:'awaiting_policy',processed:job.category_progress?.work?.processed??0};
 const cutoff=new Date(now.getTime()-days*86400000).toISOString();
 const scope="r.country=$1 AND r.owner=$2 AND r.kind=ANY($3::text[]) AND r.data->>'retention_minimized_at' IS NULL";
 const result=await store.db.query<{data:RecordData}>(`SELECT r.data FROM records r
 LEFT JOIN records m ON r.kind='message_revision' AND m.id::text=r.data->>'message_id' AND m.kind='message' AND m.country=r.country
 LEFT JOIN records v ON r.kind='review_revision' AND v.id::text=r.data->>'review_id' AND v.kind='review' AND v.country=r.country
 LEFT JOIN records c ON c.id::text=COALESCE(r.data->>'thread_id',m.data->>'thread_id') AND c.kind='conversation' AND c.country=r.country
 JOIN records o ON o.id::text=CASE WHEN r.kind='order' THEN r.id::text ELSE COALESCE(r.data->>'order_id',v.data->>'order_id',c.data->>'order_id') END AND o.kind='order' AND o.country=r.country
 WHERE ${scope} AND r.data->>'created_at'<=$4 AND COALESCE(r.data->>'edited_at',r.data->>'created_at')<=$4
 AND ((o.data->>'status'='completed' AND o.data->>'completed_at'<=$4) OR (o.data->>'status'='cancelled' AND o.data->>'cancelled_at'<=$4) OR (o.data->>'status'='expired' AND o.data->>'expires_at'<=$4))
 AND NOT EXISTS(SELECT 1 FROM records newer WHERE newer.country=r.country AND newer.data->>'created_at'>$4 AND ((newer.kind='message_revision' AND newer.data->>'message_id'=r.id::text) OR (newer.kind='review_revision' AND newer.data->>'review_id'=r.id::text)))
 AND NOT EXISTS(SELECT 1 FROM records h WHERE h.country=r.country AND h.kind='legal_hold' AND h.data->>'status'='active' AND h.data->>'target_id' IN(r.id::text,o.id::text,m.id::text,v.id::text,c.id::text))
 AND NOT EXISTS(SELECT 1 FROM records x LEFT JOIN records xt ON xt.id::text=x.data->>'target_id' AND xt.country=x.country LEFT JOIN records xc ON xc.id::text=xt.data->>'thread_id' AND xc.kind='conversation' AND xc.country=x.country WHERE x.country=r.country AND x.kind='case' AND COALESCE(x.data->>'status','') NOT IN('resolved','closed','dismissed') AND (x.data->>'target_id' IN(r.id::text,o.id::text,m.id::text,v.id::text,c.id::text) OR x.data->>'order_id'=o.id::text OR xt.data->>'order_id'=o.id::text OR xc.data->>'order_id'=o.id::text))
 ORDER BY r.data->>'created_at',r.id LIMIT 50 FOR UPDATE OF r`,[job.country,job.owner,kinds,cutoff]);
 let processed=0;
 for(const {data:r} of result.rows){
  if(!Number.isFinite(Date.parse(r.created_at)))continue;
  const attachmentIds=[...new Set([r,r.order_snapshot,r.offer_snapshot,r.acknowledged_order].filter(Boolean).flatMap(value=>heldFileIds(value)))];
  const minimal=Object.fromEntries(common.filter(key=>r[key]!==undefined).map(key=>[key,r[key]]));
  await store.put({...minimal,id:r.id,kind:r.kind,owner:r.owner,country:r.country,created_at:r.created_at,version:r.version+1,retention_minimized_at:now.toISOString(),...(attachmentIds.length?{retention_file_ids:attachmentIds}:{}),retention_policy_id:policy!.id,retention_policy_version:policy!.version,...(['message','message_revision','review','review_revision'].includes(r.kind)?{text:'',upload_ids:[],tombstone:true}:{})} as RecordData,{skipContentCheck:true});processed++;
 }
 const remaining=await store.db.query<{count:string}>(`SELECT count(*)::text AS count FROM records r WHERE ${scope}`,[job.country,job.owner,kinds]);
 return {state:Number(remaining.rows[0].count)?'waiting_retention_or_protection':'minimized',processed:(job.category_progress?.work?.processed??0)+processed,remaining:Number(remaining.rows[0].count),policy_id:policy!.id,policy_version:policy!.version,last_run_at:now.toISOString()};
}
