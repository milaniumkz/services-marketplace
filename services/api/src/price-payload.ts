import {HttpException} from '@nestjs/common';
const invalid=(message:string):never=>{throw new HttpException({error:{code:'VALIDATION_ERROR',message,details:{},retryable:false}},422);};
const currencies:Record<string,string>={KZ:'KZT',KG:'KGS',RU:'RUB',BY:'BYN'};
const zones:Record<string,string>={KZ:'Asia/Almaty',KG:'Asia/Bishkek',RU:'Europe/Moscow',BY:'Europe/Minsk'};
export function pricePayload(value:any,country:string){
 const p=value??{};
 if(!currencies[country])invalid('Страна не поддерживается');
 if(!['subscription','boost'].includes(p.product_type))invalid('Выберите подписку или продвижение');
 if(p.currency!==currencies[country]||!Number.isSafeInteger(p.amount_minor)||p.amount_minor<0)invalid('Проверьте сумму и валюту страны');
 for(const name of ['provider','product_id'])if(typeof p[name]!=='string'||!p[name].trim()||p[name].length>120)invalid('Укажите провайдера и идентификатор продукта');
 if(p.product_type==='subscription'&&p.plan!==undefined&&(!['standard','premium','customer'].includes(p.plan)||p.period!=='days'||p.duration_days!==30))invalid('Подписки действуют ровно 30 дней');
 if(!(p.product_type==='subscription'?(p.plan?['days']:['month','year']):['week','month','year','days']).includes(p.period))invalid('Выберите поддерживаемый период');
 if(p.period==='days'&&(!Number.isInteger(p.duration_days)||p.duration_days<1||p.duration_days>366))invalid('Укажите от 1 до 366 суток');
 if(p.time_zone!==zones[country])invalid('Часовой пояс должен соответствовать стране цены');
 if(p.role!==undefined&&p.role!==(p.product_type==='subscription'?(p.plan==='customer'?'customer':'executor'):'all'))invalid('Роль не соответствует выбранному тарифу');
 return {...(p.product_type==='subscription'&&p.plan?{plan:p.plan}:{}),product_type:p.product_type,provider:p.provider.trim(),product_id:p.product_id.trim(),amount_minor:p.amount_minor,currency:p.currency,period:p.period,time_zone:p.time_zone,role:p.product_type==='subscription'?(p.plan==='customer'?'customer':'executor'):'all',...(p.period==='days'?{duration_days:p.duration_days}:{})};
}
