import {Store,RecordData} from './store';
export async function adminReviewQueues(store:Store,country:string,grants?:string[]) {
 const definitions=[
  {key:'customers',label:'Заказчики — проверка личности',kind:'verification',endpoint:'verifications',route:'verification',role:'customer'},
  {key:'executors',label:'Исполнители — проверка личности',kind:'verification',endpoint:'verifications',route:'verification',role:'executor'},
  {key:'portfolio',label:'Портфолио на проверке',kind:'portfolio',endpoint:'portfolio',route:'portfolio'},
  {key:'contractors',label:'Услуги исполнителей на проверке',kind:'contractor',endpoint:'contractors',route:'contractors'},
  {key:'cases',label:'Жалобы и модерация',kind:'case',endpoint:'cases',route:'moderation'},
  {key:'support',label:'Обращения в поддержку',kind:'support',endpoint:'support-threads',route:'support'},
  {key:'refunds',label:'Запросы возврата',kind:'refund_request',endpoint:'refund-requests',route:'refunds'},
  {key:'privacy',label:'Запросы приватности',kind:'privacy',endpoint:'privacy-requests',route:'privacy'}
 ];
 const queues=[];
 for(const d of definitions){
  if(grants&&!grants.includes('GET /admin/'+d.endpoint))continue;
  const state="COALESCE(r.data->'draft'->>'status',r.data->>'status')";
  const condition=['verification','portfolio','contractor'].includes(d.kind)?`${state} IN ('pending_review','pending_moderation')`:
    d.kind==='refund_request'?`${state}='requested'`:d.kind==='privacy'?`${state} IN ('requested','processing','failed')`:`${state} NOT IN ('resolved','closed')`;
  const role="COALESCE(r.data->>'submitted_role',u.data->>'active_role','customer')";
  const result=await store.db.query<{data:RecordData,total:string,display_name:string}>(`SELECT r.data,count(*) OVER() AS total,u.data->>'display_name' AS display_name FROM records r LEFT JOIN records u ON u.id::text=r.owner AND u.kind='user' AND u.country=r.country WHERE r.country=$1 AND r.kind=$2 AND ${condition} ${d.role?`AND ${role}=$3`:''} ORDER BY r.data->>'created_at',r.id LIMIT 5`,d.role?[country,d.kind,d.role]:[country,d.kind]);
  const params=new URLSearchParams({...(d.role?{status:'pending_review',owner_role:d.role}:['portfolio','contractor'].includes(d.kind)?{status:'pending_review'}:{})});
  queues.push({key:d.key,label:d.label,count:Number(result.rows[0]?.total??0),href:'#'+d.route+(params.size?'?'+params:''),items:result.rows.map(({data:r,display_name})=>({id:r.id,title:r.draft?.title??r.title??r.subject??display_name??r.id,status:r.draft?.status??r.status,created_at:r.created_at,href:d.route==='moderation'?'#case-live/'+r.id:d.route==='support'?'#support-live/'+r.id:d.route==='refunds'?'#refunds?id='+r.id:'#record-live/'+d.route+'/'+r.id}))});
 }
 const visible=definitions.filter(d=>!grants||grants.includes('GET /admin/'+d.endpoint));
 const kinds=[...new Set(visible.map(d=>d.kind))];
 const recent=kinds.length?(await store.db.query<{data:RecordData}>(`SELECT data FROM records WHERE country=$1 AND kind=ANY($2::text[]) AND COALESCE(data->'draft'->>'status',data->>'status') NOT IN ('draft','archived') ORDER BY COALESCE(data->>'decided_at',data->>'updated_at',data->>'published_at',data->>'created_at') DESC,id LIMIT 20`,[country,kinds])).rows:[];
 const activity=recent.map(({data:r})=>{const d=visible.find(d=>d.kind===r.kind)!;return {id:r.id,label:({verification:'Проверка личности',portfolio:'Портфолио',contractor:'Услуги исполнителя',case:'Жалоба',support:'Поддержка',refund_request:'Возврат',privacy:'Приватность'} as Record<string,string>)[r.kind],title:r.draft?.title??r.title??r.subject??r.id,status:r.draft?.status??r.status,occurred_at:r.decided_at??r.updated_at??r.published_at??r.created_at,href:d.route==='moderation'?'#case-live/'+r.id:d.route==='support'?'#support-live/'+r.id:d.route==='refunds'?'#refunds?id='+r.id:'#record-live/'+d.route+'/'+r.id};});
 return {queues,activity,activity_limit:20,refresh_seconds:30,items_per_queue:5};
}
