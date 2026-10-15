import {HttpException} from '@nestjs/common';
export function rankingParameters(payload:any){
 const windowDays=payload?.window_days,dislikeWeight=payload?.dislike_weight,ageDays=payload?.age_days;
 if(!Number.isInteger(windowDays)||windowDays<1||windowDays>3650||!Number.isFinite(dislikeWeight)||dislikeWeight<0||dislikeWeight>100||!Number.isInteger(ageDays)||ageDays<1||ageDays>3650||payload.formula!==undefined&&payload.formula!=='log_likes_decay_v1')
  throw new HttpException({error:{code:'VALIDATION_ERROR',message:'Проверьте окно, вес отрицательной реакции и срок затухания рейтинга',details:{},retryable:false}},400);
 return {windowDays,dislikeWeight,ageDays};
}
