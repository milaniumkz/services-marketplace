import {createHash} from 'node:crypto';
import {HttpException} from '@nestjs/common';
import {RecordData,Store} from './store';
const fields:Record<string,string[]>={
 user:['display_name','avatar_id','city'],
 order:['title','description','attributes','category_id','city','budget_amount','currency','time_window','upload_ids'],
 contractor:['title','description','category_id','category_ids','gallery_ids','price','work_modes','service_cities','languages','experience_years','travel_radius_km'],
 portfolio:['title','description','category_id','photos','cover_id','order_id','rights_confirmed'],
 message:['text','thread_id','upload_ids','tombstone'],review:['text','rating','order_id','target_id'],offer:['text','amount','currency','order_id'],
};
const canonical=(value:any):any=>Array.isArray(value)?value.map(canonical):value&&typeof value==='object'?Object.fromEntries(Object.keys(value).sort().map(key=>[key,canonical(value[key])])):value;
export function targetSnapshot(target:RecordData,scope:string='public'){
 const effective=scope==='draft'?{...target,...target.draft}:target;
 return Object.fromEntries((fields[target.kind]??[]).filter(key=>effective[key]!==undefined).map(key=>[key,effective[key]]));
}
export function contentHash(value:any){return createHash('sha256').update(JSON.stringify(canonical(value))).digest('hex');}
export function freezeTarget(target:RecordData,scope:string='public'){
 const snapshot=targetSnapshot(target,scope),effective=scope==='draft'?{...target,...target.draft}:target;
 return {target_version:target.version,target_revision:effective.revision,target_scope:scope,target_snapshot:snapshot,target_content_hash:contentHash(snapshot),previous_target_status:effective.status};
}
export function visibleCase(record:RecordData){
 const {internal_notes,target_snapshot,target_hash,target_content_hash,previous_target_status,source_private_case_id,...visible}=record;
 if(visible.effects){const {target_content_hash_after,...effects}=visible.effects;visible.effects=effects;}
 return visible;
}
function fail(code:string,message:string,status=409):never{throw new HttpException({error:{code,message,details:{},retryable:false}},status);}
export async function resolveEffects(store:Store,incident:RecordData,decision:string,expectedTargetVersion:unknown){
 const target=await store.get(incident.target_id),scope=incident.target_scope??'public';
 if(!target||target.country!==incident.country||target.kind!==incident.target_type){if(decision!=='no_violation')fail('STATE_CONFLICT','Материал больше недоступен');return releaseUnavailableTarget(store,incident);}
 const snapshot=targetSnapshot(target,scope),hash=contentHash(snapshot);
 let changed=false,targetAction='unchanged';
 const frozen=incident.target_content_hash;
 const matches=frozen?hash===frozen:(scope==='draft'?target.draft?.case_id:target.case_id)===incident.id;
 const restoring=decision==='overturned'&&incident.effects?.target_action==='hidden';
 if(decision==='content_removed'||restoring||['no_violation','overturned'].includes(decision)&&matches){
  if(expectedTargetVersion!==target.version)fail('STATE_CONFLICT','Материал изменился. Обновите карточку дела.');
  if(decision==='content_removed'&&!matches)fail('TARGET_CHANGED','После обращения материал изменён. Решение не может удалить другую версию.');
  if(restoring&&hash!==incident.effects.target_content_hash_after)fail('TARGET_CHANGED','После решения материал изменён. Нельзя восстановить старую версию поверх новой.');
  const effective=scope==='draft'?{...target,...target.draft}:target;
  let patch:any={};
  if(decision==='content_removed'){
   patch={moderation_status:'hidden',case_id:incident.id};if(scope==='draft')patch.status='rejected';
   if(target.kind==='user')patch={...patch,display_name:'Пользователь',avatar_id:null};
   targetAction='hidden';changed=true;
  }else{
   if(restoring){if(!incident.target_snapshot)fail('EVIDENCE_UNAVAILABLE','Нет зафиксированного материала для восстановления');patch={...incident.target_snapshot};}
   const linked=(await store.all('case',incident.country)).some(c=>c.id!==incident.id&&c.target_id===target.id&&(c.target_scope??'public')===scope&&!['resolved','closed','dismissed'].includes(c.status));
   if(linked)fail('STATE_CONFLICT','По этой версии остаётся другое открытое дело');
   if(!restoring&&effective.moderation_status==='hidden'&&effective.case_id&&effective.case_id!==incident.id){
    const previous=await store.get(effective.case_id);
    if(previous?.decision==='content_removed'&&previous.effects?.target_content_hash_after===hash)fail('STATE_CONFLICT','По этой версии уже подтверждено нарушение. Нужна апелляция по исходному решению.');
   }
   patch={...patch,moderation_status:'reviewed',case_id:undefined};
   if(effective.status==='pending_moderation'||scope==='draft'&&restoring){const previous=incident.previous_target_status??'draft';patch.status=target.kind==='order'&&previous==='open'&&target.expires_at<=new Date().toISOString()?'expired':previous;}
   targetAction='restored';changed=true;
  }
  const next=scope==='draft'?{...target,draft:{...target.draft,...patch},version:target.version+1}:{...target,...patch,version:target.version+1};
  await store.put(next,{skipContentCheck:true});
 }
 if(['no_violation','overturned'].includes(decision)&&!matches&&!restoring)targetAction='superseded';
 const now=new Date().toISOString();
 const holds=(await store.all('auto_hold',incident.country)).filter(h=>h.case_id===incident.id&&h.status==='active');
 const sanctions=(await store.all('blacklist',incident.country)).filter(h=>h.case_id===incident.id&&h.status==='active');
 const currentSurface=scope==='draft'?target.draft:target;
 const upheldRemoval=decision==='sanction_upheld'&&incident.effects?.target_action==='hidden'&&currentSurface?.moderation_status==='hidden';
 if(decision==='sanction_upheld'&&!upheldRemoval&&!holds.some(h=>h.expires_at>now)&&!sanctions.some(h=>(!h.ends_at||h.ends_at>now)))fail('STATE_CONFLICT','Нет действующего ограничения по этому делу');
 let released=false;
 if(upheldRemoval)return {...incident.effects,restriction_released:false};
 if(['no_violation','content_removed','overturned'].includes(decision)){
  for(const hold of holds)await store.put({...hold,status:'released',version:hold.version+1,resolved_case_id:incident.id});
  if(decision==='overturned')for(const sanction of sanctions)await store.put({...sanction,status:'overturned',version:sanction.version+1});
  const owner=await store.get(incident.subject_user_id??target.owner);
  if(owner?.country===incident.country&&owner.status==='restricted'){
   const activeHold=(await store.all('auto_hold',incident.country)).some(h=>h.user_id===owner.id&&h.status==='active'&&h.expires_at>now);
   const activeSanction=(await store.all('blacklist',incident.country)).some(h=>h.user_id===owner.id&&h.status==='active'&&(!h.ends_at||h.ends_at>now));
   if(!activeHold&&!activeSanction){await store.put({...owner,status:'active',version:owner.version+1});released=true;}
  }
 }
 const current=changed?await store.get(target.id):target;
 return {target_action:targetAction,target_version:current?.version,target_content_hash_after:contentHash(targetSnapshot(current!,scope)),restriction_released:released};
}

async function releaseUnavailableTarget(store:Store,incident:RecordData){
 const now=new Date().toISOString();
 const holds=(await store.all('auto_hold',incident.country)).filter(h=>h.case_id===incident.id&&h.status==='active');
 for(const hold of holds)await store.put({...hold,status:'released',version:hold.version+1,resolved_case_id:incident.id});
 const owner=incident.subject_user_id?await store.get(incident.subject_user_id):undefined;
 let released=false;
 if(owner?.country===incident.country&&owner.status==='restricted'){
  const activeHold=(await store.all('auto_hold',incident.country)).some(h=>h.user_id===owner.id&&h.status==='active'&&h.expires_at>now);
  const activeSanction=(await store.all('blacklist',incident.country)).some(h=>h.user_id===owner.id&&h.status==='active'&&(!h.ends_at||h.ends_at>now));
  if(!activeHold&&!activeSanction){await store.put({...owner,status:'active',version:owner.version+1});released=true;}
 }
 return {target_action:'not_available',restriction_released:released};
}
