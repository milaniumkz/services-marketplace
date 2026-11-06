import {readFileSync,existsSync} from 'node:fs';
import {HttpException} from '@nestjs/common';
import type {BillingProvider,VerifiedPurchase,VerifiedRefund} from './providers';
import {Store,RecordData} from './store';
export type VtbConfig={environment:'sandbox'|'production';user_name:string;password:string;public_origin:string;payment_form_path?:string};
export const VTB_ORIGINS={sandbox:'https://vtbkz.rbsuat.com',production:'https://payment.vtb.kz'};
export class VtbGatewayError extends Error {constructor(readonly code:string){super('Банк временно не подтвердил операцию');}}
const unavailable=(code='VTB_UNAVAILABLE',message='Не удалось связаться с банком. Проверьте статус оплаты, не оплачивая повторно.'):never=>{throw new HttpException({error:{code,message,retryable:true}},503);};
export function loadVtbConfig():VtbConfig|undefined {
 const file=process.env.JOBA_VTB_CONFIG_FILE??'/run/joba-payments/vtb.json';if(!existsSync(file))return;
 const c=JSON.parse(readFileSync(file,'utf8'));if(c.enabled===false)return;
 if(!['sandbox','production'].includes(c.environment)||typeof c.user_name!=='string'||!c.user_name||typeof c.password!=='string'||!c.password)throw Error('Invalid private VTB configuration');
 const origin=new URL(c.public_origin);if(origin.protocol!=='https:'||origin.username||origin.password||origin.search||origin.hash||origin.pathname!=='/')throw Error('Invalid VTB public origin');
 if(c.payment_form_path!==undefined&&(typeof c.payment_form_path!=='string'||!c.payment_form_path.startsWith('/payment/')||c.payment_form_path.includes('?')||c.payment_form_path.includes('#')))throw Error('Invalid VTB form path');
 return {...c,public_origin:origin.origin};
}
export function vtbSandbox(provider:BillingProvider|undefined){return provider instanceof VtbGateway&&provider.environment==='sandbox';}
export class VtbGateway implements BillingProvider {
 readonly name='vtb';readonly countries=['KZ'];readonly hostedCheckout=true;
 readonly environment:'sandbox'|'production';readonly origin:string;
 constructor(readonly config:VtbConfig,private store:Store,private transport:typeof fetch=fetch){this.environment=config.environment;this.origin=VTB_ORIGINS[config.environment];}
 async api(method:string,values:Record<string,string|number>){
  try{
   const response=await this.transport(this.origin+'/payment/rest/'+method,{method:'POST',headers:{'Content-Type':'application/x-www-form-urlencoded'},body:new URLSearchParams({userName:this.config.user_name,password:this.config.password,language:'ru',...Object.fromEntries(Object.entries(values).map(([k,v])=>[k,String(v)]))}),signal:AbortSignal.timeout(20000),redirect:'error'});
   if(!response.ok)return unavailable();const text=await response.text();if(Buffer.byteLength(text)>262144)return unavailable();const data=JSON.parse(text);
   if(data.errorCode!==undefined&&String(data.errorCode)!=='0')throw new VtbGatewayError(String(data.errorCode));return data;
  }catch(error){if(error instanceof VtbGatewayError||error instanceof HttpException)throw error;return unavailable();}
 }
 formUrl(value:string){let url:URL;try{url=new URL(value);}catch{return unavailable('VTB_INVALID_RESPONSE');}if(url.origin!==this.origin||url.protocol!=='https:'||url.username||url.password||!url.pathname.startsWith('/payment/'))return unavailable('VTB_INVALID_RESPONSE');return url.toString();}
 async register(payment:RecordData,callback:string){
  try{
   const r=await this.api('register.do',{orderNumber:payment.id,amount:payment.amount_minor,currency:398,returnUrl:this.config.public_origin+'/api/v1/public/billing/vtb/return?payment_id='+payment.id,failUrl:this.config.public_origin+'/api/v1/public/billing/vtb/return?payment_id='+payment.id,dynamicCallbackUrl:callback,description:'JOBA '+(payment.benefit==='boost'?'Продвижение':'Подписка')+' '+(payment.offer.plan??'boost'),sessionTimeoutSecs:Math.max(1,Math.min(1200,Math.floor((Date.parse(payment.expires_at)-Date.now())/1000))),bindingNotNeeded:'true'});
   if(typeof r.orderId!=='string'||typeof r.formUrl!=='string')return unavailable('VTB_INVALID_RESPONSE');
   return {order_id:r.orderId,form_url:this.formUrl(r.formUrl)};
  }catch(error){
   if(!(error instanceof VtbGatewayError)||error.code!=='1')throw error;
   const status=await this.status({orderNumber:payment.id});const id=this.orderId(status);
   if(!id)return unavailable('VTB_RECONCILIATION_REQUIRED');
   const path=this.config.payment_form_path??payment.form_path;
   return {order_id:id,form_url:path?this.formUrl(new URL(path+'?mdOrder='+encodeURIComponent(id),this.origin).toString()):null};
  }
 }
 orderId(data:any):string|undefined{return typeof data.orderId==='string'?data.orderId:(data.attributes??[]).find((x:any)=>x.name==='mdOrder')?.value;}
 async status(values:{orderId?:string;orderNumber?:string}){return this.api('getOrderStatusExtended.do',values as Record<string,string>);}
 validateStatus(payment:RecordData,data:any){
  const id=this.orderId(data);
  if(String(data.orderNumber)!==payment.id||payment.bank_order_id&&id&&id!==payment.bank_order_id||data.amount!==payment.amount_minor||String(data.currency)!=='398')return unavailable('VTB_EVIDENCE_MISMATCH','Сумма или идентификатор банковской операции не совпали. Требуется сверка.');
  if(!Number.isInteger(data.orderStatus)||![0,1,2,3,4,5,6,7,8].includes(data.orderStatus))return unavailable('VTB_INVALID_RESPONSE');
  if(data.orderStatus===2&&(String(data.actionCode)!=='0'||data.paymentAmountInfo?.depositedAmount!==payment.amount_minor||Number(data.paymentAmountInfo?.refundedAmount??0)>0))return unavailable('VTB_EVIDENCE_MISMATCH');
  return data.orderStatus as number;
 }
 async decline(payment:RecordData){return this.api('decline.do',{orderId:payment.bank_order_id,orderNumber:payment.id});}
 async validateProduct(productId:string,country:string){
  if(country!=='KZ')return unavailable('VTB_COUNTRY_UNAVAILABLE','ВТБ подключён только для оплаты в тенге.');
  const rows=(await this.store.all('price_version',country)).filter(p=>p.payload?.provider==='vtb'&&p.payload?.product_id===productId).sort((a,b)=>b.created_at.localeCompare(a.created_at));
  if(!rows.length)return unavailable('PRODUCT_NOT_CONFIGURED','Сначала создайте цену JOBA. ВТБ получает сумму из серверного предложения.');
  return {product_id:productId,amount_minor:rows[0].payload.amount_minor,currency:rows[0].payload.currency};
 }
 async verifyPurchase(reference:string,accountId:string):Promise<VerifiedPurchase>{
  const payment=(await this.store.select('bank_checkout','KZ',{owner:accountId,limit:1000})).find(p=>p.id===reference||p.bank_order_id===reference);
  if(!payment)return unavailable('PURCHASE_OWNERSHIP_MISMATCH','Платёж не найден в вашем аккаунте.');
  const data=await this.status(payment.bank_order_id?{orderId:payment.bank_order_id}:{orderNumber:payment.id}),status=this.validateStatus(payment,data);
  return {provider:'vtb',transaction_id:payment.bank_order_id??this.orderId(data)!,original_transaction_id:payment.id,user_id:payment.owner,country:payment.country,product_id:payment.offer.product_id,environment:this.environment,amount_minor:payment.amount_minor,currency:'KZT',valid_until:payment.benefit==='boost'?payment.boost_ends_at:new Date(Date.now()+30*86400000).toISOString(),state:status===2?'active':[3,4,6].includes(status)?'revoked':'pending',revision:status===2?2:status>=3?3:1};
 }
 async verifyWebhook(_raw:Buffer,_headers:Record<string,string>):Promise<never>{throw new HttpException({error:{code:'VTB_CALLBACK_ROUTE',message:'Используйте защищённый callback JOBA с серверной сверкой банка'}},400);}
 async requestRefund(request:{request_id:string;transaction_id:string;user_id:string;country:string;amount_minor:number;currency:string}){
  if(request.country!=='KZ'||request.currency!=='KZT'||!Number.isSafeInteger(request.amount_minor)||request.amount_minor<1)return unavailable('REFUND_MISMATCH');
  const payment=(await this.store.select('bank_checkout','KZ',{owner:request.user_id,limit:1000})).find(p=>p.bank_order_id===request.transaction_id);
  if(!payment)return unavailable('REFUND_MISMATCH');
  await this.api('refund.do',{orderId:request.transaction_id,amount:request.amount_minor,currency:398,externalRefundId:request.request_id});return {reference:request.request_id};
 }
 async verifyRefund(requestId:string,accountId:string):Promise<VerifiedRefund>{
  const request=await this.store.get(requestId);if(!request||request.kind!=='refund_request'||request.owner!==accountId||!['pending','unknown'].includes(request.status))return unavailable('REFUND_MISMATCH');
  const payment=await this.store.get(request.payment_id);if(!payment||payment.provider!=='vtb'||payment.owner!==accountId)return unavailable('REFUND_MISMATCH');
  // Repeating externalRefundId is explicitly idempotent in the bank protocol.
  await this.requestRefund({request_id:request.id,transaction_id:payment.transaction_id,user_id:accountId,country:request.country,amount_minor:request.amount_minor,currency:request.currency});
  return {environment:this.environment,provider:'vtb',request_id:request.id,refund_id:request.id,transaction_id:payment.transaction_id,user_id:accountId,country:request.country,amount_minor:request.amount_minor,currency:request.currency,status:'succeeded'};
 }
}
