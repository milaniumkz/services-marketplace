import {HttpException} from '@nestjs/common';
const fail=(message:string):never=>{throw new HttpException({error:{code:'VALIDATION_ERROR',message,details:{},retryable:false}},422);};
export function monetizationPayload(p:any){
 if(!p||p.subscription_enabled!==true||typeof p.banner_ads_enabled!=='boolean'||typeof p.rewarded_access_enabled!=='boolean')fail('Подписка исполнителя обязательна; рекламные флаги должны быть независимыми');
 if(p.role!==undefined&&!['all','executor'].includes(p.role)||p.platform!==undefined&&p.platform!=='all')fail('Настройка действует для всей страны; подписка и награды доступны только исполнителю');
 const daily=p.daily_cap??5,cooldown=p.cooldown_seconds??300;
 if(!Number.isSafeInteger(daily)||daily<1||daily>1000||!Number.isSafeInteger(cooldown)||cooldown<0||cooldown>86400)fail('Лимит сессий — от 1 до 1000; пауза — от 0 до 86400 секунд');
 const field=(key:string,max:number)=>{const v=p[key]??'';if(typeof v!=='string'||v.length>max)fail('Проверьте настройки рекламных сетей');return v.trim();};
 const placements=p.banner_placements??[];
 if(!Array.isArray(placements)||placements.length>10||placements.some((x:any)=>typeof x!=='string'||!['catalog.inline','catalog.inline.end','home.inline','top.inline'].includes(x)))fail('Выберите разрешённые inline-размещения');
 let reward;
 if(p.reward_policy!==undefined){const r=p.reward_policy;
  if(!r||!['duration','action_credits'].includes(r.kind)||!Array.isArray(r.capabilities)||!r.capabilities.length||r.capabilities.some((x:any)=>!['search_full','send_offer','publish_profile'].includes(x)))fail('Выберите возможности рекламной награды исполнителя');
  if(!Number.isSafeInteger(r.duration_seconds)||r.duration_seconds<60||r.duration_seconds>2592000)fail('Срок награды — от минуты до 30 суток');
  if(r.kind==='action_credits'&&(!Number.isSafeInteger(r.credits)||r.credits<1||r.credits>100||r.capabilities.includes('search_full')))fail('Кредиты — от 1 до 100, только для действий исполнителя');
  reward={kind:r.kind,capabilities:[...new Set(r.capabilities)],duration_seconds:r.duration_seconds,...(r.kind==='action_credits'?{credits:r.credits}:{})};
 }
 if(p.rewarded_access_enabled&&!reward)fail('Укажите политику рекламной награды');
 return {subscription_enabled:true,banner_ads_enabled:p.banner_ads_enabled,rewarded_access_enabled:p.rewarded_access_enabled,role:'all',platform:'all',daily_cap:daily,cooldown_seconds:cooldown,banner_provider:field('banner_provider',100),banner_placements:[...new Set(placements)],provider:field('provider',100),policy_evidence:field('policy_evidence',4000),...(reward?{reward_policy:reward}:{})};
}
