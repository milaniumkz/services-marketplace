import {randomUUID,createHash} from 'node:crypto';
import {HttpException} from '@nestjs/common';
import {Store,RecordData} from './store';
import {isStaffOwner} from './staff-access';
import {currentLegalDocuments} from './legal-documents';
import {operatorActivityText} from './operator-activity';
const start='[Реквизиты оператора JOBA]',end='[/Реквизиты оператора JOBA]';
const fail=(field:string,message:string,status=422):never=>{throw new HttpException({error:{code:status===409?'STATE_CONFLICT':status===403?'FORBIDDEN':'VALIDATION_ERROR',message,details:{field},retryable:false}},status);};
export function operatorText(content:string,p:any){
 const block=`${start}\nОператор: ${p.name}\nБИН/ИИН: ${p.tax_id}\nАдрес: ${p.address}\nEmail для обращений и персональных данных: ${p.email}\nКонтактный телефон: ${p.phone||'Обращения по email и через поддержку'}${operatorActivityText(p)}\n${end}`;
 let s=content.replace(/\n?\[Реквизиты оператора JOBA\][\s\S]*?\[\/Реквизиты оператора JOBA\]\n?/g,'\n');
 s=s.replace(/Реквизиты оператора: наименование _+; регистрационный номер _+; адрес _+; контактный email _+\. По поручению владельца реквизиты пока не заполнены и будут внесены через админ-панель\./g,'Реквизиты оператора приведены в конце документа.');
 const values:[RegExp,string][]=[[/^(Полное наименование[^:\n]*|Наименование оператора|Наименование собственника\/оператора[^:\n]*):[^\n]*$/gm,p.name],[/^(БИН\/ИИН):[^\n]*$/gm,p.tax_id],[/^(Юридический адрес|Почтовый адрес для обращений):[^\n]*$/gm,p.address],[/^(Email[^:\n]*):[^\n]*$/gm,p.email],[/^(Контактный телефон):[^\n]*$/gm,p.phone||'Обращения по email и через поддержку']];
 for(const [regex,value] of values)s=s.replace(regex,(_line,label)=>`${label}: ${value}`);
 s=s.replace(/Реквизиты оставлены пустыми по поручению владельца\.[^\n]*/g,'Актуальные реквизиты оператора опубликованы в этом документе. Публикация реквизитов не означает подключения банка или подтверждения юридической экспертизы.');
 s=s.replace(/Реквизиты оставлены пустыми по поручению владельца и должны быть заполнены\./g,'Актуальные реквизиты оператора опубликованы в этом документе.');
 s=s.replace(/Реквизиты временно не заполнены владельцем сервиса\.[^\n]*/g,'Актуальные реквизиты оператора опубликованы в этом документе.');
 s=s.replace(/^Режим обработки обращений:[^\n]*$/gm,'Режим обработки обращений: электронные обращения принимаются через форму поддержки и email.');
 return s.trim()+'\n\n'+block+'\n';
}
export async function adminOperatorProfile(store:Store,a:{id:string;user:RecordData;mfa:boolean},method:string,b:any){
 if(!isStaffOwner(a.user)||!a.mfa||a.user.status!=='active')fail('','Реквизитами оператора управляет владелец платформы.',403);
 if(method==='PUT')await store.db.query('SELECT pg_advisory_xact_lock(1752138231)');
 const old=(await store.all('public_operator_profile','KZ'))[0];
 if(method==='GET')return old??{version:0,status:'not_configured',name:'',tax_id:'',address:'',email:'',phone:''};
 if(method!=='PUT')fail('','Действие не поддерживается.');
 if(b.expected_version!==(old?.version??0))fail('expected_version','Реквизиты уже изменились. Обновите страницу.',409);
 const fields:any={};
 for(const [key,min,max,label] of [['name',3,200,'Наименование оператора'],['tax_id',12,12,'БИН/ИИН'],['address',5,400,'Адрес'],['email',5,254,'Email'],['phone',0,30,'Телефон']] as const){const value=typeof b[key]==='string'?b[key].trim():'';if(value.length<min||value.length>max||/[\r\n]/.test(value)||value.includes(start)||value.includes(end))fail(key,`Проверьте поле «${label}».`);fields[key]=value;}
 if(!/^\d{12}$/.test(fields.tax_id))fail('tax_id','БИН/ИИН должен содержать 12 цифр.');
 if(!/^[^\s<>@]+@[^\s<>@]+\.[^\s<>@]+$/.test(fields.email))fail('email','Укажите корректный рабочий email.');
 if(fields.phone&&!/^\+\d[\d ()-]{6,28}$/.test(fields.phone))fail('phone','Укажите телефон с кодом страны.');
 fields.oked_primary=b.oked_primary===undefined?(old?.oked_primary??''):typeof b.oked_primary==='string'?b.oked_primary.trim():'';
 if(b.oked_primary!==undefined&&typeof b.oked_primary!=='string'||fields.oked_primary&&!/^\d{5}$/.test(fields.oked_primary))fail('oked_primary','Основной ОКЭД должен содержать 5 цифр.');
 const additional=b.oked_additional===undefined?(old?.oked_additional??[]):typeof b.oked_additional==='string'?b.oked_additional.split(/[,;\s]+/).filter(Boolean):b.oked_additional;
 if(!Array.isArray(additional)||additional.length>10||additional.some((code:any)=>typeof code!=='string'||!/^\d{5}$/.test(code)))fail('oked_additional','Укажите дополнительные ОКЭД из 5 цифр через запятую, не более 10 кодов.');
 fields.oked_additional=[...new Set(additional)];
 if(fields.oked_additional.length&&!fields.oked_primary)fail('oked_primary','Сначала укажите основной ОКЭД.');
 if(fields.oked_additional.includes(fields.oked_primary))fail('oked_additional','Основной ОКЭД не нужно повторять в дополнительных.');
 fields.oked_status=b.oked_status??old?.oked_status??'updating';
 if(!['updating','registered'].includes(fields.oked_status))fail('oked_status','Выберите статус оформления ОКЭД.');
 return saveOperatorProfile(store,old,fields,a.id,'Публикация реквизитов владельцем; правила услуг и обработки данных не изменены');
}

async function saveOperatorProfile(store:Store,old:RecordData|undefined,fields:any,actor:string,reason:string){
 const now=new Date().toISOString(),profile={...old,id:old?.id??randomUUID(),kind:'public_operator_profile',owner:actor,country:'KZ',created_at:old?.created_at??now,version:(old?.version??0)+1,status:'published',...fields,updated_at:now};
 await store.put(profile);
 let updated=0;
 for(const country of ['KZ','RU','BY','KG']){
 const records=await store.all('legal_document',country),documents=new Map<string,RecordData>();
 for(const locale of new Set(['ru',...records.filter(d=>d.status==='published').map(d=>d.locale)]))for(const d of currentLegalDocuments(records,country,locale))documents.set(d.id,d);
 for(const d of documents.values()){
  const content=operatorText(d.content,fields);if(content===d.content)continue;
  await store.put({id:randomUUID(),kind:'legal_revision',country,owner:actor,version:1,created_at:now,source_id:d.id,source_version:d.version,content:d.content,hash:d.hash,change_kind:'operator_contacts_only'});
  await store.put({...d,content,hash:createHash('sha256').update(content).digest('hex'),version:d.version+1,operator_contacts_only:true,operator_contact_previous_hashes:[...new Set([...(d.operator_contact_previous_hashes??[]),d.hash])],operator_profile_version:profile.version,operator_contact_updated_at:now});updated++;
 }}
 await store.put({id:randomUUID(),kind:'audit',owner:actor,country:'KZ',created_at:now,version:1,actor_id:actor,action:'public_operator.updated',target_id:profile.id,reason,profile_version:profile.version,legal_documents_updated:updated});
 return {...profile,legal_documents_updated:updated};
}

/** One-time owner instruction of 2026-11-13; registration is still being changed. */
export async function publishOwnerActivityCodes(store:Store){
 await store.db.exec('BEGIN');
 try{
  await store.db.query('SELECT pg_advisory_xact_lock(1752138231)');
  const model='joba-oked-2026-11-13';
  if((await store.all('operator_activity_migration','KZ')).some(x=>x.model===model)){await store.db.exec('COMMIT');return;}
  const old=(await store.all('public_operator_profile','KZ'))[0];
  if(!old||old.status!=='published'){await store.db.exec('COMMIT');return;}
  if(!old.oked_primary)await saveOperatorProfile(store,old,{name:old.name,tax_id:old.tax_id,address:old.address,email:old.email,phone:old.phone,oked_primary:'63120',oked_additional:['63115'],oked_status:'updating'},old.owner,'Поручение владельца от 13.11.2026: опубликовать ОКЭД 63120 и 63115; изменение регистрационных сведений оформляется');
  await store.put({id:randomUUID(),kind:'operator_activity_migration',owner:old.owner,country:'KZ',version:1,created_at:new Date().toISOString(),model});
  await store.db.exec('COMMIT');
 }catch(error){await store.db.exec('ROLLBACK');throw error;}
}
