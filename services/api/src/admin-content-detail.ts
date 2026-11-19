import {Store,RecordData} from './store';
import {editableContent} from './content-revisions';

export async function adminContentDetail(store:Store,record:RecordData,grants?:string[]) {
 const can=(path:string)=>!grants||grants.includes('GET /admin/'+path);
 const owner=await store.get(record.owner),content=editableContent(record);
 const subject=owner?.kind==='user'&&owner.country===record.country?{
  id:owner.id,display_name:owner.display_name,city:owner.city,country:owner.country,
  roles:owner.roles,active_role:owner.active_role,status:owner.status,verification:owner.verification,
  created_at:owner.created_at,avatar_id:owner.avatar_id,
  phone_masked:owner.phone?'•••• '+String(owner.phone).slice(-4):null
 }:null;
 const related=async(kind:string,path:string)=>can(path)?(await store.db.query<{data:RecordData}>(
  'SELECT data FROM records WHERE kind=$1 AND country=$2 AND owner=$3 ORDER BY data->>\'created_at\' DESC,id LIMIT 20',
  [kind,record.country,record.owner])).rows.map(({data})=>{const r=editableContent(data);return {id:r.id,title:r.title,status:r.status,version:r.version,created_at:r.created_at};}):[];
 const [portfolio,services,verifications]=await Promise.all([related('portfolio','portfolio'),related('contractor','contractors'),related('verification','verifications')]);
 const ids=[...new Set([content.category_id,...content.category_ids??[]].filter(Boolean))];
 const categories=await Promise.all(ids.map(async id=>{const c=(await store.db.query<{data:RecordData}>("SELECT data FROM records WHERE kind='category' AND country=$1 AND (id::text=$2 OR data->>'legacy_id'=$2) LIMIT 1",[record.country,id])).rows[0]?.data;return c?{id,name:c.title??c.name??id}: {id,name:id};}));
 return {...content,subject,categories,related:{portfolio,services,verifications},related_limit:20};
}
