import {HttpException} from '@nestjs/common';
import {Temporal} from '@js-temporal/polyfill';
import {RecordData} from './store';
const zones:Record<string,string>={KZ:'Asia/Almaty',RS:'Europe/Belgrade',RU:'Europe/Moscow',BY:'Europe/Minsk'};
function invalid(field:string,message:string):never{throw new HttpException({error:{code:'VALIDATION_ERROR',message,details:{field},retryable:false}},400);}
export function offerPolicy(order:RecordData,hours:number,now=new Date()){
 const time_zone=order.time_window?.time_zone??zones[order.country];
 const orderEnd=Date.parse(order.expires_at);
 const until=Math.min(now.getTime()+hours*3600000,Number.isFinite(orderEnd)?orderEnd:Infinity);
 return {time_zone,server_time:now.toISOString(),latest_expires_at:new Date(until).toISOString(),latest_expires_local:Temporal.Instant.fromEpochMilliseconds(until).toZonedDateTimeISO(time_zone).toPlainDateTime().toString({smallestUnit:'minute'})};
}
function localInstant(value:any,zone:string,field:string){
 if(typeof value!=='string'||!/^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}$/.test(value))invalid(field,'Выберите дату и время');
 try{return Temporal.PlainDateTime.from(value).toZonedDateTime(zone,{disambiguation:'reject'}).toInstant().toString();}
 catch{return invalid(field,'Дата или время не существует либо неоднозначно в часовом поясе заказа');}
}
export function offerTerms(order:RecordData,body:any,hours:number,now=new Date(),previous?:RecordData){
 const policy=offerPolicy(order,hours,now),zone=policy.time_zone;
 const startLocal=body.proposed_start_local===undefined?previous?.proposed_start_local:body.proposed_start_local;
 if(startLocal!=null&&typeof startLocal!=='string')invalid('proposed_start_local','Выберите дату и время');
 const start=startLocal?localInstant(startLocal,zone,'proposed_start_local'):undefined;
 if(start&&Date.parse(start)<=now.getTime())invalid('proposed_start_local','Начало работы должно быть в будущем');
 if(start&&order.time_window?.start_date){const date=startLocal.slice(0,10);if(date<order.time_window.start_date||date>order.time_window.end_date)invalid('proposed_start_local','Начало вне выбранных заказчиком дат');}
 const duration=body.duration_minutes===undefined?previous?.duration_minutes:body.duration_minutes;
 if(duration!=null&&(!Number.isSafeInteger(duration)||duration<=0))invalid('duration_minutes','Укажите длительность в минутах больше нуля');
 const latest=Math.min(Date.parse(policy.latest_expires_at),start?Date.parse(start):Infinity);
 const expiresLocal=body.expires_local;
 const previousExpiry=previous?(previous.expires_at??new Date(Date.parse(previous.created_at)+hours*3600000).toISOString()):undefined;
 const expires=expiresLocal===undefined?(previousExpiry??new Date(latest).toISOString()):localInstant(expiresLocal,zone,'expires_local');
 if(Date.parse(expires)<=now.getTime()||Date.parse(expires)>latest)invalid('expires_local','Срок отклика должен быть в будущем, до начала работы и в пределах срока заказа и правил страны');
 return {proposed_start_local:startLocal||null,proposed_start_at:start??null,duration_minutes:duration??null,time_zone:zone,expires_at:expires};
}
export function offerExpired(offer:RecordData,hours:number,now=new Date()){
 const end=offer.expires_at??new Date(Date.parse(offer.created_at)+hours*3600000).toISOString();
 return Date.parse(end)<=now.getTime();
}

export function presentOffer(offer:RecordData,hours:number,now=new Date()){
 const expires_at=offer.expires_at??new Date(Date.parse(offer.created_at)+hours*3600000).toISOString();
 const expires_local=Temporal.Instant.from(expires_at).toZonedDateTimeISO(offer.time_zone??zones[offer.country]).toPlainDateTime().toString({smallestUnit:'minute'});
 return {...offer,expires_at,expires_local,status:offer.status==='active'&&offerExpired(offer,hours,now)?'expired':offer.status};
}

/** Batch public participant labels and published review aggregates; never return account secrets. */
export async function offerPeople(store:import('./store').Store,country:string,offers:RecordData[]){
 if(!offers.length)return offers;
 const owners=[...new Set(offers.map(o=>o.owner))];
 const rows=await store.db.query<{id:string;display_name:string;avatar_id:string;verification:string;status:string;rating_count:string;rating_average:number|null;profile_id:string|null}>(`
   SELECT u.id,u.data->>'display_name' AS display_name,u.data->>'avatar_id' AS avatar_id,u.data->>'verification' AS verification,u.data->>'status' AS status,
    count(review.id) AS rating_count,avg((review.data->>'rating')::numeric) AS rating_average,
    (SELECT p.id FROM records p WHERE p.kind='contractor' AND p.country=u.country AND p.owner=u.id::text AND p.data->>'status'='published' AND COALESCE(p.data->>'moderation_status','') NOT IN('quarantined','hidden','rejected') LIMIT 1) AS profile_id
   FROM records u LEFT JOIN records review ON review.kind='review' AND review.country=u.country AND review.data->>'target_id'=u.id::text
     AND review.data->>'status'='published' AND COALESCE(review.data->>'moderation_status','') NOT IN('quarantined','hidden','rejected')
   WHERE u.kind='user' AND u.country=$1 AND u.id=ANY($2::uuid[]) GROUP BY u.id,u.data,u.country`,[country,owners]);
 const people=new Map(rows.rows.map(r=>[r.id,r]));
 return offers.map(offer=>{const u=people.get(offer.owner);return {...offer,executor:u?{id:u.id,display_name:u.display_name,avatar_id:u.avatar_id,verified:u.verification==='passed',available:u.status==='active'&&u.verification==='passed',profile_id:u.profile_id,rating:{count:Number(u.rating_count),average:u.rating_average==null?null:Number(u.rating_average)}}:null};});
}
