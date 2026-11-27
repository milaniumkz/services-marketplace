import {RecordData} from './store';
/** Calendar years avoid shortening the approved period across leap years. */
export function retentionCutoff(policy:RecordData|undefined,days:number,now:Date){
 const date=new Date(now.getTime()-days*86400000);
 if(policy?.payload?.account_removal==='immediate'){
  date.setTime(now.getTime());date.setUTCFullYear(date.getUTCFullYear()-3);
 }
 return date;
}
