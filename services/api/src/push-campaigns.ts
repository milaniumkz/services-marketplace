import {Temporal} from '@js-temporal/polyfill';
import {createHash,randomUUID} from 'node:crypto';
import {HttpException} from '@nestjs/common';
import {RecordData,Store} from './store';
const fail=(message:string,status=422,code='VALIDATION_ERROR'):never=>{throw new HttpException({error:{code,message,retryable:false}},status);};
export function normalizePushPayload(value:any){
 const p={...value};try{for(const [local,utc] of [['send_local','send_at'],['deadline_local','deadline_at']]){if(p[local])p[utc]=new Date(Number(Temporal.PlainDateTime.from(p[local]).toZonedDateTime(p.time_zone,{disambiguation:'reject'}).toInstant().epochMilliseconds)).toISOString();delete p[local];}}catch{fail('Проверьте местное время и IANA часовой пояс');}return p;
}
export const campaignStates=['draft','scheduled','sending','completed','canceled'];
export function validatePushCampaign(r:RecordData){
 const p=r.payload??{};
 if(!['service','marketing'].includes(p.type))fail('Выберите категорию сообщения');
 if(p.type==='service'&&!['account','order','safety','support'].includes(p.service_purpose))fail('Укажите назначение сервисного сообщения');
 if(!Array.isArray(p.locales)||!p.locales.length||p.locales.length>4||new Set(p.locales).size!==p.locales.length||p.locales.some((l:string)=>!['ru','kk','sr','be'].includes(l)))fail('Выберите языки сообщения');
 if(!Array.isArray(p.roles)||!p.roles.length||p.roles.some((role:string)=>!['customer','executor'].includes(role)))fail('Выберите роли получателей');
 if(!Array.isArray(p.countries)||p.countries.length!==1||p.countries[0]!==r.country)fail('Кампания ограничена текущей страной сотрудника');
 for(const locale of p.locales)if(typeof p.title?.[locale]!=='string'||p.title[locale].trim().length<1||p.title[locale].length>100||typeof p.body?.[locale]!=='string'||p.body[locale].trim().length<1||p.body[locale].length>500)fail('Заполните заголовок и сообщение для каждого языка');
 const link=p.deep_link;
 if(!link||!['order','offer','conversation','profile','notification','subscription','help'].includes(link.route)||Object.keys(link).some(k=>!['route','id'].includes(k))||(['order','offer','conversation'].includes(link.route)&&!link.id)||link.id!==undefined&&!/^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i.test(link.id))fail('Выберите разрешённую ссылку и ID объекта');
 const start=Date.parse(p.send_at),end=Date.parse(p.deadline_at);
 if(!Number.isFinite(start)||!Number.isFinite(end)||end<=start||end-start>7*86400000)fail('Задайте время отправки и дедлайн в пределах 7 дней');
 if(new Date(start).toISOString()!==p.send_at||new Date(end).toISOString()!==p.deadline_at)fail('Время должно быть задано в UTC ISO 8601');
 try{new Intl.DateTimeFormat('ru',{timeZone:p.time_zone}).format(new Date());if(!p.time_zone)fail('Укажите часовой пояс');}catch{fail('Проверьте часовой пояс');}
 return {valid:true};
}
function uid(value:string){const h=createHash('sha256').update(value).digest('hex');return h.slice(0,8)+'-'+h.slice(8,12)+'-5'+h.slice(13,16)+'-'+((parseInt(h[16],16)&3)|8).toString(16)+h.slice(17,20)+'-'+h.slice(20,32);}
export async function campaignEligible(store:Store,campaign:RecordData,user:RecordData,now=new Date()){
 const p=campaign.payload;
 if(user.country!==campaign.country||!['active','restricted'].includes(user.status)||(!campaign.test_of&&user.staff_permissions?.length)||!p.locales.includes(user.locale??'ru')||!p.roles.some((role:string)=>user.roles?.includes(role)))return false;
 if(campaign.test_of&&(!user.push_test_allowed||!user.push_test_until||user.push_test_until<=now.toISOString()||!campaign.test_recipients.includes(user.id)))return false;
 if(p.type==='marketing'){
  if(user.status!=='active'||user.notification_preferences?.marketing!==true)return false;
  const consent=(await store.select('processing_consent',user.country,{owner:user.id,limit:1}))[0];if(consent?.marketing!==true)return false;
 }else if(user.notification_preferences?.service===false)return false;
 return true;
}
export async function pushPreview(store:Store,campaign:RecordData){
 validatePushCampaign(campaign);
 // Aggregate membership in SQL; consent/channel checks are repeated when claiming delivery.
 const p=campaign.payload;
 const result=await store.db.query<{count:string}>(`SELECT count(*)::text FROM records u WHERE u.kind='user' AND u.country=$1
 AND u.data->>'status'=ANY($2::text[]) AND COALESCE(jsonb_array_length(u.data->'staff_permissions'),0)=0
 AND COALESCE(u.data->>'locale','ru')=ANY($3::text[]) AND u.data->'roles' ?| $4::text[]
 AND ($5::text='service' AND COALESCE(u.data->'notification_preferences'->>'service','true')='true' OR $5='marketing' AND u.data->'notification_preferences'->>'marketing'='true' AND EXISTS(SELECT 1 FROM records c WHERE c.kind='processing_consent' AND c.country=u.country AND c.owner=u.id::text AND c.data->>'marketing'='true'))`,[campaign.country,p.type==='marketing'?['active']:['active','restricted'],p.locales,p.roles,p.type]);
 return {campaign_id:campaign.id,source_version:campaign.version,audience_count:Number(result.rows[0].count),samples:p.locales.map((locale:string)=>({locale,title:p.title[locale],body:p.body[locale],deep_link:p.deep_link})),send_at:p.send_at,deadline_at:p.deadline_at,time_zone:p.time_zone,applied:false};
}
export async function queuePushCampaigns(store:Store,now=new Date()){
 const recipients=new Set<string>();
 for(const original of (await store.all('push_campaign')).filter(r=>['scheduled','sending'].includes(r.status))){
  if(original.payload.send_at>now.toISOString())continue;
  let c=original;
  if(c.status==='scheduled'){c={...c,status:'sending',audience_cutoff:now.toISOString(),version:c.version+1};await store.put(c);}
  if(c.payload.deadline_at<=now.toISOString()){
   for(const o of (await store.db.query<{data:RecordData}>("SELECT data FROM records WHERE kind='outbox' AND country=$1 AND data->>'campaign_id'=$2 AND data->>'status' IN('pending','retry','waiting_token')",[c.country,c.id])).rows)await store.put({...o.data,status:'expired',version:o.data.version+1});
   c={...c,queue_complete:true,version:c.version+1};await store.put(c);await refreshPushCampaign(store,c,now);continue;
  }
  if(c.queue_complete){await refreshPushCampaign(store,c,now);continue;}
  const batch=await store.db.query<{data:RecordData}>(`SELECT data FROM records WHERE kind='user' AND country=$1 AND id::text>$2 AND data->>'created_at'<=$3 AND ($4::uuid[] IS NULL OR id=ANY($4::uuid[])) ORDER BY id LIMIT 100`,[c.country,c.audience_cursor??'',c.audience_cutoff,c.test_of?c.test_recipients:null]);
  let queued=c.queued??0,skipped=c.skipped??0;
  for(const {data:user} of batch.rows){
   if(!await campaignEligible(store,c,user,now)){skipped++;continue;}
   const id=uid(c.id+':'+user.id+':outbox');if(await store.get(id))continue;
   const locale=user.locale??'ru',eventId=uid(c.id+':'+user.id+':notification'),base={owner:user.id,country:c.country,version:1,created_at:now.toISOString()},type=c.payload.type==='marketing'?'marketing.campaign':'service.campaign';
   await store.put({...base,id:eventId,kind:'notification',type,target_id:c.id,campaign_id:c.id,title:c.payload.title[locale],body:c.payload.body[locale],deep_link:c.payload.deep_link,read:false});
   await store.db.query('INSERT INTO events(event_id,recipient_id,country,data) VALUES($1,$2,$3,$4) ON CONFLICT(event_id) DO NOTHING',[eventId,user.id,c.country,JSON.stringify({event_id:eventId,type,aggregate_id:c.id,occurred_at:now.toISOString()})]);
   recipients.add(user.id);
   await store.put({...base,id,kind:'outbox',type,campaign_id:c.id,campaign_type:c.payload.type,target_id:c.id,recipient_id:user.id,event_id:eventId,status:'pending',attempts:0,deadline_at:c.payload.deadline_at});queued++;
  }
  c={...c,queued,skipped,audience_cursor:batch.rows.at(-1)?.data.id??c.audience_cursor,queue_complete:batch.rows.length<100,version:c.version+1};await store.put(c);await refreshPushCampaign(store,c,now);
 }
 return [...recipients];
}
export async function refreshPushCampaign(store:Store,c:RecordData,now=new Date()){
 if(c.status!=='sending'||!c.queue_complete)return;
 const rows=(await store.db.query<{status:string,count:string}>("SELECT data->>'status' AS status,count(*)::text FROM records WHERE kind='outbox' AND country=$1 AND data->>'campaign_id'=$2 GROUP BY 1",[c.country,c.id])).rows;
 const active=rows.some(r=>['pending','retry','waiting_token','processing'].includes(r.status));
 if(!active)await store.put({...c,status:'completed',delivery_counts:Object.fromEntries(rows.map(r=>[r.status,Number(r.count)])),completed_at:now.toISOString(),version:c.version+1});
}
export async function cancelPushCampaign(store:Store,c:RecordData){
 for(const {data:o} of (await store.db.query<{data:RecordData}>("SELECT data FROM records WHERE kind='outbox' AND country=$1 AND data->>'campaign_id'=$2 AND data->>'status' IN('pending','retry','waiting_token')",[c.country,c.id])).rows)await store.put({...o,status:'canceled',version:o.version+1});
 return store.put({...c,status:'canceled',canceled_at:new Date().toISOString(),version:c.version+1});
}
export async function claimCampaignMessage(store:Store,entry:RecordData,user:RecordData,now:Date):Promise<{stop?:string;retry?:string;message?:any}>{
 const c=await store.get(entry.campaign_id);
 if(!c||c.country!==entry.country||c.status==='canceled')return {stop:'canceled'};
 if(c.payload.deadline_at<=now.toISOString())return {stop:'expired'};
 if(!await campaignEligible(store,c,user,now))return {stop:'suppressed'};
 const locale=user.locale??'ru';if(!c.payload.locales.includes(locale))return {stop:'suppressed'};
 if(c.payload.type==='marketing'){
  const counts=(await store.db.query<{daily:string;weekly:string}>(`SELECT count(*) FILTER(WHERE COALESCE(data->>'claimed_at',data->>'sent_at')>$4)::text AS daily,count(*)::text AS weekly FROM records WHERE kind='outbox' AND country=$1 AND data->>'recipient_id'=$2 AND id::text<>$3 AND data->>'campaign_type'='marketing' AND data->>'status' IN('processing','sent') AND COALESCE(data->>'claimed_at',data->>'sent_at')>$5`,[entry.country,user.id,entry.id,new Date(now.getTime()-86400000).toISOString(),new Date(now.getTime()-7*86400000).toISOString()])).rows[0];
  if(Number(counts.daily)>=1||Number(counts.weekly)>=3)return {retry:new Date(now.getTime()+3600000).toISOString()};
 }
 return {message:{event_id:entry.event_id,title:c.payload.title[locale],body:c.payload.body[locale],deep_link:c.payload.deep_link,campaign_id:c.id}};
}
export function testCampaign(c:RecordData,actor:string,ids:string[],now=new Date()):RecordData {
 return {...c,id:randomUUID(),owner:actor,version:1,created_at:now.toISOString(),status:'scheduled',test_of:c.id,test_recipients:ids,payload:{...c.payload,send_at:now.toISOString(),deadline_at:new Date(now.getTime()+3600000).toISOString()},audience_cursor:null,queue_complete:false,queued:0,skipped:0};
}
