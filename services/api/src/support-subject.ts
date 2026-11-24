import {RecordData,Store} from './store';
/** Support staff see the sender of their own regional case, never raw contacts. */
export async function supportSubjects(store:Store,threads:RecordData[]){
 const owners=new Map<string,RecordData|undefined>();
 for(const id of new Set(threads.filter(t=>!t.retention_minimized_at).map(t=>t.owner)))owners.set(id,await store.get(id));
 return threads.map(t=>{const u=t.retention_minimized_at?undefined:owners.get(t.owner),visible=u?.kind==='user'&&u.country===t.country&&u.status!=='deleted';return {...t,subject_user:visible?{id:u!.id,display_name:u!.display_name,country:u!.country,city:u!.city,roles:u!.roles,active_role:u!.active_role,status:u!.status,phone_masked:u!.phone?'•••• '+String(u!.phone).slice(-4):null}:null};});
}
