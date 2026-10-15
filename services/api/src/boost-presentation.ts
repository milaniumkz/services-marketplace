import {RecordData,Store} from './store';
export async function boostPresentation(store:Store,country:string,rows:RecordData[],now=new Date()){
 const ids=[...new Set(rows.map(r=>r.target_id))];
 const targets=ids.length?(await store.db.query<{data:RecordData}>("SELECT data FROM records WHERE country=$1 AND id=ANY($2::uuid[])",[country,ids])).rows.map(r=>r.data):[];
 return rows.map(r=>{
  const target=targets.find(t=>t.id===r.target_id&&t.owner===r.owner);
  const status=['active','scheduled','paused','reserved','payment_pending'].includes(r.status)&&((['reserved','payment_pending'].includes(r.status)?r.reservation_expires_at:r.ends_at)??r.ends_at)<=now.toISOString()?'expired':r.status;
  return {id:r.id,version:r.version,country:r.country,status,created_at:r.created_at,target_id:r.target_id,target_type:target?.kind??null,title:target?.title??'',city:target?.city??'',category_id:target?.category_id??null,
   placement_id:r.placement_id,provenance:r.provenance??null,starts_at:r.starts_at,ends_at:r.ends_at,reservation_expires_at:r.reservation_expires_at??null,
   payment_confirmed:r.provenance==='paid'&&!!r.confirmed_at&&!['reserved','payment_pending','revoked'].includes(status),
   price:r.price_snapshot?{amount_minor:r.price_snapshot.amount_minor,currency:r.price_snapshot.currency,period:r.price_snapshot.period,duration_days:r.price_snapshot.duration_days,time_zone:r.price_snapshot.time_zone??'UTC'}:r.provenance==='admin_grant'?{amount_minor:0,currency:null}:null};
 });
}
