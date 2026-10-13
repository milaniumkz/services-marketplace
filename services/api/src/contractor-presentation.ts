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
  return profiles.map(profile=>{
    const account=accounts.find(account=>account.data.id===profile.owner)?.data;
    const rating=ratings.find(rating=>rating.target_id===profile.owner);
    return {...publicContent(profile),display_name:account?.display_name??'',owner_avatar_id:account?.avatar_id??null,
      rating:{count:Number(rating?.count??0),average:rating?Number(rating.average):null}};
  });
}
