import {randomUUID,timingSafeEqual} from 'node:crypto';
import {HttpException} from '@nestjs/common';
import {Store,RecordData} from './store';
import {PrivateFiles} from './private-files';
import {Commerce} from './commerce';
import {Growth} from './growth';
import {VtbGatewayError} from './vtb-gateway';
import type {HostedBank} from './hosted-bank';
import {subscriptionState,validateHostedQuote,fulfillQuotedSubscription} from './subscription-quotes';
import {VerifiedPurchase} from './providers';
function fail(code:string,message:string,status=409):never {throw new HttpException({error:{code,message,retryable:status>=500}},status);}
const pending=(r:RecordData)=>['registering','pending'].includes(r.status);
export class VtbPayments {
 private work=new Map<string,Promise<any>>();
 constructor(private store:Store,readonly gateway:HostedBank,private commerce:Commerce,private growth:Growth,private files:PrivateFiles,private transaction:<T>(run:()=>Promise<T>)=>Promise<T>){}
 async prepare(user:RecordData,b:any){
  if(!this.gateway.countries.includes(user.country)||user.status!=='active'||user.staff_permissions?.length)fail('VTB_COUNTRY_UNAVAILABLE','Этот банк пока не подключён для страны аккаунта',403);
  await this.store.db.query('SELECT pg_advisory_xact_lock(hashtextextended($1,0))',['vtb-owner:'+user.country+':'+user.id]);
  if(b.accepted!==true)fail('CONSENT_REQUIRED','Подтвердите условия оплаты',403);
  const source=String(b.reservation_id??b.offer_id??'');
  const previous=(await this.store.select('bank_checkout',user.country,{owner:user.id,limit:1000})).filter(p=>p.provider===this.gateway.name&&p.source_id===source&&p.environment===this.gateway.environment).sort((a,b)=>b.created_at.localeCompare(a.created_at))[0];
  if(previous)return {_vtb_provider:this.gateway.name,_vtb_action:pending(previous)?'register':'present',id:previous.id};
  const active=(await this.store.select('bank_checkout',user.country,{owner:user.id,limit:1000})).find(p=>pending(p)&&p.role===(b.reservation_id?'boost':user.active_role??'customer'));
  if(active)return {_vtb_provider:active.provider,_vtb_action:'register',id:active.id};
  let offer:any,quote:RecordData|undefined,boost:RecordData|undefined,state:any;
  if(b.reservation_id){
   boost=await this.store.get(source);
   if(!boost||boost.kind!=='boost'||boost.owner!==user.id||boost.country!==user.country||boost.status!=='reserved'||boost.reservation_expires_at<=new Date().toISOString()||boost.price_snapshot?.provider!==this.gateway.name)fail('RESERVATION_EXPIRED','Резерв продвижения истёк. Выберите размещение заново');
   offer=boost.price_snapshot;
   if(user.verification!=='passed'||offer.amount_minor!==b.amount_minor||offer.currency!==b.currency)fail('OFFER_CHANGED','Проверьте итоговую цену и подтверждение личности');
  }else{const checked=await validateHostedQuote(this.store,this.commerce,user,b);offer=checked.offer;quote=checked.quote;state=checked.state;}
  if(offer.provider!==this.gateway.name)fail('OFFER_CHANGED','Выбран другой банк. Обновите предложение оплаты.');
  if(!(this.gateway.currencies??['KZT']).includes(offer.currency)||!Number.isSafeInteger(offer.amount_minor)||offer.amount_minor<0||offer.amount_minor>999999999999)fail('PRICE_MISMATCH','Банк пока не поддерживает валюту выбранного предложения');
  const now=new Date(),id=randomUUID();
  const payment:RecordData={id,kind:'bank_checkout',owner:user.id,country:user.country,version:1,created_at:now.toISOString(),status:'registering',provider:this.gateway.name,environment:this.gateway.environment,benefit:boost?'boost':'subscription',source_id:source,role:boost?'boost':offer.role,offer,amount_minor:offer.amount_minor,currency:offer.currency,expires_at:new Date(Math.min(now.getTime()+20*60000,boost?Date.parse(boost.reservation_expires_at):Infinity)).toISOString(),boost_ends_at:boost?.ends_at,baseline_periods:state?.periods.map((p:RecordData)=>p.id)??[],attempts:0};
  await this.store.put(payment);
  if(quote)await this.store.put({...quote,status:'payment_pending',payment_id:id,version:quote.version+1});
  return {_vtb_provider:this.gateway.name,_vtb_action:'register',id};
 }
 async owned(user:RecordData,id:string,action='poll'){
  const p=await this.store.get(id);if(!p||p.kind!=='bank_checkout'||p.owner!==user.id||p.country!==user.country)fail('NOT_FOUND','Платёж не найден',404);
  if(p.provider!==this.gateway.name||p.environment!==this.gateway.environment)fail('PAYMENT_ENVIRONMENT_CHANGED','Этот платёж оформлен в другой среде. Обратитесь в поддержку');
  if(action==='cancel'&&pending(p))await this.store.put({...p,cancel_requested:true,version:p.version+1});
  return {_vtb_provider:this.gateway.name,_vtb_action:action,id};
 }
 async byReference(user:RecordData,reference:string){const p=(await this.store.select('bank_checkout',user.country,{owner:user.id,limit:1000})).find(p=>p.id===reference||p.bank_order_id===reference);if(!p)fail('NOT_FOUND','Платёж не найден',404);return this.owned(user,p.id);}
 async callback(id:string,token:string){
  if(!/^[0-9a-f-]{36}$/i.test(id)||typeof token!=='string'||token.length>200)fail('FORBIDDEN','Некорректное уведомление',403);
  const expected=await this.files.requestDigest(this.gateway.name+'-callback:'+id),a=Buffer.from(token),b=Buffer.from(expected);
  if(a.length!==b.length||!timingSafeEqual(a,b))fail('FORBIDDEN','Некорректное уведомление',403);
  const p=await this.store.get(id);if(!p||p.kind!=='bank_checkout')fail('NOT_FOUND','Платёж не найден',404);
  return {_vtb_provider:this.gateway.name,_vtb_action:'callback',id};
 }
 private async get(id:string){return this.transaction(async()=>{const p=await this.store.get(id);if(!p||p.kind!=='bank_checkout')fail('NOT_FOUND','Платёж не найден',404);return p;});}
 private async save(id:string,data:any){return this.transaction(async()=>{const p=await this.store.get(id);if(!p)fail('NOT_FOUND','Платёж не найден',404);if(!pending(p))return p;return this.store.put({...p,...data,version:p.version+1});});}
 async perform(action:string,id:string){
  const existing=this.work.get(id);if(existing)return existing;
  const job=this.process(action,id).finally(()=>this.work.delete(id));this.work.set(id,job);return job;
 }
 private async process(action:string,id:string){
  let p=await this.get(id);if(p.provider!==this.gateway.name||p.environment!==this.gateway.environment)fail('PAYMENT_ENVIRONMENT_CHANGED','Среда платежа изменилась');if(!pending(p))return this.present(p);
  try{
   if(p.amount_minor===0)return this.settle(p,2,true);
   if(!p.bank_order_id){
    const token=await this.files.requestDigest(this.gateway.name+'-callback:'+id),callback=this.gateway.config.public_origin+'/api/v1/public/billing/'+this.gateway.name+'/callback?payment_id='+id+'&token='+token;
    const registered=await this.gateway.register(p,callback);
    p=await this.save(id,{bank_order_id:registered.order_id,form_url:registered.form_url,form_path:registered.form_url?new URL(registered.form_url).pathname:null,status:'pending',last_error:null});
   }
   let data=await this.gateway.status({orderId:p.bank_order_id});let status=this.gateway.validateStatus(p,data);
   const expired=p.expires_at<=new Date().toISOString();
   if(status===0&&(action==='cancel'||p.cancel_requested||expired)){
    try{await this.gateway.decline(p);}catch(_){/* Re-read: capture can win the cancellation race. */}
    data=await this.gateway.status({orderId:p.bank_order_id});status=this.gateway.validateStatus(p,data);
   }
   if(status===2){if(this.gateway.name==='bcc')p=await this.save(id,{bank_evidence:{rrn:data.RRN,int_ref:data.INT_REF}});return this.settle(p,status);}
   if([3,4,6].includes(status)){
    const terminal=expired?'expired':p.cancel_requested||action==='cancel'?'canceled':'declined';
    p=await this.transaction(async()=>{const fresh=(await this.store.get(id))!;if(!pending(fresh))return fresh;const quote=await this.store.get(fresh.source_id);if(quote?.kind==='checkout_quote'&&quote.status==='payment_pending')await this.store.put({...quote,status:'payment_failed',version:quote.version+1});return this.store.put({...fresh,status:terminal,bank_status:status,last_checked_at:new Date().toISOString(),version:fresh.version+1});});
   }else p=await this.save(id,{bank_status:status,last_checked_at:new Date().toISOString(),last_error:null});
  }catch(error){
   const code=error instanceof VtbGatewayError?'VTB_BANK_ERROR_'+error.code:error instanceof HttpException?(error.getResponse() as any)?.error?.code:this.gateway.name.toUpperCase()+'_UNAVAILABLE';
   p=await this.save(id,{last_error:code,attempts:(p.attempts??0)+1,last_checked_at:new Date().toISOString()});
  }
  return this.present(p);
 }
 private async settle(p:RecordData,status:number,free=false){
  return this.transaction(async()=>{
   await this.store.db.query('SELECT pg_advisory_xact_lock(hashtextextended($1,0))',['vtb-payment:'+p.id]);
   const payment=(await this.store.get(p.id))!;if(!pending(payment))return this.present(payment);
   const user=await this.store.get(payment.owner),now=new Date();
   const proof={provider:this.gateway.name,environment:payment.environment as 'sandbox'|'production',transaction_id:payment.bank_order_id??'free-'+payment.id,payment_id:payment.id,created_at:payment.created_at};
   let subscription:RecordData|undefined,boost:RecordData|undefined,resolution:string|undefined;
   if(!user||user.status!=='active'||user.verification!=='passed')resolution='ACCOUNT_REQUIRES_REVIEW';
   if(!resolution&&payment.benefit==='subscription'){
    await this.store.db.query('SELECT pg_advisory_xact_lock(hashtextextended($1,0))',['subscription-periods:'+payment.country+':'+payment.owner]);
    const roleUser:RecordData={...user!,active_role:payment.offer.role};
    const state=await subscriptionState(this.store,roleUser,now);
    if(!roleUser.roles?.includes(payment.offer.role)||state.periods.some(s=>!payment.baseline_periods.includes(s.id)))resolution='SUBSCRIPTION_CHANGED_DURING_PAYMENT';
    if(payment.offer.offer_kind==='upgrade'&&Date.parse(payment.offer.valid_until)<=now.getTime())resolution='UPGRADE_PERIOD_ENDED';
    if(!resolution){
     const quote=(await this.store.get(payment.source_id))!;
     // Payment has already been verified; a fulfillment failure must leave no
     // partial grants/discount usage while retaining a refundable payment.
     await this.store.db.exec('SAVEPOINT vtb_fulfillment');
     try{subscription=(await fulfillQuotedSubscription(this.store,roleUser,quote,state,payment.offer,now,proof)).subscription;await this.store.db.exec('RELEASE SAVEPOINT vtb_fulfillment');}
     catch(_){await this.store.db.exec('ROLLBACK TO SAVEPOINT vtb_fulfillment');resolution='FULFILLMENT_REQUIRES_REVIEW';}
    }
   }
   if(!resolution&&payment.benefit==='boost'){
    await this.store.db.exec('SAVEPOINT vtb_fulfillment');
    try{
     const evidence:VerifiedPurchase={provider:this.gateway.name,transaction_id:proof.transaction_id,original_transaction_id:payment.id,user_id:payment.owner,country:payment.country,product_id:payment.offer.product_id,environment:proof.environment,amount_minor:payment.amount_minor,currency:payment.currency,valid_until:payment.boost_ends_at,state:'active',revision:2};
     boost=await this.growth.verifyBoost(payment.owner,payment.country,{reservation_id:payment.source_id,provider:this.gateway.name,transaction_reference:payment.id},evidence);
     if(boost.status==='resolution_required')resolution='PLACEMENT_REQUIRES_REVIEW';
     await this.store.db.exec('RELEASE SAVEPOINT vtb_fulfillment');
    }catch(_){await this.store.db.exec('ROLLBACK TO SAVEPOINT vtb_fulfillment');resolution='FULFILLMENT_REQUIRES_REVIEW';}
   }
   const transactions=await this.store.select('payment_transaction',payment.country,{owner:payment.owner,limit:1000});
   if(resolution&&!transactions.some(t=>t.provider===this.gateway.name&&t.transaction_id===proof.transaction_id))await this.store.put({id:randomUUID(),kind:'payment_transaction',owner:payment.owner,country:payment.country,version:1,created_at:now.toISOString(),provider:this.gateway.name,is_test:payment.environment==='sandbox',environment:payment.environment,transaction_id:proof.transaction_id,original_transaction_id:payment.id,bank_checkout_id:payment.id,benefit:payment.benefit,operation:'purchase',state:'active',amount_minor:payment.amount_minor,cash_amount_minor:payment.environment==='production'?payment.amount_minor:0,currency:payment.currency,resolution_required:true});
   const completed=await this.store.put({...payment,status:resolution?'resolution_required':'completed',bank_status:status,zero_charge:free,subscription_id:subscription?.id,boost_id:boost?.id,resolution_code:resolution,last_error:null,confirmed_at:now.toISOString(),version:payment.version+1});
   return this.present(completed);
  });
 }
 present(p:RecordData){return {id:p.id,provider:this.gateway.name,status:p.status,environment:p.environment,bank_test:p.environment==='sandbox',payment_url:pending(p)&&!p.cancel_requested?p.form_url??null:null,amount_minor:p.amount_minor,currency:p.currency,plan:p.offer.plan??null,title:p.offer.title??'Продвижение',benefit:p.benefit,expires_at:p.expires_at,subscription_id:p.subscription_id??null,boost_id:p.boost_id??null,can_cancel:pending(p),can_refund:p.status==='resolution_required',message:p.status==='resolution_required'?'Банк подтвердил оплату, но условия аккаунта изменились. Обратитесь в поддержку для восстановления услуги или возврата.':p.last_error?'Статус оплаты уточняется. Повторная оплата не нужна.':null};}
 async list(user:RecordData){const rows=(await this.store.select('bank_checkout',user.country,{owner:user.id,limit:1000})).filter(p=>pending(p)||p.status==='resolution_required').sort((a,b)=>b.created_at.localeCompare(a.created_at));return {enabled:this.gateway.countries.includes(user.country),items:rows.filter(p=>p.provider===this.gateway.name).map(p=>this.present(p))};}
 async pendingIds(){return this.transaction(async()=>{const rows=(await this.store.all('bank_checkout')).filter(p=>p.provider===this.gateway.name&&pending(p)&&p.environment===this.gateway.environment&&(!p.last_checked_at||Date.parse(p.last_checked_at)<Date.now()-45000));return rows.slice(0,10).map(p=>p.id);});}
}
