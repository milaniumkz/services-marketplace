import {HttpException} from '@nestjs/common';
import {Store} from './store';
import {promotedPlacements} from './promoted-listings';
function fail(message:string):never{throw new HttpException({error:{code:'VALIDATION_ERROR',message,details:{},retryable:false}},422);}
export function placementPolicyPayload(p:any){
 if(!promotedPlacements.includes(p?.placement_id)||!Number.isSafeInteger(p?.capacity)||p.capacity<1||p.capacity>100)fail('Выберите известное место и ёмкость от 1 до 100');
 return {placement_id:p.placement_id,capacity:p.capacity};
}
export async function placementPromises(store:Store,country:string,placement:string,now=new Date()){
 const time=now.getTime(),events:{time:number,delta:number}[]=[];let reservations=0,placements=0;
 for(const r of await store.all('boost',country)){
  if(r.placement_id!==placement||!['reserved','payment_pending','active','scheduled'].includes(r.status))continue;
  const reserve=['reserved','payment_pending'].includes(r.status);
  if(reserve&&!(Date.parse(r.reservation_expires_at)>time))continue;
  const start=Math.max(time,Date.parse(r.starts_at??r.created_at)),end=Date.parse(r.ends_at);
  if(!Number.isFinite(start)||!Number.isFinite(end))fail('Проверьте даты существующих размещений');
  if(end<=start)continue;
  if(reserve)reservations++;else placements++;
  events.push({time:start,delta:1},{time:end,delta:-1});
 }
 let occupied=0,peak=0;
 for(const event of events.sort((a,b)=>a.time-b.time||a.delta-b.delta)){occupied+=event.delta;peak=Math.max(peak,occupied);}
 return {promised_peak:peak,live_reservations:reservations,scheduled_or_active:placements};
}
