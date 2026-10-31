import {communicationLanguages} from './communication-languages';
import {HttpException} from '@nestjs/common';
import {Store} from './store';
const fail=(message:string):never=>{throw new HttpException({error:{code:'VALIDATION_ERROR',message,retryable:false}},400);};
/** Read reports after the caller has enforced the section's staff permission and MFA. */
export async function adminReports(store:Store,country:string,method:string,path:string,query:any) {
 if(method!=='GET')return undefined;
 if(path==='/admin/languages'){
  const catalog=await communicationLanguages(store,country),languages=catalog.items;
  const rows=await store.db.query<{locale:string,count:string}>("SELECT COALESCE(data->>'locale','ru') AS locale,count(*)::text FROM records WHERE kind='user' AND country=$1 AND data->>'status'<>'deleted' GROUP BY 1",[country]);
  return {country,version:catalog.version,items:languages.map(l=>({...l,active_users:Number(rows.rows.find(r=>r.locale===l.code)?.count??0)})),read_only:false};
 }
 if(path==='/admin/revenue'){
  const days=query.days===undefined?30:Number(query.days);if(![7,30,90].includes(days))fail('Выберите период 7, 30 или 90 дней');
  const until=new Date(),since=new Date(until.getTime()-days*86400000);
  const records=(await store.all('ad_revenue',country)).filter(r=>r.period_start>=since.toISOString()&&r.period_end<=until.toISOString());
  const groups=new Map<string,any>();
  for(const r of records){
   if(!['estimated','finalized'].includes(r.status)||!Number.isSafeInteger(r.amount_minor)||typeof r.currency!=='string'||typeof r.provider!=='string')continue;
   const key=JSON.stringify([r.provider,r.currency,r.status]),row=groups.get(key)??{provider:r.provider,currency:r.currency,status:r.status,amount_minor:0,received_at:null,period_start:r.period_start,period_end:r.period_end};
   row.amount_minor+=r.amount_minor;row.received_at=row.received_at===null||r.received_at>row.received_at?r.received_at:row.received_at;groups.set(key,row);
  }
  return {country,period:{from:since.toISOString(),until:until.toISOString(),days},items:[...groups.values()],data_available:groups.size>0,note:'Оценки и финальные отчёты по валютам отдельно. Отсутствие отчётов не означает нулевой доход.',generated_at:until.toISOString()};
 }
 return undefined;
}
