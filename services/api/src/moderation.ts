import { randomUUID } from 'node:crypto';
import { RecordData, Store } from './store';
import { readSettings } from './settings';

export const TEXT_SURFACES: Record<string,string[]> = {
  user:['display_name'], order:['title','description','attributes'], offer:['text'], contractor:['title','description'],
  portfolio:['title','description'], message:['text'], review:['text']
};
const normalize=(s:string)=>s.normalize('NFKC').toLocaleLowerCase('und').replace(/\s+/gu,' ').trim();
const word=(s:string)=>/[\p{L}\p{N}_]/u.test(s);
export function matchesRule(source:string,value:string,type:'exact_word'|'phrase',exceptions:string[]=[]) {
  const hay=normalize(source),needle=normalize(value);let start=hay.indexOf(needle);
  const spans: Array<[number,number]>=[];
  for(const exception of exceptions){const allowed=normalize(exception);if(!allowed)continue;let index=hay.indexOf(allowed);while(index>=0){spans.push([index,index+allowed.length]);index=hay.indexOf(allowed,index+1);}}
  while(start>=0){const left=start===0||!word(Array.from(hay.slice(0,start)).at(-1)??''),right=start+needle.length===hay.length||!word(Array.from(hay.slice(start+needle.length))[0]??'');const exempt=spans.some(([a,b])=>start>=a&&start+needle.length<=b);if(left&&right&&!exempt)return true;start=hay.indexOf(needle,start+1);}return false;
}
export function validateRules(rules:any) {
  if(!Array.isArray(rules)||rules.length>1000)throw Error('Словарь: максимум 1000 правил');
  for(const r of rules)if(!['exact_word','phrase'].includes(r.type)||typeof r.value!=='string'||r.value.length<1||r.value.length>100||r.regex!==undefined)throw Error('Недопустимое правило словаря');
}
export class Moderation {
  constructor(private store:Store){}
  async check(data:RecordData) {
    const fields=TEXT_SURFACES[data.kind];if(!fields||data.owner==='provider'||data.owner==='system')return;
    const previous=await this.store.get(data.id);
    // Applying a non-content status decision never reopens the same episode.
    if(previous&&fields.every(f=>JSON.stringify(previous[f])===JSON.stringify(data[f])))return;
    const dictionaries=(await this.store.all('dictionary',data.country)).filter(d=>d.status==='published');
    const hits:any[]=[];
    for(const d of dictionaries)for(const r of d.payload.rules) {
      if(r.surfaces&&!r.surfaces.includes(data.kind))continue;
      for(const f of fields) {
        const source=typeof data[f]==='object'?JSON.stringify(data[f]):String(data[f]??'');if(matchesRule(source,r.value,r.type,d.payload.exceptions??[]))hits.push({dictionary_id:d.id,dictionary_version:d.version,rule_id:r.id??r.value,field:f});
      }
    }
    if(!hits.length)return;
    const settings=await readSettings(this.store,data.country);
    const now=new Date().toISOString();const common={owner:data.owner,country:data.country,version:1,created_at:now};
    const episode=(await this.store.all('moderation_episode',data.country)).find(e=>e.content_id===data.id&&e.content_version===data.version);
    if(episode)return;
    const caseId=randomUUID();
    await this.store.put({...common,id:caseId,kind:'case',target_id:data.id,target_type:data.kind,status:'new',reason_code:'dictionary_match',subject_user_id:data.owner});
    await this.store.put({...common,id:randomUUID(),kind:'moderation_episode',content_id:data.id,content_version:data.version,case_id:caseId,matches:hits});
    await this.store.put({...common,id:randomUUID(),kind:'auto_hold',user_id:data.owner,case_id:caseId,status:'active',expires_at:new Date(Date.now()+settings.auto_hold_minutes*60000).toISOString()});
    if(data.kind==='user')data.status='restricted';else {const owner=await this.store.get(data.owner);if(owner)await this.store.put({...owner,status:'restricted',version:owner.version+1});}
    data.moderation_status='quarantined';data.case_id=caseId;
    if(['order','contractor','portfolio'].includes(data.kind))data.status='pending_moderation';
    if(data.kind==='message')data.delivery_state='quarantined';
  }
}
