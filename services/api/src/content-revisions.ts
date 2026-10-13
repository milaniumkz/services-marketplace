import {RecordData} from './store';

/** A draft is private; the approved root remains the public version during review. */
export function editableContent(record:RecordData):RecordData {
  return {...record,...record.draft,version:record.version,draft:undefined,public_status:record.status};
}
export function publicContent(record:RecordData):RecordData {
  const {draft,reason,reviewer_id,rejection_reason,case_id,public_status,...visible}=record;
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
  return ['published','paused'].includes(record.status)
    ? {...record,draft:{...record.draft,status:'pending_review'},version:record.version+1}
    : {...record,status:'pending_review',version:record.version+1};
}
