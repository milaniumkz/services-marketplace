/** Keep stored verification snapshots intact; choose pages for new sessions by country. */
export function verificationDocumentTypes(policy:any,country:string):string[]{
 if(['RU','BY'].includes(country))return ['passport'];
 if(country==='KG')return ['id_card','passport'];
 return Array.isArray(policy?.document_types)?policy.document_types:[];
}
export function verificationPages(policy:any,type:string,country?:string):string[]{
 if(type==='passport'&&['RU','BY','KG'].includes(country??''))return ['Разворот паспорта с фотографией и личными данными','Селфи'];
 const supplied=Array.isArray(policy?.required_pages?.[type])?policy.required_pages[type].filter((x:any)=>typeof x==='string'&&!/селфи|selfie/i.test(x)):[];
 return [supplied[0]??'Лицевая сторона удостоверения',supplied[1]??'Обратная сторона удостоверения','Селфи'];
}
export function verificationPhotoLayout(record:any):{count:number;selfie:number}|null{
 const count=Array.isArray(record.required_pages)?record.required_pages.length:3;
 if(![2,3].includes(count)||record.selfie_index!==count-1)return null;
 if(count===2&&record.document_type!=='passport')return null;
 return {count,selfie:count-1};
}

/** Keep the existing policy/document link and old decision snapshots; archive
 * the obsolete wording and require fresh consent only for a new submission. */
export async function refreshVerificationWording(store:import('./store').Store){
 const {randomUUID,createHash}=await import('node:crypto');
 await store.db.exec('BEGIN');try{
  await store.db.query('SELECT pg_advisory_xact_lock(1752138231)');
  for(const country of ['RU','BY','KG']){
   const policies=(await store.all('verification_policy',country)).filter(p=>p.status==='effective');
   for(const id of new Set(policies.map(p=>p.payload.document_id))){
    const old=await store.get(id);if(!old||old.kind!=='legal_document'||old.type!=='verification_consent'||old.status!=='published')continue;
    const before='Я передаю фотографии лицевой и обратной стороны удостоверения личности и отдельное селфи';
    if(!String(old.content??'').includes(before))continue;
    const after=country==='KG'?'Я передаю фотографии лицевой и обратной стороны ID-карты либо разворота паспорта с фотографией и личными данными, а также отдельное селфи':'Я передаю фотографию разворота паспорта с фотографией и личными данными, а также отдельное селфи';
    const content=old.content.replace(before,after).replace('Удостоверение и исходные материалы','Документ личности и исходные материалы').replace('фотографии удостоверения для этого не используются','фотографии документа для этого не используются'),now=new Date().toISOString();
    await store.put({id:randomUUID(),kind:'legal_revision',owner:old.owner,country,created_at:now,version:1,source_id:old.id,source_version:old.version,content:old.content,hash:old.hash,change_kind:'regional_document_wording'});
    await store.put({...old,content,hash:createHash('sha256').update(content).digest('hex'),version:old.version+1,published_at:now,operator_contacts_only:false,operator_contact_previous_hashes:[]});
    await store.put({id:randomUUID(),kind:'audit',owner:old.owner,country,version:1,created_at:now,action:'verification.regional_document_wording_updated',target_id:old.id,reason:'Owner requested passports for Russia and Belarus, ID card or passport for Kyrgyzstan; completed approvals and stored photo layouts preserved'});
   }
  }
  await store.db.exec('COMMIT');
 }catch(e){await store.db.exec('ROLLBACK');throw e;}
}
