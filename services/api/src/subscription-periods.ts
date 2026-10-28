import {randomUUID} from 'node:crypto';
import {Store,RecordData} from './store';
import {subscriptionCapabilities,subscriptionRole} from './subscription-plans';
export const DAY_MS=86400000;
export const periodPlan=(r:RecordData)=>r.price_snapshot?.plan??r.plan??'standard';
export const periodActive=(r:RecordData,now=new Date())=>['active','grace','canceled_at_period_end','scheduled'].includes(r.status)&&Date.parse(r.valid_until)>now.getTime()&&(!r.valid_from||Date.parse(r.valid_from)<=now.getTime());
export const basePeriod=(r:RecordData)=>!r.is_upgrade&&periodPlan(r)!=='top100';
export async function userPeriods(store:Store,user:RecordData){return (await store.select('subscription',user.country,{owner:user.id,limit:1000})).filter(r=>(periodPlan(r)==='customer')===(subscriptionRole(user)==='customer'));}
export async function activatePeriods(store:Store,user:RecordData,now=new Date()){
 if(user.status!=='active')return;
 for(const s of await userPeriods(store,user))if(s.status==='scheduled'&&Date.parse(s.valid_from)<=now.getTime()&&Date.parse(s.valid_until)>now.getTime()){
  const id=s.grant_id??randomUUID();
  await store.put({id,kind:'grant',owner:user.id,country:user.country,version:1,created_at:now.toISOString(),source:s.provider==='referral'?'referral_privilege':'subscription',source_id:s.id,role:s.role??subscriptionRole(user),plan:periodPlan(s),requires_base:s.is_upgrade||periodPlan(s)==='top100',is_test:s.is_test===true,valid_until:s.valid_until,capabilities:s.is_upgrade?['top100']:subscriptionCapabilities(periodPlan(s))});
  await store.put({...s,grant_id:id,status:'active',version:s.version+1});
 }
}
export async function createPeriod(store:Store,user:RecordData,options:{plan:string;seconds:number;from?:string;price:any;provider:string;is_test?:boolean;is_upgrade?:boolean;quote_id?:string;referral_reward_id?:string},now=new Date()){
 const from=options.from?new Date(options.from):now,until=new Date(from.getTime()+options.seconds*1000),id=randomUUID(),grantId=randomUUID(),active=from.getTime()<=now.getTime();
 const s:RecordData={id,kind:'subscription',owner:user.id,country:user.country,created_at:now.toISOString(),version:1,provider:options.provider,is_test:options.is_test===true,is_upgrade:options.is_upgrade===true,checkout_quote_id:options.quote_id,referral_reward_id:options.referral_reward_id,environment:options.is_test?'sandbox':undefined,product_id:options.price.product_id??('joba.'+options.plan),status:active?'active':'scheduled',valid_from:from.toISOString(),valid_until:until.toISOString(),auto_renew:false,price_snapshot:options.price,role:subscriptionRole(user),original_transaction_id:randomUUID(),grant_id:grantId};
 await store.put(s);
 if(active)await store.put({id:grantId,kind:'grant',owner:user.id,country:user.country,created_at:now.toISOString(),version:1,source:options.provider==='referral'?'referral_privilege':'subscription',source_id:id,role:subscriptionRole(user),plan:options.plan,requires_base:options.is_upgrade||options.plan==='top100',is_test:options.is_test===true,valid_until:s.valid_until,capabilities:options.is_upgrade?['top100']:subscriptionCapabilities(options.plan)});
 return s;
}
export function presentSubscription(r:RecordData,now=new Date()){
 return {id:r.id,provider:r.provider,product_id:r.product_id,plan:periodPlan(r),is_test:r.is_test===true,is_upgrade:r.is_upgrade===true,is_addon:periodPlan(r)==='top100',auto_renew:r.auto_renew,top100:periodPlan(r)==='premium'||periodPlan(r)==='top100',status:r.status==='scheduled'&&periodActive(r,now)?'active':r.status,valid_from:r.valid_from,valid_until:r.valid_until,price:r.price_snapshot?{amount_minor:r.price_snapshot.amount_minor,currency:r.price_snapshot.currency,period:r.price_snapshot.period,original_amount_minor:r.price_snapshot.original_amount_minor,discount_percent:r.price_snapshot.discount_percent}:null};
}
