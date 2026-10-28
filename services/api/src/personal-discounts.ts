import {randomUUID} from 'node:crypto';
import {HttpException} from '@nestjs/common';
import {Store,RecordData} from './store';
export const discountServices=['standard','premium','customer','renewal','upgrade','top100','boost'] as const;
async function holds(store:Store,user:{id:string;country:string},now:Date,exclude?:string){return (await store.select('boost',user.country,{owner:user.id,limit:1000})).filter(b=>b.id!==exclude&&['reserved','payment_pending'].includes(b.status)&&b.reservation_expires_at>now.toISOString());}
export async function bestDiscount(store:Store,user:RecordData,service:string,action?:string,now=new Date()){
 const reserved=await holds(store,user as {id:string;country:string},now);
 const rows=(await store.select('referral_discount',user.country,{owner:user.id,limit:1000})).filter(d=>d.status==='active'&&d.valid_until>now.toISOString()&&(!d.max_uses||(d.uses??0)+reserved.filter(b=>b.price_snapshot?.discount_id===d.id).length<d.max_uses)&&(d.services?.includes('all')||d.services?.includes(service)||action&&d.services?.includes(action)));
 return rows.sort((a,b)=>b.percent-a.percent||a.valid_until.localeCompare(b.valid_until)||a.id.localeCompare(b.id))[0];
}
export function discountedPrice(amount:number,discount?:RecordData){const reduction=discount?Math.floor(amount*discount.percent/100):0;return {original_amount_minor:amount,amount_minor:amount-reduction,discount_amount_minor:reduction,discount_percent:discount?.percent??0,discount_id:discount?.id,discount_version:discount?.version};}
export async function useDiscount(store:Store,owner:string,country:string,price:any,now=new Date(),excludeBoost?:string){
 if(!price.discount_id)return;
 await store.db.query('SELECT pg_advisory_xact_lock(hashtextextended($1,0))',['personal-discount:'+country+':'+owner]);
 const reserved=await holds(store,{id:owner,country},now,excludeBoost);
 const d=await store.get(price.discount_id);
 if(!d||d.kind!=='referral_discount'||d.owner!==owner||d.country!==country||d.status!=='active'||d.valid_until<=now.toISOString()||(!excludeBoost&&d.version!==price.discount_version)||d.max_uses&&(d.uses??0)+reserved.filter(b=>b.price_snapshot?.discount_id===d.id).length>=d.max_uses)throw new HttpException({error:{code:'OFFER_CHANGED',message:'Персональная скидка изменилась. Обновите итоговую цену.',retryable:false}},409);
 await store.put({...d,uses:(d.uses??0)+1,status:d.max_uses&&(d.uses??0)+1>=d.max_uses?'used':'active',version:d.version+1});
}
export async function issueDiscount(store:Store,reward:RecordData,now=new Date()){
 const existing=(await store.select('referral_discount',reward.country,{owner:reward.owner,sourceId:reward.id,limit:1}))[0];if(existing)return existing;
 const p=reward.policy_snapshot;
 return store.put({id:randomUUID(),kind:'referral_discount',owner:reward.owner,country:reward.country,version:1,created_at:now.toISOString(),source_id:reward.id,campaign_id:reward.campaign_id,status:'active',percent:p.discount_percent,services:p.discount_services??['all'],max_uses:p.discount_max_uses??0,uses:0,valid_until:new Date(now.getTime()+p.reward_duration_seconds*1000).toISOString()});
}
