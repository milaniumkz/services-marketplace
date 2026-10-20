import {RecordData, Store} from './store';
import {publicContent} from './content-revisions';

// Enrich an already-authorized page in batches. Never return phone or staff data.
export async function contractorPresentation(store:Store, country:string, profiles:RecordData[]) {
  if(!profiles.length)return [];
  const owners=[...new Set(profiles.map(profile=>profile.owner))];
  const accounts=(await store.db.query<{data:RecordData}>(
    "SELECT data FROM records WHERE kind='user' AND country=$1 AND id=ANY($2::uuid[])",[country,owners])).rows;
  const ratings=(await store.db.query<any>(`
    SELECT data->>'target_id' AS target_id, count(*) AS count, avg((data->>'rating')::numeric) AS average
    FROM records WHERE kind='review' AND country=$1 AND data->>'target_id'=ANY($2::text[])
    AND data->>'status'='published' AND COALESCE(data->>'moderation_status','') NOT IN ('quarantined','hidden','rejected')
    GROUP BY data->>'target_id'`,[country,owners])).rows;
  const completed=(await store.db.query<any>(`SELECT data->>'executor_id' AS actor_id,count(*) AS count FROM records WHERE kind='order' AND country=$1 AND data->>'status'='completed' AND data->>'executor_id'=ANY($2::text[]) GROUP BY data->>'executor_id'`,[country,owners])).rows;
  const portfolios=(await store.db.query<any>(`SELECT owner AS actor_id,count(*) AS count FROM records WHERE kind='portfolio' AND country=$1 AND owner=ANY($2::text[]) AND data->>'status'='published' AND COALESCE(data->>'moderation_status','') NOT IN ('quarantined','hidden','rejected') GROUP BY owner`,[country,owners])).rows;
  const verifications=(await store.db.query<any>(`SELECT owner AS actor_id,max(data->>'decided_at') AS checked_at FROM records WHERE kind='verification' AND country=$1 AND owner=ANY($2::text[]) AND data->>'status'='passed' AND data->>'expires_at'>$3 GROUP BY owner`,[country,owners,new Date().toISOString()])).rows;
  return profiles.map(profile=>{
    const account=accounts.find(account=>account.data.id===profile.owner)?.data;
    const rating=ratings.find(rating=>rating.target_id===profile.owner);
    return {...publicContent(profile),display_name:account?.display_name??'',owner_avatar_id:account?.avatar_id??null,
      rating:{count:Number(rating?.count??0),average:rating?Number(rating.average):null},
      completed_orders:Number(completed.find(r=>r.actor_id===profile.owner)?.count??0),portfolio_count:Number(portfolios.find(r=>r.actor_id===profile.owner)?.count??0),
      verification:{status:account?.verification??'not_started',checked_at:verifications.find(r=>r.actor_id===profile.owner)?.checked_at??null}};
  });
}
