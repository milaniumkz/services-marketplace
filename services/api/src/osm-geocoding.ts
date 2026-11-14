import {HttpException} from '@nestjs/common';
import {Store} from './store';
import {cityCatalog} from './city-catalog';
const failure=(status:number,code:string,message:string):never=>{throw new HttpException({error:{code,message,retryable:status>=429}},status);};
export function geoPoint(latitude:unknown,longitude:unknown){
 if(!['number','string'].includes(typeof latitude)||!['number','string'].includes(typeof longitude)||String(latitude).trim()===''||String(longitude).trim()==='')return failure(400,'VALIDATION_ERROR','Проверьте координаты');
 const lat=Number(latitude),lon=Number(longitude);
 if(!Number.isFinite(lat)||Math.abs(lat)>90||!Number.isFinite(lon)||Math.abs(lon)>180)return failure(400,'VALIDATION_ERROR','Проверьте координаты');
 return {latitude:Math.round(lat*1e6)/1e6,longitude:Math.round(lon*1e6)/1e6};
}
/** Shared queue: Nominatim public service allows at most one request per second. No autocomplete. */
export class OsmGeocoder {
 private tail:Promise<unknown>=Promise.resolve();private next=0;private queued=0;
 private cache=new Map<string,{at:number,value:any}>();private pending=new Map<string,Promise<any>>();
 constructor(private request:typeof fetch=fetch,private interval=1100){}
 async get(path:'search'|'reverse',params:Record<string,string>){
  const url=new URL('https://nominatim.openstreetmap.org/'+path);url.search=new URLSearchParams({format:'jsonv2','accept-language':'ru',addressdetails:'1',...params}).toString();
  const key=url.href,cached=this.cache.get(key);if(cached&&Date.now()-cached.at<86400000)return cached.value;
  if(this.pending.has(key))return this.pending.get(key);
  if(this.queued>=8)return failure(429,'RATE_LIMITED','Поиск адресов занят. Повторите через несколько секунд.');
  this.queued++;
  const run=this.tail.then(async()=>{
   const delay=this.next-Date.now();if(delay>0)await new Promise(resolve=>setTimeout(resolve,delay));this.next=Date.now()+this.interval;
   try{
    const response=await this.request(url,{headers:{'User-Agent':'JOBA/1.0 (+https://joba.com.kz)','Accept':'application/json'},signal:AbortSignal.timeout(8000)});
    if(!response.ok)return failure(503,'GEOCODER_UNAVAILABLE','Не удалось определить адрес. Выберите точку или введите адрес вручную.');
    const value=await response.json();if(path==='search'&&!Array.isArray(value)||path==='reverse'&&(!value||typeof value!=='object'||Array.isArray(value)||value.error))return failure(503,'GEOCODER_UNAVAILABLE','Адрес не найден. Выберите точку вручную.');
    if(this.cache.size>=500)this.cache.delete(this.cache.keys().next().value!);this.cache.set(key,{at:Date.now(),value});return value;
   }catch(error){if(error instanceof HttpException)throw error;return failure(503,'GEOCODER_UNAVAILABLE','Сервис адресов временно недоступен. Введите адрес вручную.');}
  }).finally(()=>{this.queued--;this.pending.delete(key);});
  this.tail=run.catch(()=>{});this.pending.set(key,run);return run;
 }
}
export const osmGeocoder=new OsmGeocoder();
export async function nearestCity(store:Store,country:string,point:{latitude:number,longitude:number}){
 const rows=(await cityCatalog(store,country)).items.filter(c=>Number.isFinite(c.latitude)&&Number.isFinite(c.longitude));
 const rad=Math.PI/180;
 const distance=(c:any)=>{const dlat=(c.latitude-point.latitude)*rad,dlon=(c.longitude-point.longitude)*rad;const a=Math.sin(dlat/2)**2+Math.cos(point.latitude*rad)*Math.cos(c.latitude*rad)*Math.sin(dlon/2)**2;return 6371*2*Math.asin(Math.sqrt(Math.min(1,a)));};
 const sorted=rows.map(c=>({city:c,distance:distance(c)})).sort((a,b)=>a.distance-b.distance);
 return sorted[0]&&sorted[0].distance<=100?{id:sorted[0].city.id,name:sorted[0].city.name,distance_km:Math.round(sorted[0].distance*10)/10}:null;
}
export async function geocode(store:Store,country:string,mode:'search'|'reverse',query:any,provider=osmGeocoder){
 let source:any;
 if(mode==='search'){
  if(typeof query.q!=='string'||query.q.trim().length<3||query.q.length>200)failure(400,'VALIDATION_ERROR','Введите адрес — от 3 до 200 символов');
  source=await provider.get('search',{q:query.q.trim(),countrycodes:country.toLowerCase(),limit:'5'});
 }else{const point=geoPoint(query.latitude,query.longitude);source=[await provider.get('reverse',{lat:String(point.latitude),lon:String(point.longitude),zoom:'18'})];}
 const result=[];
 for(const item of source){
  if(item.address?.country_code?.toUpperCase()!==country){if(mode==='reverse')failure(422,'LOCATION_OUTSIDE_COUNTRY','Местоположение находится в другой стране. Выберите точку в текущей стране или смените страну.');continue;}
  const point=geoPoint(item.lat,item.lon);
  result.push({...point,address:String(item.display_name??'').slice(0,500),city:await nearestCity(store,country,point)});
 }
 return {items:result,provider:'OpenStreetMap Nominatim',attribution:'© OpenStreetMap contributors',attribution_url:'https://www.openstreetmap.org/copyright'};
}
export function orderAddress(body:any){
 const result:any={};
 if(body.exact_address!==undefined){if(body.exact_address!==null&&(typeof body.exact_address!=='string'||body.exact_address.trim().length>500))failure(400,'VALIDATION_ERROR','Адрес — до 500 символов');result.exact_address=typeof body.exact_address==='string'?body.exact_address.trim():null;}
 if(body.exact_location!==undefined){result.exact_location=body.exact_location===null?null:geoPoint(body.exact_location?.latitude,body.exact_location?.longitude);result.public_location=result.exact_location?{latitude:Math.round(result.exact_location.latitude*100)/100,longitude:Math.round(result.exact_location.longitude*100)/100,approximate:true}:null;}
 return result;
}
