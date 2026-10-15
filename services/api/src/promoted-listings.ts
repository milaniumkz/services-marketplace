import {Store,RecordData} from './store';
import {contractorPresentation} from './contractor-presentation';
import {publicContent} from './content-revisions';
export const promotedPlacements=['search.services.promoted','search.orders.promoted','home.promoted.services','top.services.promoted','top.orders.promoted'];
export async function promotedListings(store:Store,country:string,actor:string,placement:string,query:any,now=new Date()){
 const policy=(await store.db.query<{data:RecordData}>("SELECT data FROM records WHERE kind='placement_policy' AND country=$1 AND data->>'status'='effective' AND data->'payload'->>'placement_id'=$2 ORDER BY data->>'published_at' DESC,id DESC LIMIT 1",[country,placement])).rows[0]?.data;
 if(!policy)return {items:[],placement_id:placement};
 const kind=placement.includes('.orders.')?'order':'contractor',limit=Math.min(20,Math.max(0,policy.payload.capacity));if(!limit)return {items:[],placement_id:placement};
 const rows=await store.db.query<{boost_id:string;data:RecordData}>(`
 SELECT b.id AS boost_id,t.data FROM records b
 JOIN records t ON t.id::text=b.data->>'target_id' AND t.country=b.country AND t.owner=b.owner AND t.kind=$4
 JOIN records u ON u.id::text=t.owner AND u.kind='user' AND u.country=t.country AND u.data->>'status'='active'
 WHERE b.kind='boost' AND b.country=$1 AND b.data->>'placement_id'=$2
 AND b.data->>'status' IN ('active','scheduled') AND b.data->>'starts_at'<=$3 AND b.data->>'ends_at'>$3
 AND (b.data->>'provenance'='admin_grant' OR b.data->>'provenance'='paid' AND b.data->>'confirmed_at' IS NOT NULL)
 AND (t.kind='contractor' AND t.data->>'status'='published' AND u.data->>'verification'='passed' OR t.kind='order' AND t.data->>'status'='open' AND t.data->>'expires_at'>$3)
 AND COALESCE(t.data->>'moderation_status','') NOT IN ('hidden','quarantined','rejected')
 AND ($5::text='' OR t.data->>'city'=$5) AND ($6::text='' OR t.data->>'category_id'=$6 OR t.data->'category_ids' ? $6)
 AND NOT EXISTS(SELECT 1 FROM records p WHERE p.kind='pair_block' AND p.country=b.country AND p.data->>'status'='active' AND (p.owner=$7 AND p.data->>'target_id'=t.owner OR p.owner=t.owner AND p.data->>'target_id'=$7))
 AND EXISTS(SELECT 1 FROM records g WHERE g.kind='grant' AND g.country=t.country AND g.owner=t.owner AND g.data->>'valid_until'>$3 AND g.data->'capabilities' ? 'search_full' AND (g.data->>'balance' IS NULL OR (g.data->>'balance')::numeric>0))
 ORDER BY b.data->>'starts_at',b.id LIMIT $8`,[country,placement,now.toISOString(),kind,String(query.city??''),String(query.category_id??''),actor,limit]);
 const presented=kind==='contractor'?await contractorPresentation(store,country,rows.rows.map(r=>r.data)):rows.rows.map(r=>({...publicContent(r.data),exact_address:undefined}));
 return {placement_id:placement,items:presented.map((r,i)=>({boost_id:rows.rows[i].boost_id,target_type:kind,promoted:true,target:r})),organic_rank_changed:false};
}
