import type {Store,RecordData} from './store';
import {randomUUID} from 'node:crypto';

// All arguments are internal SQL expressions, never client-provided strings.
// Used for writes AND reads so historical unqualified votes cannot affect ranking.
export function qualifiedVoteSql(voter:string,owner:string,country:string){
 return `(${voter}::text<>${owner}::text
  AND EXISTS(SELECT 1 FROM records voting_user WHERE voting_user.kind='user' AND voting_user.id=${voter}::uuid AND voting_user.country=${country} AND voting_user.data->>'status'='active' AND COALESCE(jsonb_array_length(voting_user.data->'staff_permissions'),0)=0 AND COALESCE(voting_user.data->>'staff_access_mode','')<>'managed')
  AND EXISTS(SELECT 1 FROM records rated_user WHERE rated_user.kind='user' AND rated_user.id::text=${owner}::text AND rated_user.country=${country} AND rated_user.data->>'status'='active' AND COALESCE(jsonb_array_length(rated_user.data->'staff_permissions'),0)=0 AND COALESCE(rated_user.data->>'staff_access_mode','')<>'managed')
  AND EXISTS(SELECT 1 FROM records completed_work WHERE completed_work.kind='order' AND completed_work.country=${country} AND completed_work.data->>'status'='completed' AND ((completed_work.owner=${voter}::text AND completed_work.data->>'executor_id'=${owner}::text) OR (completed_work.owner=${owner}::text AND completed_work.data->>'executor_id'=${voter}::text))))`;
}
export async function canVoteForOwner(store:Store,voter:string,owner:string,country:string){
 const r=await store.db.query<{eligible:boolean}>(`SELECT ${qualifiedVoteSql('$1','$2','$3')} AS eligible`,[voter,owner,country]);return r.rows[0]?.eligible===true;
}

export async function recordProfileView(store:Store,viewer:RecordData,profile:RecordData){
 if(viewer.id===profile.owner||viewer.country!==profile.country||viewer.status!=='active'||viewer.staff_permissions?.length||viewer.staff_access_mode==='managed')return;
 const id=randomUUID(),record={id,kind:'profile_view',owner:viewer.id,country:profile.country,version:1,created_at:new Date().toISOString(),target_id:profile.id};
 await store.db.query('INSERT INTO records(id,kind,owner,country,version,data) VALUES($1,$2,$3,$4,1,$5::jsonb) ON CONFLICT DO NOTHING',[id,record.kind,record.owner,record.country,JSON.stringify(record)]);
}
export async function profileViewCounts(store:Store,country:string,ids:string[]){
 if(!ids.length)return new Map<string,number>();
 const r=await store.db.query<{target_id:string,count:string}>(`SELECT v.data->>'target_id' AS target_id,count(*)::text AS count FROM records v
  JOIN records visitor ON visitor.id::text=v.owner AND visitor.kind='user' AND visitor.country=v.country
  JOIN records profile ON profile.id::text=v.data->>'target_id' AND profile.kind='contractor' AND profile.country=v.country AND profile.owner<>v.owner
  WHERE v.kind='profile_view' AND v.country=$1 AND v.data->>'target_id'=ANY($2::text[]) AND visitor.data->>'status'='active'
  AND COALESCE(jsonb_array_length(visitor.data->'staff_permissions'),0)=0 AND COALESCE(visitor.data->>'staff_access_mode','')<>'managed'
  GROUP BY v.data->>'target_id'`,[country,ids]);
 return new Map(r.rows.map(x=>[x.target_id,Number(x.count)]));
}
export async function eraseProfileViews(store:Store,owner:string,country:string){
 await store.db.query("DELETE FROM records WHERE kind='profile_view' AND country=$1 AND (owner=$2 OR data->>'target_id' IN(SELECT id::text FROM records WHERE kind='contractor' AND country=$1 AND owner=$2))",[country,owner]);
}
