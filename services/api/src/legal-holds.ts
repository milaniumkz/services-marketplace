import {HttpException} from '@nestjs/common';
import {RecordData,Store} from './store';
const fileFields=['file','document_refs','upload_ids','revision_upload_ids','completion_upload_ids','photos','gallery_ids','avatar_id','cover_id'];
export const holdFields:Record<string,string[]>={upload:['file'],support:['subject'],support_note:['text'],case:['description','upload_ids','appeal_reason','appeal_upload_ids'],user:['display_name','avatar_id'],verification:['document_refs'],order:['title','description','completion_note','upload_ids','revision_upload_ids','completion_upload_ids'],message:['text','upload_ids'],support_message:['text','upload_ids'],review:['text'],portfolio:['title','description','photos','cover_id'],contractor:['title','description','gallery_ids']};
function invalid(message:string):never{throw new HttpException({error:{code:'VALIDATION_ERROR',message,retryable:false}},400);}
export async function holdSnapshot(store:Store,target:RecordData,fields:any){
 if(!Array.isArray(fields)||!fields.length||fields.some(f=>typeof f!=='string'||!holdFields[target.kind]?.includes(f)))invalid('Укажите конкретные разрешённые поля удержания');
 if(target.retention_minimized_at)throw new HttpException({error:{code:'STATE_CONFLICT',message:'Данные уже минимизированы',retryable:false}},409);
 if(['purge_pending','purged','deleted','archived','retention_minimized'].includes(target.status))throw new HttpException({error:{code:'STATE_CONFLICT',message:'Данные уже очищены или недоступны для нового удержания',retryable:false}},409);
 const unique=[...new Set<string>(fields)],snapshot:Record<string,any>={};
 for(const field of unique){
  if(field==='file')snapshot.file=target.id;
  else if(target[field]===undefined||target[field]===null)invalid('Выбранное поле не содержит данных');
  else snapshot[field]=structuredClone(target[field]);
 }
 if(Buffer.byteLength(JSON.stringify(snapshot))>65536)invalid('Объём выбранных полей превышает допустимый размер');
 for(const id of heldFileIds(snapshot)){
  const file=await store.get(id);if(!file||file.kind!=='upload'||file.country!==target.country||['purge_pending','purged'].includes(file.status))invalid('Файл удержания недоступен или уже очищается');
 }
 return {fields:unique,field_snapshot:snapshot,target_version:target.version};
}
export function heldFileIds(snapshot:Record<string,any>){return fileFields.flatMap(field=>Array.isArray(snapshot[field])?snapshot[field]:typeof snapshot[field]==='string'?[snapshot[field]]:[]).filter((id):id is string=>typeof id==='string');}
