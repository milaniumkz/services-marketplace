import {HttpException} from '@nestjs/common';
const bad=(field:string,message:string):never=>{throw new HttpException({error:{code:'VALIDATION_ERROR',message,details:{field},retryable:false}},400);};
export function adminOrderConditions(q:any,bind:(value:any)=>string){
 const where:string[]=[];
 const present=(key:string)=>q[key]!==undefined&&q[key]!=='';
 for(const [key,label,expression] of [['order_id','ID заказа','r.id::text'],['customer_id','ID заказчика','r.owner'],['executor_id','ID исполнителя',"r.data->>'executor_id'"],['category_id','ID категории',"r.data->>'category_id'"]])if(present(key)){
  if(!/^[0-9a-f]{8}-[0-9a-f-]{27}$/i.test(String(q[key])))bad(key,`В поле «${label}» укажите корректный ID.`);
  where.push(`${expression}=${bind(q[key])}`);
 }
 for(const [key,column] of [['customer','r.owner'],['executor',"r.data->>'executor_id'"]])if(present(key)){
  if(String(q[key]).length>120)bad(key,'Имя участника — не более 120 символов.');
  const term=bind('%'+String(q[key]).replace(/[\\%_]/g,'\\$&')+'%');
  where.push(`EXISTS(SELECT 1 FROM records person WHERE person.kind='user' AND person.country=r.country AND person.id::text=${column} AND (person.id::text ILIKE ${term} OR person.data->>'display_name' ILIKE ${term}))`);
 }
 if(present('address')){if(String(q.address).length>250)bad('address','Адрес — не более 250 символов.');where.push(`COALESCE(r.data->>'exact_address',r.data->>'address','') ILIKE ${bind('%'+String(q.address).replace(/[\\%_]/g,'\\$&')+'%')}`);}
 const enums:Record<string,string[]>={work_mode:['onsite','remote','hybrid'],currency:['KZT','KGS','RUB','BYN'],moderation_status:['approved','pending_review','pending_moderation','quarantined','hidden','rejected','clean']};
 for(const [key,values] of Object.entries(enums))if(present(key)){
  if(!values.includes(String(q[key])))bad(key,'Выберите допустимое значение фильтра.');
  where.push(`r.data->>'${key}'=${bind(q[key])}`);
 }
 if(present('city')){if(String(q.city).length>120)bad('city','Город — не более 120 символов.');where.push(`COALESCE(r.data->>'city','') ILIKE ${bind('%'+String(q.city).replace(/[\\%_]/g,'\\$&')+'%')}`);}
 if(present('category')){if(String(q.category).length>120)bad('category','Название категории — не более 120 символов.');where.push(`COALESCE(r.data->'category_snapshot'->>'title','') ILIKE ${bind('%'+String(q.category).replace(/[\\%_]/g,'\\$&')+'%')}`);}
 for(const [key,expr] of [['has_executor',"COALESCE(r.data->>'executor_id','')<>''"],['has_photos',"CASE WHEN jsonb_typeof(r.data->'upload_ids')='array' THEN jsonb_array_length(r.data->'upload_ids') ELSE 0 END>0"],['has_address',"COALESCE(r.data->>'exact_address',r.data->>'address','')<>''"]])if(present(key)){
  if(!['yes','no'].includes(q[key]))bad(key,'Выберите «Да», «Нет» или «Все».');where.push(q[key]==='yes'?`(${expr})`:`NOT (${expr})`);
 }
 if(present('budget_mode')){if(!['fixed','negotiable'].includes(q.budget_mode))bad('budget_mode','Выберите тип бюджета.');where.push(`r.data->>'budget_amount' IS ${q.budget_mode==='fixed'?'NOT ':''}NULL`);}
 for(const field of ['budget','agreed']){
  const parse=(key:string)=>{if(!present(key))return undefined;const raw=String(q[key]).replace(',','.');if(!/^\d+(\.\d{1,2})?$/.test(raw))bad(key,'Сумма должна быть неотрицательной, с точностью до двух знаков после запятой.');const n=Math.round(Number(raw)*100);if(!Number.isSafeInteger(n))bad(key,'Сумма слишком большая.');return n;};
  const min=parse(field+'_min'),max=parse(field+'_max');if(min!==undefined&&max!==undefined&&min>max)bad(field+'_max','Максимальная сумма должна быть не меньше минимальной.');
  if((min!==undefined||max!==undefined)&&q.admin_country==='ALL'&&!present('currency'))bad('currency','Для фильтра по сумме во всех странах выберите валюту.');
  if(min!==undefined)where.push(`(r.data->>'${field}_amount')::numeric>=${bind(min)}`);
  if(max!==undefined)where.push(`(r.data->>'${field}_amount')::numeric<=${bind(max)}`);
 }
 const dates=['created_at','published_at','started_at','completed_at','cancelled_at','expires_at','updated_at'];
 if(present('date_field')&&!dates.includes(q.date_field))bad('date_field','Выберите тип даты из списка.');
 const dateField=q.date_field||'created_at';
 const day=(key:string)=>{if(!present(key))return undefined;const raw=String(q[key]);const date=new Date(raw+'T00:00:00Z');if(!/^\d{4}-\d{2}-\d{2}$/.test(raw)||Number(raw.slice(0,4))<1900||Number(raw.slice(0,4))>2200||!Number.isFinite(date.getTime())||date.toISOString().slice(0,10)!==raw)bad(key,'Укажите существующую дату.');return date.getTime();};
 const from=day('date_from'),to=day('date_to');if(from!==undefined&&to!==undefined&&from>to)bad('date_to','Конечная дата должна быть не раньше начальной.');
 if(from!==undefined)where.push(`(r.data->>'${dateField}')::timestamptz>=${bind(new Date(from).toISOString())}::timestamptz`);
 if(to!==undefined)where.push(`(r.data->>'${dateField}')::timestamptz<${bind(new Date(to+86400000).toISOString())}::timestamptz`);
 return where;
}
