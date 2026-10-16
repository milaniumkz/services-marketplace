import { HttpException } from '@nestjs/common';
import {Temporal} from '@js-temporal/polyfill';
function invalid(field:string,message:string):never{throw new HttpException({error:{code:'VALIDATION_ERROR',message,details:{field},retryable:false}},400);}
export function attributes(schema:any,value:any={}) {
  if(!value||Array.isArray(value)||typeof value!=='object'||Object.keys(value).length>50)invalid('attributes','Проверьте дополнительные поля');
  const fields=schema?.properties??{};
  for(const key of Object.keys(value)) {
    const spec=Object.hasOwn(fields,key)?fields[key]:undefined;if(!spec)invalid('attributes.'+key,'Поле не входит в схему категории');
    const v=value[key];if(spec.type==='string'&&(typeof v!=='string'||v.length>(spec.maxLength??1000)||v.length<(spec.minLength??0)))invalid('attributes.'+key,'Проверьте текст');
    if(spec.type==='number'&&(typeof v!=='number'||!Number.isFinite(v)||v<(spec.minimum??-Infinity)||v>(spec.maximum??Infinity)))invalid('attributes.'+key,'Проверьте число');
    if(spec.type==='integer'&&(!Number.isSafeInteger(v)||v<(spec.minimum??-Infinity)||v>(spec.maximum??Infinity)))invalid('attributes.'+key,'Проверьте целое число');
    if(spec.type==='boolean'&&typeof v!=='boolean')invalid('attributes.'+key,'Нужно логическое значение');
    if(spec.enum&&!spec.enum.includes(v))invalid('attributes.'+key,'Выберите допустимое значение');
  }
  for(const key of schema?.required??[])if(value[key]===undefined)invalid('attributes.'+key,'Заполните обязательное поле');
  return value;
}
export function timeWindow(value:any) {
  if(value===undefined)return undefined;
  let dates:any;
  if(value?.start_date!==undefined||value?.end_date!==undefined) {
    if(typeof value.start_date!=='string'||typeof value.end_date!=='string'||
      !/^\d{4}-\d{2}-\d{2}$/.test(value.start_date)||!/^\d{4}-\d{2}-\d{2}$/.test(value.end_date))invalid('time_window','Выберите корректные даты');
    try {
      const start=Temporal.PlainDate.from(value.start_date),end=Temporal.PlainDate.from(value.end_date);
      if(Temporal.PlainDate.compare(end,start)<0)invalid('time_window','Окончание раньше начала');
      dates={start_date:value.start_date,end_date:value.end_date};
      value={...value,start:start.toZonedDateTime(value.time_zone).toInstant().toString(),
        end:end.add({days:1}).toZonedDateTime(value.time_zone).toInstant().toString()};
    }catch{invalid('time_window','Проверьте даты и часовой пояс');}
  }
  if(!value||!Number.isFinite(Date.parse(value.start))||!Number.isFinite(Date.parse(value.end))||Date.parse(value.end)<Date.parse(value.start))invalid('time_window','Проверьте начало и окончание');
  try{new Intl.DateTimeFormat('ru',{timeZone:value.time_zone}).format(new Date());}catch{invalid('time_window.time_zone','Нужен IANA time zone');}
  return {start:new Date(value.start).toISOString(),end:new Date(value.end).toISOString(),time_zone:value.time_zone,...dates};
}
