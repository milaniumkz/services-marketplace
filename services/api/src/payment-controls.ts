import {randomUUID} from 'node:crypto';
import {HttpException} from '@nestjs/common';
import {Store,RecordData} from './store';
import {isStaffOwner} from './staff-access';
const fields=['bcc_enabled','vtb_enabled','rewarded_enabled'] as const;
export async function paymentControls(store:Store){const r=(await store.all('payment_controls','KZ'))[0];return {bcc_enabled:r?.bcc_enabled!==false,vtb_enabled:r?.vtb_enabled!==false,rewarded_enabled:r?.rewarded_enabled!==false,version:r?.version??0};}
export function paymentAllowed(c:Awaited<ReturnType<typeof paymentControls>>,provider:string){return provider==='bcc'?c.bcc_enabled:provider==='vtb'?c.vtb_enabled:provider==='test'?c.bcc_enabled||c.vtb_enabled:true;}
export async function requirePayment(store:Store,provider:string){const c=await paymentControls(store);if(!paymentAllowed(c,provider))throw new HttpException({error:{code:'PAYMENT_METHOD_DISABLED',message:c.rewarded_enabled?'Оплата через этот банк временно недоступна. Получите подписку за рекламу.':'Оплата через этот банк временно недоступна. Попробуйте позже.',retryable:false}},403);}
export async function adminPaymentControls(store:Store,a:{id:string;country:string;user:RecordData;mfa:boolean},method:string,b:any){
 if(!isStaffOwner(a.user)||!a.mfa||a.user.status!=='active')throw new HttpException({error:{code:'FORBIDDEN',message:'Переключатели оплаты доступны владельцу.',retryable:false}},403);
 if(method==='GET')return paymentControls(store);
 if(method!=='PUT')throw new HttpException({error:{code:'NOT_FOUND',message:'Действие не поддерживается.',retryable:false}},404);
 const changed=fields.filter(k=>Object.hasOwn(b,k));if(!changed.length||changed.some(k=>typeof b[k]!=='boolean')||typeof b.reason!=='string'||b.reason.trim().length<10||b.reason.length>1000)throw new HttpException({error:{code:'VALIDATION_ERROR',message:'Укажите состояние переключателя.',retryable:false}},422);
 await store.db.query('SELECT pg_advisory_xact_lock(hashtextextended($1,0))',['payment-controls']);
 const old=(await store.all('payment_controls','KZ'))[0];if(b.expected_version!==(old?.version??0))throw new HttpException({error:{code:'STATE_CONFLICT',message:'Настройка изменилась. Обновите страницу.',retryable:false}},409);
 const now=new Date().toISOString(),previous=await paymentControls(store),record={...old,id:old?.id??randomUUID(),kind:'payment_controls',owner:a.id,country:'KZ',created_at:old?.created_at??now,version:(old?.version??0)+1,updated_at:now,...Object.fromEntries(changed.map(k=>[k,b[k]]))};await store.put(record);
 await store.put({id:randomUUID(),kind:'audit',owner:a.id,country:'KZ',created_at:now,version:1,actor_id:a.id,action:'billing.controls_changed',target_id:record.id,reason:b.reason,changes:changed.map(k=>({field:k,from:previous[k],to:b[k]}))});return paymentControls(store);
}
