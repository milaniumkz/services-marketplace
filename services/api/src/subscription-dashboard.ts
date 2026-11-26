import {Store} from './store';

// Read-only aggregates. Do not infer purchases from client redirects or attempts.
export async function subscriptionDashboard(store:Store,country:string,from:string,now:string){
 const rows=(await store.db.query<any>(`
 WITH activations AS (
  SELECT t.country,'paid' AS channel, t.data->>'provider' AS provider,
   t.data->>'transaction_id' AS event_id,min(t.data->>'created_at') AS occurred_at
  FROM records t JOIN records s ON s.id::text=t.data->>'source_id' AND s.kind='subscription' AND s.country=t.country
  WHERE t.kind='payment_transaction' AND ($1='ALL' OR t.country=$1)
   AND t.data->>'benefit'='subscription' AND t.data->>'operation' IN ('purchase','renewal')
   AND t.data->>'environment'='production' AND COALESCE(t.data->>'is_test','false')<>'true'
   AND t.data->>'state'='active' AND COALESCE(t.data->>'resolution_required','false')<>'true'
   AND COALESCE((t.data->>'cash_amount_minor')::numeric,0)>0 AND t.data->>'transaction_id' IS NOT NULL
   AND COALESCE(s.data->>'is_test','false')<>'true' AND COALESCE(s.data->>'status','') NOT IN ('pending','revoked','refunded')
  GROUP BY t.country,t.data->>'provider',t.data->>'transaction_id'
  UNION ALL
  SELECT s.country,'rewarded',s.data->>'provider',s.id::text,s.data->>'created_at'
  FROM records s WHERE s.kind='subscription' AND ($1='ALL' OR s.country=$1)
   AND s.data->>'provider' IN ('rewarded_ads','yandex_web_ads')
   AND COALESCE(s.data->>'is_test','false')<>'true' AND COALESCE(s.data->>'environment','production')<>'sandbox'
   AND s.data->>'status' IN ('active','scheduled','expired','grace','canceled_at_period_end','canceled')
 )
 SELECT country,channel,count(*)::text AS all_time,
 count(*) FILTER(WHERE occurred_at>=$2 AND occurred_at<=$3)::text AS period
 FROM activations WHERE occurred_at<=$3 GROUP BY country,channel`,[country,from,now])).rows;
 const countries=country==='ALL'?['KZ','KG','RU','BY']:[country];
 const by_country=countries.map(code=>{const get=(channel:string,field:string)=>Number(rows.find((r:any)=>r.country===code&&r.channel===channel)?.[field]??0);return {country:code,paid:get('paid','period'),rewarded:get('rewarded','period'),paid_all_time:get('paid','all_time'),rewarded_all_time:get('rewarded','all_time')};});
 const sum=(key:'paid'|'rewarded'|'paid_all_time'|'rewarded_all_time')=>by_country.reduce((total,r)=>total+r[key],0);
 return {period:{paid:sum('paid'),rewarded:sum('rewarded')},all_time:{paid:sum('paid_all_time'),rewarded:sum('rewarded_all_time')},by_country};
}
