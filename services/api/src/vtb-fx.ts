import {HttpException} from '@nestjs/common';
import {randomUUID,createHash} from 'node:crypto';
import {Store} from './store';
export type BankSettlement={provider:'vtb';invoice_amount_minor:number;invoice_currency:string;bank_amount_minor:number;bank_currency:'KZT';source:string;quoted_at:string;rate?:string;units?:number;rate_date?:string;source_url?:string};
const source='https://nationalbank.kz/rss/rates_all.xml';
const unavailable=():never=>{throw new HttpException({error:{code:'FX_RATE_UNAVAILABLE',message:'Курс пересчёта в тенге временно недоступен. Повторите позже; сумма не изменена.',retryable:true}},503);};
export function parseNbkRate(xml:string,currency:string,now=new Date()){
 if(!['RUB','BYN'].includes(currency)||Buffer.byteLength(xml)>262144||/<!DOCTYPE|<!ENTITY/i.test(xml))return unavailable();
 const item=[...xml.matchAll(/<item>([\s\S]*?)<\/item>/g)].map(m=>m[1]).find(v=>new RegExp('<title>\\s*'+currency+'\\s*</title>').test(v));if(!item)return unavailable();
 const text=(tag:string)=>item.match(new RegExp('<'+tag+'>\\s*([^<]+?)\\s*</'+tag+'>'))?.[1];
 const rate=text('description'),quant=text('quant'),date=text('pubDate');
 if(!rate||!/^\d{1,7}(\.\d{1,6})?$/.test(rate)||!quant||!/^\d{1,6}$/.test(quant)||!date||!/^\d{2}\.\d{2}\.\d{4}$/.test(date))return unavailable();
 const iso=date.split('.').reverse().join('-'),stamp=Date.parse(iso+'T00:00:00.000Z'),today=Date.parse(now.toISOString().slice(0,10)+'T00:00:00.000Z');
 if(!Number.isFinite(stamp)||new Date(stamp).toISOString().slice(0,10)!==iso||stamp<today-7*86400000||stamp>today+86400000||Number(rate)<=0||Number(quant)<1)return unavailable();
 return {invoice_currency:currency,bank_currency:'KZT',rate,units:Number(quant),rate_date:iso,source_url:source,source:'НБ РК',retrieved_at:now.toISOString(),response_sha256:createHash('sha256').update(xml).digest('hex')};
}
export function convertToKzt(amount:number,fx:{rate:string;units:number}){
 if(!Number.isSafeInteger(amount)||amount<0||amount>999999999999||!/^\d{1,7}(\.\d{1,6})?$/.test(fx.rate)||!Number.isSafeInteger(fx.units)||fx.units<1||fx.units>999999)return unavailable();
 const [whole,part='']=fx.rate.split('.'),n=BigInt(whole+part),d=BigInt(fx.units)*10n**BigInt(part.length);
 if(n<=0n||d<=0n)return unavailable();const result=Number((BigInt(amount)*n+d/2n)/d);
 if(!Number.isSafeInteger(result)||result>999999999999||amount>0&&result<1)return unavailable();return result;
}
export async function vtbSettlement(store:Store,amount:number,currency:string,now=new Date(),transport:typeof fetch=fetch):Promise<BankSettlement|undefined>{
 if(currency==='KZT')return;
 if(amount===0&&['RUB','BYN'].includes(currency))return {provider:'vtb',invoice_amount_minor:0,invoice_currency:currency,bank_amount_minor:0,bank_currency:'KZT',source:'zero_charge',quoted_at:now.toISOString()};
 if(!['RUB','BYN'].includes(currency))return unavailable();
 let cached=(await store.all('fx_rate','KZ')).filter(r=>r.invoice_currency===currency&&r.source_url===source&&r.retrieved_at<=now.toISOString()&&Date.parse(r.retrieved_at)>now.getTime()-6*3600000).sort((a,b)=>b.retrieved_at.localeCompare(a.retrieved_at))[0];
 if(!cached){try{const response=await transport(source,{signal:AbortSignal.timeout(8000),redirect:'error'});if(!response.ok)return unavailable();const xml=await response.text(),fx=parseNbkRate(xml,currency,now);cached=await store.put({id:randomUUID(),kind:'fx_rate',owner:'system',country:'KZ',version:1,created_at:now.toISOString(),...fx});}catch{return unavailable();}}
 return {provider:'vtb',invoice_amount_minor:amount,invoice_currency:currency,bank_amount_minor:convertToKzt(amount,cached as any),bank_currency:'KZT',rate:cached.rate,units:cached.units,rate_date:cached.rate_date,source:cached.source,source_url:source,quoted_at:now.toISOString()};
}
