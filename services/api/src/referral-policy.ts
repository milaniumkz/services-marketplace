import {HttpException} from '@nestjs/common';
export function referralPolicy(p:any){
 const fail=(message:string):never=>{throw new HttpException({error:{code:'VALIDATION_ERROR',message,details:{},retryable:false}},422);};
 if(!p||!Number.isSafeInteger(p.threshold)||p.threshold<1||p.threshold>100||!Number.isSafeInteger(p.budget_units)||p.budget_units<1||p.budget_units>1000000||!Number.isSafeInteger(p.reward_duration_seconds)||p.reward_duration_seconds<60||p.reward_duration_seconds>366*86400)fail('Проверьте порог, бюджет и длительность привилегии');
 if(p.attribution_window_days!==undefined&&(!Number.isSafeInteger(p.attribution_window_days)||p.attribution_window_days<1||p.attribution_window_days>365))fail('Окно ввода кода должно быть от 1 до 365 суток после регистрации');
 if(!['registered','completed_order','executor_verified'].includes(p.qualifying_event))fail('Укажите подтверждаемое событие');
 if(p.multilevel||p.cash_payout)fail('Допустимы только одноуровневые неденежные привилегии');
 const kind=p.reward_kind??'access';if(!['access','discount','subscription_days'].includes(kind))fail('Выберите вид награды');
 if(kind==='discount'){
  if(!Number.isSafeInteger(p.discount_percent)||p.discount_percent<1||p.discount_percent>100)fail('Скидка должна быть от 1 до 100 процентов');
  if(!Array.isArray(p.discount_services)||!p.discount_services.length||p.discount_services.some((v:any)=>!['all','standard','premium','customer','renewal','upgrade','top100','boost'].includes(v)))fail('Выберите услуги для персональной скидки');
  if(!Number.isSafeInteger(p.discount_max_uses??0)||(p.discount_max_uses??0)<0||(p.discount_max_uses??0)>10000)fail('Укажите от 0 до 10000 применений скидки; 0 — без ограничения');
 }else if(kind==='subscription_days'){
  if(!['current','standard','premium','customer','top100'].includes(p.reward_plan))fail('Выберите тариф или Топ-100 для бонусных дней');
 }else if(!Array.isArray(p.capabilities)||!p.capabilities.length||new Set(p.capabilities).size!==p.capabilities.length||p.capabilities.some((x:any)=>!['search_full','send_offer','publish_profile'].includes(x)))fail('Выберите доступные привилегии исполнителя');

 return {...(p.attribution_window_days!==undefined?{attribution_window_days:p.attribution_window_days}:{}),threshold:p.threshold,budget_units:p.budget_units,reward_duration_seconds:p.reward_duration_seconds,qualifying_event:p.qualifying_event,capabilities:kind==='access'?p.capabilities:[],...(kind==='discount'?{reward_kind:kind,discount_percent:p.discount_percent,discount_services:[...new Set(p.discount_services)],discount_max_uses:p.discount_max_uses??0}:kind==='subscription_days'?{reward_kind:kind,reward_plan:p.reward_plan}:{}),multilevel:false,cash_payout:false};
}
