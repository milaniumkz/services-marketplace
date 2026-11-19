import {HttpException} from '@nestjs/common';
import {isDeepStrictEqual} from 'node:util';
import {Store,RecordData} from './store';
import {editableContent} from './content-revisions';
const fields=['title','description','city','category_id','category_ids','price','work_modes','service_cities','languages','travel_radius_km','experience_years','availability','gallery_ids','public_location'];
// Old apps submit a complete form after an upload. Rebase untouched fields only;
// two devices changing the same value must still see a conflict.
export async function rebaseProfile(store:Store,current:RecordData,body:any){
 if(body.expected_version===current.version)return body;
 const conflict=()=>{throw new HttpException({error:{code:'STATE_CONFLICT',message:'Это поле изменено на другом устройстве. Обновите профиль и повторите изменение.',details:{current_version:current.version},retryable:false}},409);};
 if(!Number.isSafeInteger(body.expected_version)||body.expected_version<1)return conflict();
 const row=(await store.db.query<{data:RecordData}>("SELECT data FROM records WHERE kind='contractor_edit_snapshot' AND country=$1 AND owner=$2 AND data->>'source_id'=$3 AND (data->>'source_version')::integer=$4 AND (data->>'created_at')::timestamptz>CURRENT_TIMESTAMP-interval '1 day' LIMIT 1",[current.country,current.owner,current.id,body.expected_version])).rows[0]?.data;
 if(!row)return conflict();
 const base=row.content,latest=editableContent(current),merged={...body,expected_version:current.version};
 for(const key of fields){if(!Object.hasOwn(body,key))continue;
  if(isDeepStrictEqual(body[key],base[key]))merged[key]=latest[key];
  else if(!isDeepStrictEqual(base[key],latest[key])&&!isDeepStrictEqual(body[key],latest[key]))return conflict();
 }
 return merged;
}
