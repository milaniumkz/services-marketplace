import {RecordData} from './store';
export const supportActivity=(r:RecordData)=>String(r.last_activity??r.updated_at??r.created_at??'');
export function supportRecords(records:RecordData[],q:any,after?:string){
 const [time,id]=after?.split('|')??[];
 return records.filter(r=>r.status!=='deleted'&&(!q.owner||r.owner===q.owner)&&(!q.status||r.status===q.status)&&(!q.q||[r.id,r.subject,r.topic].join(' ').toLowerCase().includes(String(q.q).toLowerCase())))
 .sort((a,b)=>supportActivity(b).localeCompare(supportActivity(a))||b.id.localeCompare(a.id))
 .filter(r=>!time||supportActivity(r)<time||supportActivity(r)===time&&r.id<id);
}
