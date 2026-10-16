import {HttpException} from '@nestjs/common';
export function referralPolicy(p:any){
 const fail=(message:string):never=>{throw new HttpException({error:{code:'VALIDATION_ERROR',message,details:{},retryable:false}},422);};
 if(!p||!Number.isSafeInteger(p.threshold)||p.threshold<1||p.threshold>100||!Number.isSafeInteger(p.budget_units)||p.budget_units<1||p.budget_units>1000000||!Number.isSafeInteger(p.reward_duration_seconds)||p.reward_duration_seconds<60||p.reward_duration_seconds>366*86400)fail('Проверьте порог, бюджет и длительность привилегии');
 if(!['completed_order','executor_verified'].includes(p.qualifying_event))fail('Укажите подтверждаемое событие');
 if(p.multilevel||p.cash_payout)fail('Допустимы только одноуровневые неденежные привилегии');
 if(!Array.isArray(p.capabilities)||!p.capabilities.length||new Set(p.capabilities).size!==p.capabilities.length||p.capabilities.some((x:any)=>!['search_full','send_offer','publish_profile'].includes(x)))fail('Выберите доступные привилегии исполнителя');
 return {threshold:p.threshold,budget_units:p.budget_units,reward_duration_seconds:p.reward_duration_seconds,qualifying_event:p.qualifying_event,capabilities:p.capabilities,multilevel:false,cash_payout:false};
}
