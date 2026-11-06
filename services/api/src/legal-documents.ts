import {RecordData} from './store';
const family=(type:string)=>['privacy','privacy_policy'].includes(type)?'privacy':['terms','terms_of_use'].includes(type)?'terms':type;
/** Prefer the requested translation, falling back to a published regional text per document family. */
export function currentLegalDocuments(records:RecordData[],country:string,locale:string){
 const preferred='ru';
 const published=records.filter(d=>d.country===country&&d.status==='published').sort((a,b)=>String(b.published_at??b.created_at).localeCompare(String(a.published_at??a.created_at))||b.id.localeCompare(a.id));
 const result:RecordData[]=[];
 for(const type of new Set(published.map(d=>family(d.type)))){
  const candidates=published.filter(d=>family(d.type)===type);
  result.push(candidates.find(d=>d.locale===locale)??candidates.find(d=>d.locale===preferred)??candidates[0]);
 }
 return result;
}

/** Contact-only corrections retain prior accepted versions; policy changes do not. */
export const legalHashAccepted=(document:RecordData,hash:any)=>typeof hash==='string'&&(document.hash===hash||document.operator_contacts_only===true&&Array.isArray(document.operator_contact_previous_hashes)&&document.operator_contact_previous_hashes.includes(hash));
