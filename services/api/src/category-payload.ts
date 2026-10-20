import {HttpException} from '@nestjs/common';
import {Store,RecordData} from './store';
const invalid=(message:string):never=>{throw new HttpException({error:{code:'VALIDATION_ERROR',message,details:{},retryable:false}},422);};
export const categoryId=(r:RecordData):string=>r.payload?.category_id??r.id;
const icons=['briefcase','settings','layers','image','star','users'];
export function categoryPayload(value:any,country:string,stableId:string){
 const p=value??{},required=({KZ:['ru','kk'],KG:['ru','ky'],RU:['ru'],BY:['ru','be']} as Record<string,string[]>)[country];if(!required)invalid('Страна не поддерживается');
 const labels:Record<string,string>={};for(const [key,v] of Object.entries(p.labels??{})){if(!['ru','kk','ky','be','sr','en'].includes(key)||typeof v!=='string'||v.trim().length<2||v.length>120)invalid('Проверьте переводы названия');labels[key]=(v as string).trim();}
 if(required.some(k=>!labels[k]))invalid('Заполните обязательные переводы страны');
 if(!icons.includes(p.icon??'briefcase'))invalid('Выберите разрешённую иконку');
 if(p.parent_id!=null&&(typeof p.parent_id!=='string'||!/^[a-f0-9-]{36}$/i.test(p.parent_id)))invalid('Проверьте родительскую категорию');
 const schema=p.schema??{},properties=schema.properties??{},mandatory=schema.required??[];
 if(!properties||Array.isArray(properties)||typeof properties!=='object'||Object.keys(properties).length>50||!Array.isArray(mandatory)||new Set(mandatory).size!==mandatory.length||mandatory.some((k:any)=>typeof k!=='string'||!Object.hasOwn(properties,k)))invalid('Проверьте дополнительные поля и обязательность');
 const clean:Record<string,any>={};
 for(const [key,definition] of Object.entries(properties)){
  const d=definition as any;if(!/^[a-z][a-z0-9_]{0,49}$/.test(key)||['constructor','prototype','__proto__'].includes(key)||!d||!['string','number','integer','boolean'].includes(d.type)||d.pattern!==undefined||typeof d.title!=='string'||d.title.trim().length<2||d.title.length>120)invalid('Проверьте ключ, название и тип дополнительного поля');
  const result:any={type:d.type,title:d.title.trim()};
  if(d.type==='string'){for(const name of ['minLength','maxLength'])if(d[name]!==undefined){if(!Number.isInteger(d[name])||d[name]<0||d[name]>4000)invalid('Длина текста должна быть от 0 до 4000');result[name]=d[name];}if((d.minLength??0)>(d.maxLength??1000))invalid('Минимальная длина больше максимальной');}
  if(['number','integer'].includes(d.type)){for(const name of ['minimum','maximum'])if(d[name]!==undefined){if(!Number.isFinite(d[name])||d.type==='integer'&&!Number.isSafeInteger(d[name]))invalid('Проверьте границы числа');result[name]=d[name];}if((d.minimum??-Infinity)>(d.maximum??Infinity))invalid('Минимум больше максимума');}
  if(d.enum!==undefined){if(d.type!=='string'||!Array.isArray(d.enum)||!d.enum.length||d.enum.length>50||new Set(d.enum).size!==d.enum.length||d.enum.some((v:any)=>typeof v!=='string'||!v.trim()||v.length>(d.maxLength??1000)||v.length<(d.minLength??0)))invalid('Проверьте варианты выбора');result.enum=d.enum;}
  clean[key]=result;
 }
 return {category_id:stableId,labels,parent_id:p.parent_id??null,icon:p.icon??'briefcase',schema:{properties:clean,required:mandatory}};
}
export async function validateCategory(store:Store,r:RecordData){
 const p=categoryPayload(r.payload,r.country,categoryId(r));const rows=(await store.all('category',r.country)).filter(x=>x.status==='effective');
 let parent=p.parent_id;const seen=new Set([p.category_id]);while(parent){if(seen.has(parent))invalid('Дерево категорий содержит цикл');seen.add(parent);if(seen.size>100)invalid('Слишком глубокое дерево категорий');const record=rows.find(x=>categoryId(x)===parent);if(!record)invalid('Родитель должен быть опубликован в этой стране');parent=record!.payload.parent_id;}
 return {valid:true};
}
