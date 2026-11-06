import {Temporal} from '@js-temporal/polyfill';
import {HttpException} from '@nestjs/common';
import {Store,RecordData} from './store';
const fail=(status:number,code:string,message:string):never=>{throw new HttpException({error:{code,message,details:{},retryable:status===503}},status);};
const text=(v:any,min:number,max:number)=>{if(typeof v!=='string'||v.trim().length<min||v.length>max)fail(422,'VALIDATION_ERROR','Проверьте обязательные поля кампании');return v.trim();};
export function bannerPayload(value:any,country:string){
 const p=value??{},zone=({KZ:'Asia/Almaty',KG:'Asia/Bishkek',RU:'Europe/Moscow',BY:'Europe/Minsk'} as Record<string,string>)[country];
 if(p.time_zone!==zone)fail(422,'VALIDATION_ERROR','Выберите часовой пояс страны кампании');
 const instant=(v:any)=>{try{if(typeof v!=='string'||!/^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}$/.test(v))throw Error();return Temporal.PlainDateTime.from(v).toZonedDateTime(zone,{disambiguation:'reject'}).toInstant().toString();}catch{fail(422,'VALIDATION_ERROR','Проверьте местное время; неоднозначное время DST недопустимо');}};
 const valid_from=instant(p.start_local)!,valid_until=instant(p.end_local)!;
 if(Date.parse(valid_until)<=Date.parse(valid_from))fail(422,'VALIDATION_ERROR','Окончание должно быть позже начала');
 if(!['catalog.inline','catalog.inline.end','home.inline','top.inline'].includes(p.placement))fail(422,'VALIDATION_ERROR','Недопустимое размещение баннера');
 if(!['home','catalog','top'].includes(p.destination))fail(422,'VALIDATION_ERROR','Выберите внутренний экран назначения');
 for(const [key,max] of [['budget_minor',100000000000],['daily_limit',1000000],['screen_interval',100]] as const)if(!Number.isSafeInteger(p[key])||p[key]<1||p[key]>max)fail(422,'VALIDATION_ERROR','Проверьте бюджет и лимиты');
 return {headline:text(p.headline,3,100),caption:text(p.caption,0,300),placement:p.placement,destination:p.destination,time_zone:zone,start_local:p.start_local,end_local:p.end_local,valid_from,valid_until,budget_minor:p.budget_minor,currency:({KZ:'KZT',KG:'KGS',RU:'RUB',BY:'BYN'} as Record<string,string>)[country],daily_limit:p.daily_limit,screen_interval:p.screen_interval,...(p.creative_id?{creative_id:text(p.creative_id,36,36)}:{})};
}
type Actor={id:string;country:string};
type Context={object:(id:string)=>Promise<RecordData>;record:(data:any)=>RecordData;audit:(action:string,id:string,reason:string)=>Promise<any>};
export async function bannerCampaigns(store:Store,a:Actor,method:string,path:string,b:any,ctx:Context){
 const match=path.match(/^\/admin\/banner-campaigns(?:\/([^/]+)(?:\/(validate|submit|approve|reject|publish|stop))?)?$/);if(!match)return undefined;
 const save=async(r:RecordData,action:string,reason:string)=>{const next={...r,history:[...(r.history??[]),{action,actor_id:a.id,version:r.version,reason,at:new Date().toISOString()}]};await store.put(next);await ctx.audit('banner.'+action,r.id,reason);return next;};
 if(!match[1]&&method==='POST')return save(ctx.record({title:text(b.title,3,120),payload:bannerPayload(b.payload,a.country),status:'draft'}),'created',text(b.reason,5,1000));
 if(!match[1])return undefined;
 const r=await ctx.object(match[1]);if(method==='GET'&&!match[2])return r;
 if(b.expected_version!==r.version)fail(409,'STATE_CONFLICT','Версия изменилась. Обновите данные');
 const reason=text(b.reason,5,1000);
 const validate=async()=>{const p=bannerPayload(r.payload,a.country);if(Date.parse(p.valid_until)<=Date.now())fail(422,'CAMPAIGN_EXPIRED','Период кампании завершён');const u=await store.get(p.creative_id??'');if(!u||u.kind!=='upload'||u.country!==a.country||u.purpose!=='banner'||u.status!=='clean'||!['image/png','image/jpeg'].includes(u.mime))fail(422,'UNSAFE_UPLOAD','Добавьте проверенный креатив баннера');return {valid:true,source_id:r.id,source_version:r.version,provider_connected:false};};
 if(method==='PATCH'&&!match[2]){if(r.owner!==a.id||!['draft','rejected'].includes(r.status))fail(409,'STATE_CONFLICT','Изменять можно только собственный черновик или отклонённую кампанию');return save({...r,title:text(b.title,3,120),payload:bannerPayload(b.payload,a.country),status:'draft',version:r.version+1},'updated',reason);}
 if(method!=='POST')return undefined;
 if(match[2]==='validate')return validate();
 if(match[2]==='publish'){if(r.status!=='approved')fail(409,'STATE_CONFLICT','Сначала требуется согласование кампании');await validate();fail(503,'BANNER_PROVIDER_UNAVAILABLE','Рекламный провайдер ещё не подключён. Показы не включены');}
 const action=match[2];let status:string;
 if(action==='submit'){if(r.owner!==a.id||!['draft','rejected'].includes(r.status))fail(409,'STATE_CONFLICT','Кампания не принимает отправку');await validate();status='pending_review';}
 else if(action==='approve'||action==='reject'){if(r.status!=='pending_review')fail(409,'STATE_CONFLICT','Кампания не ожидает проверки');if(r.owner===a.id)fail(403,'INDEPENDENT_APPROVAL_REQUIRED','Проверку выполняет другой сотрудник');if(action==='approve')await validate();status=action==='approve'?'approved':'rejected';}
 else if(action==='stop'){if(!['draft','pending_review','approved','rejected'].includes(r.status))fail(409,'STATE_CONFLICT','Остановить эту кампанию локально нельзя');status='stopped';}
 else return undefined;
 return save({...r,status,version:r.version+1,...(action==='approve'?{approved_by:a.id,approved_at:new Date().toISOString()}:{} )},action!,reason);
}
