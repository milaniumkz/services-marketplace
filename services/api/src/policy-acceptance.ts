import {RecordData} from './store';
export const policyFamily=(type:string)=>['privacy','privacy_policy'].includes(type)?'privacy':['terms','terms_of_use'].includes(type)?'terms':type;
/** A new notice revision is not a new consent event. Preserve original evidence
 * and explicit withdrawal; this applies only to the two platform documents. */
export function existingPolicyAcceptance(document:RecordData,consents:RecordData[],documents:RecordData[]){
 const type=policyFamily(document.type);
 if(!['privacy','terms'].includes(type))return undefined;
 const ids=new Set(documents.filter(d=>d.country===document.country&&policyFamily(d.type)===type).map(d=>d.id));
 return consents.filter(c=>c.country===document.country&&ids.has(c.document_id)).sort((a,b)=>(b.sequence??0)-(a.sequence??0))[0];
}
