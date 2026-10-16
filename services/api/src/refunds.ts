import {randomUUID} from 'node:crypto';
import {HttpException} from '@nestjs/common';
import {Store,RecordData} from './store';
import {Providers,VerifiedRefund} from './providers';
function fail(code:string,message:string,status=422):never{throw new HttpException({error:{code,message,details:{},retryable:status===503}},status);}
const reserved=new Set(['requested','approved','pending','unknown']);
const rec=(kind:string,owner:string,country:string,data:any):RecordData=>({...data,id:randomUUID(),kind,owner,country,version:1,created_at:new Date().toISOString()});
export class Refunds {
 constructor(private store:Store,private providers:Providers){}
 async payment(id:string,country:string,owner?:string){
  const p=await this.store.get(id);
  if(!p||p.kind!=='payment_transaction'||p.country!==country||owner&&p.owner!==owner)fail('NOT_FOUND','Платёж не найден',404);
  if(!['sandbox','production'].includes(p.environment)||p.state!=='active'||!['purchase','renewal'].includes(p.operation)||!Number.isSafeInteger(p.cash_amount_minor)||p.cash_amount_minor<=0||p.cash_amount_minor!==p.amount_minor)fail('PAYMENT_REQUIRES_RECONCILIATION','Нужен подтверждённый платёж с проверенной суммой',409);
  return p;
 }
 private async lock(p:RecordData){
  // Keep the same boost -> target -> capacity -> transaction lock order as purchase verification.
  if(p.benefit==='boost'){
   const boost=await this.store.get(p.source_id??'');
   if(boost?.kind==='boost'&&boost.country===p.country){
    await this.store.db.query('SELECT pg_advisory_xact_lock(hashtextextended($1,0))',['boost-target:'+p.country+':'+boost.target_id]);
    await this.store.db.query('SELECT pg_advisory_xact_lock(hashtextextended($1,0))',['boost-capacity:'+p.country+':'+boost.placement_id]);
   }
  }
  await this.store.db.query('SELECT pg_advisory_xact_lock(hashtextextended($1,0))',['payment-transaction:'+p.country+':'+p.provider+':'+p.transaction_id]);
 }
 async balances(payments:RecordData[],except?:string){
  if(!payments.length)return [];
  const country=payments[0].country,ids=payments.map(x=>x.id);
  const [cash,pending]=await Promise.all([
   this.store.db.query<{id:string,total:string}>("SELECT data->>'original_payment_id' AS id,sum((data->>'amount_minor')::numeric)::text AS total FROM records WHERE kind='payment_transaction' AND country=$1 AND data->>'operation'='refund' AND data->>'original_payment_id'=ANY($2::text[]) GROUP BY 1",[country,ids]),
   this.store.db.query<{id:string,total:string}>("SELECT data->>'payment_id' AS id,sum((data->>'amount_minor')::numeric)::text AS total FROM records WHERE kind='refund_request' AND country=$1 AND data->>'payment_id'=ANY($2::text[]) AND data->>'status'=ANY($3::text[]) AND ($4::text IS NULL OR id::text<>$4) GROUP BY 1",[country,ids,[...reserved],except??null])
  ]);
  return payments.map(p=>{const refunded=Number(cash.rows.find(x=>x.id===p.id)?.total??0),held=Number(pending.rows.find(x=>x.id===p.id)?.total??0);
   if(!Number.isSafeInteger(refunded)||!Number.isSafeInteger(held)||refunded<0||held<0||refunded+held>p.amount_minor)fail('REFUND_BALANCE_CONFLICT','Требуется сверка остатка возврата',409);
   return {paid_minor:p.amount_minor,refunded_minor:refunded,reserved_minor:held,available_minor:p.amount_minor-refunded-held,currency:p.currency};
  });
 }
 async balance(p:RecordData,except?:string){return (await this.balances([p],except))[0];}
 async create(owner:string,country:string,paymentId:string,amount:any,reason:string){
  const p=await this.payment(paymentId,country,owner);await this.lock(p);
  if(!Number.isSafeInteger(amount)||amount<1)fail('VALIDATION_ERROR','Укажите целую положительную сумму в минимальных единицах');
  const balance=await this.balance(p);if(amount>balance.available_minor)fail('REFUND_EXCEEDS_REMAINING','Сумма превышает доступный остаток',409);
  return this.store.put(rec('refund_request',owner,country,{payment_id:p.id,subscription_id:p.benefit==='subscription'?p.source_id:undefined,provider:p.provider,currency:p.currency,amount_minor:amount,reason,status:'requested'}));
 }
 async command(request:RecordData,actor:string,action:string,reason:string){
  if(!request.payment_id&&request.status==='requested'&&(action==='cancel'&&actor===request.owner||action==='reject'&&actor!==request.owner))return this.store.put({...request,status:action==='cancel'?'canceled':'rejected',decision_reason:reason,version:request.version+1});
  if(!request.payment_id)fail('LEGACY_REFUND_REQUIRES_REVIEW','Сначала сопоставьте обращение с подтверждённым платежом',409);
  const p=await this.payment(request.payment_id,request.country);await this.lock(p);
  if(p.owner!==request.owner)fail('PURCHASE_OWNERSHIP_MISMATCH','Владелец платежа не совпадает с заявкой',409);
  const fresh=await this.store.get(request.id);if(!fresh||fresh.version!==request.version)fail('STATE_CONFLICT','Версия заявки изменилась',409);
  const change=async(data:any)=>this.store.put({...request,...data,version:request.version+1});
  if(action==='cancel'){
   if(actor!==request.owner||request.status!=='requested')fail('STATE_CONFLICT','Отменить можно только свою заявку до согласования',409);
   return change({status:'canceled',decision_reason:reason});
  }
  if(action==='approve'||action==='reject'){
   if(request.status!=='requested')fail('STATE_CONFLICT','Заявка уже рассмотрена',409);
   if(actor===request.owner)fail('SECOND_APPROVAL_REQUIRED','Собственную заявку рассматривает другой сотрудник',403);
   const balance=await this.balance(p,request.id);if(request.amount_minor>balance.available_minor)fail('REFUND_EXCEEDS_REMAINING','Недостаточно остатка для согласования',409);
   return change({status:action==='approve'?'approved':'rejected',approved_by:action==='approve'?actor:undefined,decision_reason:reason,provider_request_key:request.id});
  }
  const provider=this.providers.billing.get(p.provider);
  if(action==='submit'){
   if(request.status!=='approved')fail('STATE_CONFLICT','Отправка доступна только согласованной заявке',409);
   if(!provider?.requestRefund)fail('PROVIDER_UNAVAILABLE','Адаптер возвратов ещё не подключён',503);
   // The adapter MUST deduplicate this stable key, including after a timeout/DB rollback.
   try{const result=await provider.requestRefund({request_id:request.id,transaction_id:p.transaction_id,user_id:p.owner,country:p.country,amount_minor:request.amount_minor,currency:p.currency});
    if(!result||typeof result.reference!=='string'||!result.reference||result.reference.length>300)return change({status:'unknown',last_error:'INVALID_PROVIDER_RESPONSE'});
    return change({status:'pending',provider_reference:result.reference,submitted_at:new Date().toISOString(),last_error:undefined});
   }catch{return change({status:'unknown',last_error:'PROVIDER_OUTCOME_UNKNOWN'});}
  }
  if(action==='reconcile'){
   if(!['pending','unknown'].includes(request.status))fail('STATE_CONFLICT','Сверка недоступна в текущем состоянии',409);
   if(!provider?.verifyRefund)fail('PROVIDER_UNAVAILABLE','Адаптер сверки возвратов ещё не подключён',503);
   let proof:VerifiedRefund;try{proof=await provider.verifyRefund(request.id,p.owner);}catch{return change({status:'unknown',last_error:'PROVIDER_CHECK_UNAVAILABLE'});}
   return this.confirm(request,p,proof);
  }
  fail('VALIDATION_ERROR','Неизвестная команда возврата');
 }
 private async confirm(r:RecordData,p:RecordData,v:VerifiedRefund){
  if(!v||v.environment!==p.environment||process.env.NODE_ENV==='production'&&v.environment!=='production'||v.provider!==p.provider||v.request_id!==r.id||v.user_id!==r.owner||v.country!==r.country||v.transaction_id!==p.transaction_id||v.amount_minor!==r.amount_minor||v.currency!==p.currency||!['pending','succeeded','failed'].includes(v.status)||typeof v.refund_id!=='string'||!v.refund_id||v.refund_id.length>300)fail('REFUND_EVIDENCE_MISMATCH','Подтверждение не соответствует заявке',409);
  if(v.status!=='succeeded')return this.store.put({...r,status:v.status==='failed'?'failed':'pending',provider_reference:v.refund_id,last_checked_at:new Date().toISOString(),last_error:undefined,version:r.version+1});
  await this.store.db.query('SELECT pg_advisory_xact_lock(hashtextextended($1,0))',['refund-evidence:'+r.country+':'+v.provider+':'+v.refund_id]);
  const prior=(await this.store.all('payment_transaction',r.country)).find(x=>x.provider===v.provider&&x.refund_id===v.refund_id);
  if(prior&&prior.refund_request_id!==r.id)fail('REFUND_ALREADY_USED','Подтверждение использовано другой заявкой',409);
  const balance=await this.balance(p,r.id);if(!prior&&r.amount_minor>balance.available_minor)fail('REFUND_EXCEEDS_REMAINING','Подтверждение превышает остаток',409);
  if(!prior)await this.store.put(rec('payment_transaction',r.owner,r.country,{provider:p.provider,transaction_id:'refund:'+v.refund_id,refund_id:v.refund_id,refund_request_id:r.id,original_payment_id:p.id,original_transaction_id:p.transaction_id,amount_minor:r.amount_minor,cash_amount_minor:-r.amount_minor,currency:p.currency,operation:'refund',state:'refunded',benefit:p.benefit,source_id:p.source_id}));
  const total=balance.refunded_minor+(prior?0:r.amount_minor);let accessAction='preserved';
  if(total===p.amount_minor){
   const target=await this.store.get(p.source_id??'');
   if(p.benefit==='subscription'&&target?.kind==='subscription'&&target.owner===r.owner&&target.country===r.country&&target.current_transaction_id===p.transaction_id){
    await this.store.put({...target,status:'revoked',version:target.version+1});
    for(const grant of await this.store.all('grant',r.country))if(grant.owner===r.owner&&grant.source_id===target.id)await this.store.put({...grant,valid_until:new Date().toISOString(),version:grant.version+1});accessAction='revoked';
   }else if(p.benefit==='boost'&&target?.kind==='boost'&&target.owner===r.owner&&target.country===r.country){await this.store.put({...target,status:'revoked',version:target.version+1});accessAction='revoked';}
   else accessAction=target?.kind==='subscription'&&target.current_transaction_id&&target.current_transaction_id!==p.transaction_id?'newer_purchase_preserved':'requires_review';
  }
  if(accessAction==='revoked'&&!prior)await this.store.put(rec('payment_transaction',r.owner,r.country,{provider:p.provider,transaction_id:'reversal:'+v.refund_id,refund_request_id:r.id,original_payment_id:p.id,amount_minor:0,cash_amount_minor:0,currency:p.currency,operation:'access_reversal',state:'revoked',benefit:p.benefit,source_id:p.source_id}));
  return this.store.put({...r,status:'confirmed',provider_reference:v.refund_id,confirmed_at:new Date().toISOString(),access_action:accessAction,last_error:undefined,version:r.version+1});
 }
}
