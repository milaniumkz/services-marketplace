import {RecordData} from './store';

/** A draft is private; the approved root remains the public version during review. */
export function editableContent(record:RecordData):RecordData {
  return {...record,...record.draft,version:record.version,draft:undefined,public_status:record.status};
}
export function publicContent(record:RecordData):RecordData {
  const {exact_address,exact_location,draft,reason,reviewer_id,rejection_reason,case_id,public_status,revision_reason,revision_upload_ids,revision_time_window,completion_note,completion_upload_ids,completion_requested_at,agreed_start_at,agreed_start_local,agreed_duration_minutes,agreed_time_zone,...visible}=record;
  return visible as RecordData;
}
export function editContent(record:RecordData,changes:Record<string,any>):RecordData {
  const current=editableContent(record);
  const textChanged=['title','description'].some(key=>changes[key]!==undefined&&changes[key]!==current[key]);
  const moderation=!textChanged&&current.moderation_status==='quarantined'
    ? {status:current.status,moderation_status:'quarantined',case_id:current.case_id}
    : {status:'draft',moderation_status:'unreviewed',case_id:undefined};
  return ['published','paused'].includes(record.status)
    ? {...record,draft:{...record.draft,...changes,...moderation,reason:undefined,reviewer_id:undefined},version:record.version+1}
    : {...record,...changes,draft:undefined,...moderation,reason:undefined,reviewer_id:undefined,version:record.version+1};
}
export function submitContent(record:RecordData):RecordData {
  // Only identity documents require a staff decision. Merge the private edit
  // atomically so public readers see the complete new revision immediately.
  const content=editableContent(record);
  return {...content,status:'published',moderation_status:'visible',published_at:record.published_at??new Date().toISOString(),updated_at:new Date().toISOString(),draft:undefined,reason:undefined,reviewer_id:undefined,version:record.version+1};
}
