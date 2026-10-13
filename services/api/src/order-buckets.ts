import {HttpException} from '@nestjs/common';
export function orderBucket(bucket:unknown):string[]|undefined {
  if(bucket===undefined)return undefined;
  const values:Record<string,string[]>={
    active:['open','assigned','in_progress','completion_requested'],
    completed:['completed','cancelled','expired'],
    drafts:['draft'],
  };
  if(typeof bucket!=='string'||!Object.hasOwn(values,bucket))throw new HttpException({error:{
    code:'VALIDATION_ERROR',message:'Неизвестный раздел заказов',details:{field:'bucket'},retryable:false}},400);
  return values[bucket];
}
