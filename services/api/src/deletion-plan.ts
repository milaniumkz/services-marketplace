import {HttpException} from '@nestjs/common';
import {Store,RecordData} from './store';
export const retentionFields={chat_days:{label:'Чаты и материалы закрытых заказов',max:3650},security_days:{label:'События безопасности',max:3650},logs_days:{label:'Технические журналы',max:3650},financial_days:{label:'Финансовые записи',max:36500},audit_days:{label:'Аудиторские записи',max:36500}};
export function validateRetentionCategories(payload:any){
 for(const [key,rule] of Object.entries(retentionFields))if(payload[key]!==undefined&&(!Number.isSafeInteger(payload[key])||payload[key]<1||payload[key]>rule.max))throw new HttpException({error:{code:'VALIDATION_ERROR',message:'Проверьте срок: '+rule.label,details:{field:key},retryable:false}},422);
}
const groups=[
 {id:'profile',label:'Аккаунт и публичные материалы',kinds:['user','contractor','portfolio','content_revision'],action:'anonymize_now',anchor:'deletion_execution'},
 {id:'sessions',label:'Сессии, устройства и ссылки загрузки',kinds:['push_token','download_ticket'],action:'revoke_now',anchor:'deletion_execution'},
 {id:'documents',label:'Проверка личности',kinds:['verification'],action:'retain_until_policy',policy:'document_days',anchor:'verification_final_decision'},
 {id:'work',label:'Заказы, отклики и переписки',kinds:['order','offer','invite','assignment','conversation','message','message_revision','review','review_revision'],action:'minimize_after_closure',policy:'chat_days',anchor:'linked_order_closure'},
 {id:'support',label:'Поддержка, споры и доказательства',kinds:['support','support_message','support_note','case','case_message','case_decision','moderation_episode','legal_hold','blacklist','auto_hold'],action:'retain_held_fields',policy:'audit_days',anchor:'case_or_thread_closure'},
 {id:'finance',label:'Платежи, возвраты и права доступа',kinds:['payment_transaction','subscription','refund_request','purchase_check','grant','boost','entitlement_consumption','ad_reward','ad_session','referral_code','referral_attribution','referral_reservation','referral_reward','compensation_request','webhook_inbox'],action:'retain_required_fields',policy:'financial_days',anchor:'financial_event'},
 {id:'audit',label:'Аудит и подтверждения согласий',kinds:['audit','consent','processing_consent','processing_consent_event','privacy'],action:'retain_required_fields',policy:'audit_days',anchor:'record_creation'},
 {id:'security',label:'События безопасности',kinds:['security_event'],action:'minimize_after_policy',policy:'security_days',anchor:'event_creation'},
 {id:'notifications',label:'Уведомления и очередь доставки',kinds:['notification','outbox'],action:'minimize_after_policy',policy:'logs_days',anchor:'event_creation'},
 {id:'files',label:'Файлы и фотографии',kinds:['upload'],action:'purpose_and_hold_policy',anchor:'file_purpose'},
];
/** Classification only: deadlines anchored to another event are never guessed from deletion time. */
export async function deletionPlan(store:Store,owner:string,country:string,policy:RecordData|undefined,now:Date,phase='preview'){
 const rows=await store.db.query<{kind:string,count:string}>("SELECT kind,count(*)::text AS count FROM records WHERE country=$1 AND (owner=$2 OR data->>'subject_user_id'=$2 OR data->>'executor_id'=$2 OR kind='audit' AND data->>'target_id'=$2 OR COALESCE(data->'members','[]'::jsonb) ? $2) GROUP BY kind",[country,owner]);
 const known=new Set(groups.flatMap(x=>x.kinds));
 const categories=groups.map(g=>{const days=g.policy?policy?.payload?.[g.policy]:undefined;return {category:g.id,label:g.label,count:rows.rows.filter(x=>g.kinds.includes(x.kind)).reduce((sum,x)=>sum+Number(x.count),0),action:g.action,anchor:g.anchor,retention_days:days??null,policy_required:Boolean(g.policy),policy_ready:!g.policy||Number.isSafeInteger(days)&&days>0,execution_state:['anonymize_now','revoke_now'].includes(g.action)?(phase==='account_removed'?'immediate_done':'planned_immediate_step'):'pending_category_worker'};});
 const unknown=rows.rows.filter(x=>!known.has(x.kind));
 if(unknown.length)categories.push({category:'unclassified',label:'Дополнительные категории требуют проверки',count:unknown.reduce((sum,x)=>sum+Number(x.count),0),action:'retain_for_review',anchor:'manual_review',retention_days:null,policy_required:true,policy_ready:false,execution_state:'pending_category_worker'});
 const auth=await store.db.query<{count:string}>("SELECT ((SELECT count(*) FROM credentials WHERE country=$1 AND user_id=$2)+(SELECT count(*) FROM tokens WHERE country=$1 AND user_id=$2))::text AS count",[country,owner]);
 categories.find(c=>c.category==='sessions')!.count+=Number(auth.rows[0].count);
 const purposes=await store.db.query<{purpose:string,count:string}>("SELECT COALESCE(data->>'purpose','unknown') AS purpose,count(*)::text AS count FROM records WHERE kind='upload' AND country=$1 AND owner=$2 GROUP BY 1",[country,owner]);
 const fileRules:Record<string,{label:string;action:string;anchor:string;policy?:string;days?:number}>={
  avatar:{label:'Аватары',action:'purge_unheld_after_deletion',anchor:'deletion_execution',days:0},
  portfolio:{label:'Фотографии профиля и проектов',action:'purge_unheld_after_deletion',anchor:'deletion_execution',days:0},
  export:{label:'Архивы экспорта',action:'revoke_and_purge_unheld_after_deletion',anchor:'deletion_execution',days:0},
  identity:{label:'Исходники документов',action:'purge_unheld_after_policy',anchor:'verification_final_decision',policy:'document_days'},
  order:{label:'Вложения заказов',action:'purge_unheld_after_closure',anchor:'linked_order_closure',policy:'chat_days'},
  chat:{label:'Вложения переписок',action:'purge_unheld_after_closure',anchor:'linked_order_closure',policy:'chat_days'},
  brand:{label:'Материалы бренда',action:'company_asset_review',anchor:'company_decision'},
  banner:{label:'Креативы кампаний',action:'company_asset_review',anchor:'company_decision'}
 };
 const fileCategories=purposes.rows.map(x=>{const rule=fileRules[x.purpose],days=rule?.days??(rule?.policy?policy?.payload?.[rule.policy]:undefined);return {category:rule?x.purpose:'other',label:rule?.label??'Прочие файлы',count:Number(x.count),action:rule?.action??'retain_for_review',anchor:rule?.anchor??'manual_review',retention_days:days??null,policy_ready:days!==undefined,execution_state:['avatar','portfolio','export'].includes(x.purpose)?phase==='account_removed'?'personal_media_step':'planned_personal_media_step':'pending_category_worker'};});
 const holds=await store.db.query<{count:string}>("SELECT count(*)::text AS count FROM records WHERE kind='legal_hold' AND country=$1 AND data->>'subject_user_id'=$2 AND data->>'status'='active'",[country,owner]);
 return {file_categories:fileCategories,phase,policy_id:policy?.id??null,policy_version:policy?.version??null,generated_at:now.toISOString(),categories,unclassified_types:unknown.length,active_holds:Number(holds.rows[0].count),missing_policy_categories:[...categories.filter(x=>x.count>0&&!x.policy_ready).map(x=>x.category),...fileCategories.filter(x=>x.count>0&&!x.policy_ready).map(x=>'file:'+x.category)],fully_erased:false};
}
/** Keep only anonymous identifiers and explicitly held file references, never profile drafts/GPS/contact data. */
export async function anonymizeProfile(store:Store,record:RecordData){
 const holds=(await store.db.query<{data:RecordData}>("SELECT data FROM records WHERE kind='legal_hold' AND country=$1 AND data->>'target_id'=$2 AND data->>'status'='active'",[record.country,record.id])).rows.map(x=>x.data);
 const held=Object.fromEntries(['gallery_ids','photos'].filter(field=>holds.some(h=>h.fields.includes(field))&&record[field]!==undefined).map(field=>[field,record[field]]));
 return store.put({id:record.id,kind:record.kind,owner:record.owner,country:record.country,created_at:record.created_at,version:record.version+1,status:'archived',...held,...(record.source_id?{source_id:record.source_id,source_kind:record.source_kind}:{})},{skipContentCheck:true});
}
