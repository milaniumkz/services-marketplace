import {existsSync,readFileSync,mkdirSync,writeFileSync,renameSync} from 'node:fs';
import {join} from 'node:path';
import {createHmac,randomBytes,createHash} from 'node:crypto';
import {HttpException} from '@nestjs/common';
import {Store,RecordData} from './store';
import type {HostedBank} from './hosted-bank';
import type {VerifiedPurchase,VerifiedRefund} from './providers';
export const BCC_ENDPOINTS={sandbox:'https://test3ds.bcc.kz:5445/cgi-bin/cgi_link',production:'https://3dsecure.bcc.kz/webview'};
export type BccConfig={enabled?:boolean;environment:'sandbox'|'production';terminal:string;merchant:string;mac_key:string;public_origin:string;countries?:string[];currencies?:string[];refund_journal_dir?:string};
const fail=(code:string,message='Не удалось подтвердить статус оплаты в БЦК. Не оплачивайте повторно.'):never=>{throw new HttpException({error:{code,message,retryable:true}},503);};
const currencyCodes:Record<string,string>={KZT:'398',KGS:'417',RUB:'643',BYN:'933'};
export function validateBccConfig(c:any):BccConfig{
 if(!['sandbox','production'].includes(c.environment)||!/^\d{8}$/.test(c.terminal)||!/^\d{1,15}$/.test(c.merchant)||!/^[a-f\d]{32,64}$/i.test(c.mac_key)||c.mac_key.length%2)throw Error('Invalid private BCC terminal configuration');
 const origin=new URL(c.public_origin);if(origin.protocol!=='https:'||origin.username||origin.password||origin.search||origin.hash||origin.pathname!=='/')throw Error('Invalid BCC public origin');
 const countries=c.countries??['KZ'],currencies=c.currencies??['KZT'];
 if(!Array.isArray(countries)||!countries.length||countries.some((v:any)=>!['KZ','KG'].includes(v))||!Array.isArray(currencies)||!currencies.length||currencies.some((v:any)=>!['KZT','KGS'].includes(v)))throw Error('Invalid BCC country/currency agreement');
 return {...c,public_origin:origin.origin,countries,currencies};
}
export function loadBccConfig():BccConfig|undefined{const file=process.env.JOBA_BCC_CONFIG_FILE??'/run/joba-payments/bcc.json';if(!existsSync(file))return;const c=JSON.parse(readFileSync(file,'utf8'));return c.enabled===false?undefined:validateBccConfig(c);}
export function bccMac(fields:Record<string,string>,keys:string[],key:string){return createHmac('sha1',Buffer.from(key,'hex')).update(keys.map(k=>Buffer.byteLength(fields[k]??'','utf8')+(fields[k]??'')).join(''),'utf8').digest('hex').toUpperCase();}
export function bccOrder(id:string){return (BigInt('0x'+id.replaceAll('-',''))%10n**28n+10n**28n).toString();}
const esc=(v:any)=>String(v??'').replace(/[&<>"']/g,c=>({'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;',"'":'&#39;'}[c]!));
export class BccGateway implements HostedBank {
 readonly name='bcc';readonly hostedCheckout=true;readonly countries:readonly string[];readonly currencies:readonly string[];readonly environment:'sandbox'|'production';readonly endpoint:string;readonly config:BccConfig;
 constructor(config:BccConfig,private store:Store,private transport:typeof fetch=fetch){this.config=validateBccConfig(config);this.environment=config.environment;this.endpoint=BCC_ENDPOINTS[config.environment];this.countries=this.config.countries!;this.currencies=this.config.currencies!;}
 private fresh(){return {TIMESTAMP:new Date().toISOString().replace(/\D/g,'').slice(0,14),NONCE:randomBytes(16).toString('hex').toUpperCase()};}
 private signed(fields:Record<string,string>,keys:string[]){return {...fields,P_SIGN:bccMac(fields,keys,this.config.mac_key)};}
 async api(fields:Record<string,string>){
  try{const response=await this.transport(this.endpoint,{method:'POST',headers:{'Content-Type':'application/x-www-form-urlencoded'},body:new URLSearchParams(fields),redirect:'error',signal:AbortSignal.timeout(20000)});if(!response.ok)fail('BCC_UNAVAILABLE');const raw=await response.text();if(Buffer.byteLength(raw)>262144)fail('BCC_INVALID_RESPONSE');
   if(raw.trim().startsWith('{'))return JSON.parse(raw);
   const result:Record<string,string>={};for(const input of raw.matchAll(/<input\b[^>]*>/gi)){const name=input[0].match(/\bname\s*=\s*["']([A-Z_]+)["']/i)?.[1]?.toUpperCase(),value=input[0].match(/\bvalue\s*=\s*["']([^"']*)["']/i)?.[1];if(name&&value!==undefined&&['ORDER','TERMINAL','TRTYPE','TRAN_TRTYPE','AMOUNT','CURRENCY','ACTION','RC','RRN','INT_REF','AUTH_CODE','TIMESTAMP','NONCE'].includes(name))result[name]=value;}
   if(!Object.keys(result).length)fail('BCC_INVALID_RESPONSE');return result;
  }catch(e){if(e instanceof HttpException)throw e;return fail('BCC_UNAVAILABLE');}
 }
 async ping(){const r=await this.api({TERMINAL:this.config.terminal,TRTYPE:'800',LANG:'ru'});return r.ACTION==='0'&&r.RC==='00'&&r.TERMINAL===this.config.terminal;}
 async register(payment:RecordData,callback:string){const token=new URL(callback).searchParams.get('token')!;return {order_id:bccOrder(payment.id),form_url:this.config.public_origin+'/api/v1/public/billing/bcc/form?payment_id='+payment.id+'&token='+encodeURIComponent(token)};}
 form(payment:RecordData){
  if(!this.currencies.includes(payment.currency)||!Number.isSafeInteger(payment.amount_minor)||payment.amount_minor<1)fail('BCC_CURRENCY_UNAVAILABLE','Для выбранной валюты банк ещё не выдал параметры приёма платежей.');
  const fields=this.signed({AMOUNT:(payment.amount_minor/100).toFixed(2),CURRENCY:currencyCodes[payment.currency],ORDER:bccOrder(payment.id),MERCHANT:this.config.merchant,TERMINAL:this.config.terminal,MERCH_GMT:'0',...this.fresh(),TRTYPE:'1',LANG:'ru',DESC:'JOBA '+(payment.benefit==='boost'?'продвижение':'подписка'),MERCH_NAME:'JOBA',BACKREF:this.config.public_origin+'/api/v1/public/billing/bcc/return?payment_id='+payment.id},['AMOUNT','CURRENCY','ORDER','MERCHANT','TERMINAL','MERCH_GMT','TIMESTAMP','TRTYPE','NONCE']);
  return '<!doctype html><html lang="ru"><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1"><meta name="referrer" content="no-referrer"><title>Оплата JOBA через БЦК</title><body><h1>Переход к защищённой оплате БЦК</h1><p>Данные карты вводятся только на странице банка.</p><form id="bank" method="POST" action="'+esc(this.endpoint)+'">'+Object.entries(fields).map(([k,v])=>'<input type="hidden" name="'+esc(k)+'" value="'+esc(v)+'">').join('')+'<button>Перейти к оплате</button></form><script>document.getElementById("bank").submit()</script></body></html>';
 }
 async status(values:{orderId?:string;orderNumber?:string}){const order=values.orderId??(values.orderNumber?bccOrder(values.orderNumber):'');return this.api(this.signed({ORDER:order,TERMINAL:this.config.terminal,TRTYPE:'90',TRAN_TRTYPE:'1',MERCH_GMT:'0',...this.fresh()},['ORDER','TERMINAL','TIMESTAMP','TRTYPE','NONCE']));}
 validateStatus(payment:RecordData,r:any){
  // Evidence is fetched directly over authenticated TLS from the bank, never
  // from browser query parameters or an unauthenticated notification.
  if(String(r.ORDER)!==bccOrder(payment.id)||String(r.TERMINAL)!==this.config.terminal)fail('BCC_EVIDENCE_MISMATCH');
  if(r.ACTION==='0'&&r.RC==='00'){
   const amount=String(r.AMOUNT??'');if(!/^\d+(?:\.\d{1,2})?$/.test(amount)||Math.round(Number(amount)*100)!==payment.amount_minor||String(r.CURRENCY)!==currencyCodes[payment.currency]||!String(r.RRN??'').trim()||!String(r.INT_REF??'').trim()||String(r.TRAN_TRTYPE??r.TRTYPE)!=='1')fail('BCC_EVIDENCE_MISMATCH');return 2;
  }
  if(['-24','-31','-33','-39','-40','-43'].includes(String(r.RC)))return 0;
  return ['2','3','6','7'].includes(String(r.ACTION))?6:0;
 }
 async decline(_payment:RecordData){return {pending:true};} // An unopened form has no bank charge; always recheck before local expiry.
 async validateProduct(productId:string,country:string){const p=(await this.store.all('price_version',country)).find(x=>x.payload?.provider==='bcc'&&x.payload.product_id===productId);if(!p)return fail('PRICE_MISMATCH');if(!this.countries.includes(country)||!this.currencies.includes(p.payload.currency))return fail('BCC_CURRENCY_UNAVAILABLE');return {product_id:productId,amount_minor:p.payload.amount_minor,currency:p.payload.currency};}
 async verifyPurchase(_reference:string,_account:string):Promise<VerifiedPurchase>{return fail('BCC_VERIFICATION_ROUTE');}
 async verifyWebhook(_raw:Buffer,_headers:Record<string,string>):Promise<never>{return fail('BCC_CALLBACK_ROUTE');}
 private refundPath(id:string){if(!/^[a-f0-9-]{36}$/i.test(id))return fail('REFUND_MISMATCH');return join(this.config.refund_journal_dir??(process.env.NODE_ENV==='production'?'/app/.local/bcc-refunds':'/tmp/joba-bcc-refunds'),createHash('sha256').update(this.environment+':'+this.config.terminal+':'+id).digest('hex')+'.json');}
 async requestRefund(request:{request_id:string;transaction_id:string;user_id:string;country:string;amount_minor:number;currency:string}):Promise<{reference:string}>{
  const path=this.refundPath(request.request_id),fingerprint=createHash('sha256').update(JSON.stringify([request.request_id,request.transaction_id,request.user_id,request.country,request.amount_minor,request.currency])).digest('hex');
  if(existsSync(path)){const prior=JSON.parse(readFileSync(path,'utf8'));if(prior.fingerprint!==fingerprint)return fail('REFUND_MISMATCH');return {reference:request.request_id};}
  const payment=(await this.store.select('bank_checkout',request.country,{owner:request.user_id,limit:1000})).find(p=>p.provider==='bcc'&&p.bank_order_id===request.transaction_id);
  if(!payment||payment.environment!==this.environment||!payment.bank_evidence?.rrn||!payment.bank_evidence?.int_ref||request.currency!==payment.currency||!Number.isSafeInteger(request.amount_minor)||request.amount_minor<1||request.amount_minor>payment.amount_minor||Date.now()-Date.parse(payment.confirmed_at)>30*86400000)return fail('REFUND_MISMATCH');
  const fields=this.signed({ORDER:payment.bank_order_id,ORG_AMOUNT:(payment.amount_minor/100).toFixed(2),AMOUNT:(request.amount_minor/100).toFixed(2),CURRENCY:currencyCodes[payment.currency],RRN:payment.bank_evidence.rrn,INT_REF:payment.bank_evidence.int_ref,TERMINAL:this.config.terminal,MERCH_GMT:'0',MERCH_RN_ID:request.request_id.replaceAll('-','').slice(0,16),TRTYPE:'14',...this.fresh()},['ORDER','ORG_AMOUNT','AMOUNT','CURRENCY','RRN','INT_REF','TERMINAL','TIMESTAMP','TRTYPE','NONCE']);
  // A durable, exclusive marker precedes the financial command, outside the DB
  // transaction. A process crash or SQL rollback must never resend a refund.
  mkdirSync(join(path,'..'),{recursive:true,mode:0o700});
  const receipt={...request,fingerprint,environment:this.environment,status:'pending',refund_id:request.request_id};
  try{writeFileSync(path,JSON.stringify(receipt),{flag:'wx',mode:0o600,flush:true});}catch(e){if((e as any).code==='EEXIST'){if(JSON.parse(readFileSync(path,'utf8')).fingerprint!==fingerprint)return fail('REFUND_MISMATCH');return {reference:request.request_id};}throw e;}
  try{const r=await this.api(fields);const matches=String(r.ORDER)===payment.bank_order_id&&String(r.TERMINAL)===this.config.terminal&&String(r.TRTYPE??r.TRAN_TRTYPE)==='14'&&String(r.CURRENCY)===currencyCodes[payment.currency]&&/^\d+(?:\.\d{1,2})?$/.test(String(r.AMOUNT))&&Math.round(Number(r.AMOUNT)*100)===request.amount_minor;
   const final={...receipt,status:matches&&r.ACTION==='0'&&r.RC==='00'?'succeeded':matches&&['2','3'].includes(String(r.ACTION))?'failed':'pending',refund_id:matches&&r.INT_REF?String(r.INT_REF):request.request_id};
   const tmp=path+'.'+randomBytes(8).toString('hex');writeFileSync(tmp,JSON.stringify(final),{mode:0o600});renameSync(tmp,path);
  }catch(_){/* Ambiguous bank result is reconciled manually; never replayed. */}
  return {reference:request.request_id};
 }
 async verifyRefund(id:string,account:string):Promise<VerifiedRefund>{
  const request=await this.store.get(id);if(!request||request.kind!=='refund_request'||request.owner!==account)return fail('REFUND_MISMATCH');
  const path=this.refundPath(id);if(!existsSync(path))return fail('REFUND_MISMATCH');const receipt=JSON.parse(readFileSync(path,'utf8'));
  if(receipt.user_id!==account||receipt.country!==request.country||receipt.amount_minor!==request.amount_minor||receipt.currency!==request.currency)return fail('REFUND_MISMATCH');
  return {environment:this.environment,provider:'bcc',request_id:id,refund_id:receipt.refund_id,transaction_id:receipt.transaction_id,user_id:account,country:request.country,amount_minor:receipt.amount_minor,currency:receipt.currency,status:receipt.status};
 }
}
