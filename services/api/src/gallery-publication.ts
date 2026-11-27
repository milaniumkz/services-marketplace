import {randomUUID} from 'node:crypto';
import {Store} from './store';
/** Repair photos already saved by older apps without exposing unrelated drafts. */
export async function publishSavedGalleries(store:Store){
 let updated=0;await store.db.exec('BEGIN');try{await store.db.query('SELECT pg_advisory_xact_lock(1752138232)');
 for(const item of await store.all('contractor')){const p=await store.get(item.id);if(!p||!['published','paused'].includes(p.status)||['hidden','quarantined','rejected'].includes(p.moderation_status)||!Array.isArray(p.draft?.gallery_ids)||JSON.stringify(p.gallery_ids??[])===JSON.stringify(p.draft.gallery_ids))continue;
  const user=await store.get(p.owner),ids=p.draft.gallery_ids;if(user?.status!=='active'||ids.length>20||new Set(ids).size!==ids.length)continue;
  const uploads=await Promise.all(ids.map((id:string)=>store.get(id)));if(uploads.some(u=>!u||u.owner!==p.owner||u.country!==p.country||u.purpose!=='portfolio'||u.status!=='clean'))continue;
  await store.put({...p,gallery_ids:ids,published_version:p.version+1,version:p.version+1});await store.put({id:randomUUID(),kind:'audit',owner:p.owner,country:p.country,version:1,created_at:new Date().toISOString(),action:'contractor.saved_gallery_published',target_id:p.id,reason:'По запросу владельца: сохранённые фотографии услуг доступны в публичном портфолио; остальные поля черновика сохранены приватными'});updated++;
 }await store.db.exec('COMMIT');return updated;}catch(e){await store.db.exec('ROLLBACK');throw e;}
}
