import {randomUUID,createHash} from 'node:crypto';
import {HttpException} from '@nestjs/common';
import {Store,RecordData} from './store';
import {isStaffOwner} from './staff-access';
import {currentLegalDocuments} from './legal-documents';
const start='[Реквизиты оператора JOBA]',end='[/Реквизиты оператора JOBA]';
const fail=(field:string,message:string,status=422):never=>{throw new HttpException({error:{code:status===409?'STATE_CONFLICT':status===403?'FORBIDDEN':'VALIDATION_ERROR',message,details:{field},retryable:false}},status);};
export function operatorText(content:string,p:any){
 const block=`${start}\nОператор: ${p.name}\nБИН/ИИН: ${p.tax_id}\nАдрес: ${p.address}\nEmail для обращений и персональных данных: ${p.email}\nКонтактный телефон: ${p.phone||'Обращения по email и через поддержку'}\n${end}`;
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
 const now=new Date().toISOString(),profile={...old,id:old?.id??randomUUID(),kind:'public_operator_profile',owner:a.id,country:'KZ',created_at:old?.created_at??now,version:(old?.version??0)+1,status:'published',...fields,updated_at:now};
 await store.put(profile);
 let updated=0;
 for(const country of ['KZ','RU','BY','KG'])for(const d of currentLegalDocuments(await store.all('legal_document',country),country,'ru')){
  const content=operatorText(d.content,fields);if(content===d.content)continue;
  await store.put({id:randomUUID(),kind:'legal_revision',country,owner:a.id,version:1,created_at:now,source_id:d.id,source_version:d.version,content:d.content,hash:d.hash,change_kind:'operator_contacts_only'});
  await store.put({...d,content,hash:createHash('sha256').update(content).digest('hex'),version:d.version+1,operator_contacts_only:true,operator_contact_previous_hashes:[...new Set([...(d.operator_contact_previous_hashes??[]),d.hash])],operator_profile_version:profile.version,operator_contact_updated_at:now});updated++;
 }
 await store.put({id:randomUUID(),kind:'audit',owner:a.id,country:'KZ',created_at:now,version:1,actor_id:a.id,action:'public_operator.updated',target_id:profile.id,reason:'Публикация реквизитов владельцем; правила услуг и обработки данных не изменены',profile_version:profile.version,legal_documents_updated:updated});
 return {...profile,legal_documents_updated:updated};
}
