import {freezeTarget} from './case-evidence';
import {randomUUID} from 'node:crypto';
import {HttpException} from '@nestjs/common';
import {Store,RecordData} from './store';
const error=(status:number,code:string,message:string):never=>{throw new HttpException({error:{code,message,retryable:false}},status);};
const uuid=(v:any)=>typeof v==='string'&&/^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i.test(v);
function reason(b:any){if(typeof b.reason!=='string'||b.reason.trim().length<10||b.reason.length>1000)error(400,'VALIDATION_ERROR','Укажите основание от 10 до 1000 символов');return b.reason.trim();}
type Eligibility={code?:string;user?:RecordData;incident?:RecordData};
async function eligibility(store:Store,country:string,id:string,caseId:string):Promise<Eligibility>{
 const user=await store.get(id),incident=await store.get(caseId);
 if(!user||user.kind!=='user'||user.country!==country||user.staff_permissions?.length||!incident||incident.kind!=='case'||incident.country!==country)return {code:'NOT_AVAILABLE'};
 if((await store.all('blacklist',country)).some(r=>r.user_id===id&&r.reviewed_case_id===caseId&&r.status==='active'&&r.ends_at>new Date().toISOString()))return {code:'ALREADY_RESTRICTED'};
 if(!['active','restricted'].includes(user.status))return {code:'STATE_CONFLICT'};
 if((incident.subject_user_id??(incident.target_type==='user'?incident.target_id:null))!==id||['closed','dismissed'].includes(incident.status)||['no_violation','overturned'].includes(incident.decision))return {code:'CASE_NOT_ELIGIBLE'};
 return {user,incident};
}
/** Called inside the command transaction, after the dedicated permission and MFA checks. */
export async function accountRestrictionJobs(store:Store,actor:{id:string;country:string},method:string,path:string,b:any,callbacks:{audit:(action:string,id:string,reason:string)=>Promise<any>;notify:(user:string,id:string)=>Promise<any>}){
 const base={country:actor.country,owner:actor.id,created_at:new Date().toISOString(),version:1};
 if(path==='/admin/account-restriction-jobs/preview'&&method==='POST'){
  const explanation=reason(b),end=Date.parse(b.ends_at);
  if(!Number.isFinite(end)||end<=Date.now()||end>Date.now()+30*86400000)error(400,'VALIDATION_ERROR','Задайте конечный срок в пределах 30 дней');
  if(!Array.isArray(b.selection)||!b.selection.length||b.selection.length>100||b.selection.some((x:any)=>!uuid(x?.user_id)||!uuid(x?.case_id))||new Set(b.selection.map((x:any)=>x.user_id)).size!==b.selection.length)error(400,'VALIDATION_ERROR','Выберите от 1 до 100 уникальных аккаунтов с делами');
  const snapshot:Array<{id:string;case_id:string;code?:string;version?:number;case_version?:number}>=[];
  for(const item of b.selection){const check=await eligibility(store,actor.country,item.user_id,item.case_id);snapshot.push({id:item.user_id,case_id:item.case_id,...(check.code?{code:check.code}:{version:check.user!.version,case_version:check.incident!.version})});}
  const job:RecordData={...base,id:randomUUID(),kind:'account_restriction_job',status:'previewed',scope:'new_business',reason:explanation,ends_at:new Date(end).toISOString(),snapshot,eligible_count:snapshot.filter(x=>!x.code).length,processed:0,results:[],expires_at:new Date(Date.now()+600000).toISOString()};
  await store.put(job);await callbacks.audit('account_restrictions.preview',job.id,explanation);return job;
 }
 const match=path.match(/^\/admin\/account-restriction-jobs\/([^/]+)(?:\/(execute|cancel))?$/);if(!match)return;
 const job=await store.get(match[1]);if(!job||job.kind!=='account_restriction_job'||job.country!==actor.country)error(404,'NOT_FOUND','Задача недоступна');
 if(method==='GET'&&!match[2])return job;
 if(method!=='POST'||!match[2])return;
 const explanation=reason(b);if(b.expected_version!==job!.version)error(409,'STATE_CONFLICT','Снимок задачи изменился');
 if(job!.status!=='previewed')error(409,'STATE_CONFLICT','Задача уже завершена или отменена');
 if(match[2]==='cancel'){const r=await store.put({...job!,status:'canceled',version:job!.version+1});await callbacks.audit('account_restrictions.canceled',r.id,explanation);return r;}
 if(job!.owner===actor.id)error(403,'SECOND_APPROVAL_REQUIRED','Операцию подтверждает другой сотрудник с отдельным полномочием');
 if(b.confirm!==true||job!.expires_at<=new Date().toISOString()||job!.ends_at<=new Date().toISOString())error(409,'STATE_CONFLICT','Предпросмотр истёк или последствия не подтверждены');
 const results=[];
 for(const item of job!.snapshot){
  const check:Eligibility=item.code?{code:item.code}:await eligibility(store,actor.country,item.id,item.case_id);
  let code=check.code;if(!code&&(check.user!.version!==item.version||check.incident!.version!==item.case_version))code='STATE_CONFLICT';
  if(code){results.push({id:item.id,status:'skipped',code});continue;}
  const notice:RecordData={...base,id:randomUUID(),kind:'case',owner:item.id,subject_user_id:item.id,target_type:'user',target_id:item.id,...freezeTarget(check.user!),status:'resolved',decision:'sanction_upheld',decision_actor:actor.id,initial_decision_actor:actor.id,reason_code:'manual_review',public_reason:'Временное ограничение новых действий после проверки',description:'Новые действия временно ограничены после служебной проверки. Текущая работа, поддержка и данные аккаунта остаются доступны. Вы можете подать апелляцию.',effects:{target_action:'unchanged'},upload_ids:[]};
  await store.put(notice);
  const sanction:RecordData={...base,id:randomUUID(),kind:'blacklist',user_id:item.id,case_id:notice.id,reviewed_case_id:item.case_id,scope:'new_business',reason:job!.reason,status:'active',ends_at:job!.ends_at,job_id:job!.id,requested_by:job!.owner,approved_by:actor.id};
  await store.put(sanction);await store.put({...base,id:randomUUID(),kind:'case_decision',case_id:notice.id,decision:'sanction_upheld',reason:explanation,status:'applied',job_id:job!.id});await store.put({...check.user!,status:'restricted',version:check.user!.version+1});await callbacks.audit('account_restrictions.applied',sanction.id,explanation);await callbacks.notify(item.id,notice.id);results.push({id:item.id,status:'applied',sanction_id:sanction.id});
 }
 const r=await store.put({...job!,status:'completed',approved_by:actor.id,approval_reason:explanation,completed_at:new Date().toISOString(),processed:results.length,results,version:job!.version+1});await callbacks.audit('account_restrictions.executed',r.id,explanation);return r;
}
