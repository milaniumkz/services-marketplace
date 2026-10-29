import {hash} from '@node-rs/argon2';
import {HttpException} from '@nestjs/common';
import {randomUUID} from 'node:crypto';
import {Store,RecordData} from './store';
import {staffOperations} from './staff-operation-catalog';
export const legacyStaffPermissions=['administrator','content','moderator','senior_moderator','security','support','support_internal','phone_view','billing','campaign','moderator_manager','verification_reviewer','identity_view','promotion','brand_owner','release','auditor','privacy','bulk_restrict'];
export const isStaffOwner=(u:RecordData)=>u.staff_access_mode!=='managed'&&u.staff_permissions?.includes('platform_owner')===true;
const commands=['assign','resolve','wait_user','wait_support','reopen'];
const extra=[...commands.map(command=>({id:'support.command.'+command,block:'support-threads',label:({assign:'Назначать обращение',resolve:'Закрывать обращение',wait_user:'Ожидать ответа пользователя',wait_support:'Возвращать в поддержку',reopen:'Повторно открывать обращение'} as Record<string,string>)[command]})),{id:'sensitive.identity',block:'verifications',label:'Просмотр исходников документов'},{id:'sensitive.phone',block:'users',label:'Просмотр полного телефона пользователя'},{id:'files.moderator',block:'files',label:'Материалы дел — просмотр файлов с основанием'},{id:'files.content',block:'files',label:'Файлы контента — служебный просмотр'},{id:'files.support',block:'files',label:'Файлы обращений поддержки — просмотр'},{id:'files.upload',block:'files',label:'Загрузка и статус собственных служебных файлов'}];
const ids=new Set<string>([...staffOperations.map(x=>x.id),...extra.map(x=>x.id)]);
// A selected action/detail needs its own section list to remain reachable in the UI.
// This adds only basic reads for the same resource; sensitive reads stay explicit.
export function completeStaffGrants(input:string[]){
 const grants=new Set(input);
 for(const id of input){const op=staffOperations.find(o=>o.id===id);if(!op)continue;
  const parts=op.path.split('/');
  for(let depth=3;depth<=parts.length;depth++){const read='GET '+parts.slice(0,depth).join('/');if(ids.has(read))grants.add(read);}
 }
 return [...grants];
}
const sections:Record<string,string>={categories:'content','category-tree':'content','banner-campaigns':'campaign','account-restriction-jobs':'bulk_restrict','security-events':'security','legal-holds':'privacy','push-test-accounts':'campaign',languages:'content',bulk:'content',revenue:'billing',audit:'auditor','support-threads':'support','recovery-threads':'support',verifications:'verification_reviewer',portfolio:'content',contractors:'content','privacy-requests':'privacy',blacklist:'senior_moderator','cases':'moderator','brand-icons':'content'};
function permission(op:typeof staffOperations[number]):string{if(op.block==='brand-icons')return op.path.endsWith('/approve')?'brand_owner':op.path.endsWith('/generate')?'release':'content';if(['price-versions','monetization-configs','monetization-summary','payment-transactions','refund-requests','promotions'].includes(op.block))return 'billing';if(['referral-campaigns','push-campaigns'].includes(op.block))return 'campaign';if(op.block==='moderation-dictionaries')return 'moderator_manager';if(op.block==='ranking-configs')return 'content';if(['boost-grants','boost-reports','placement-policies'].includes(op.block))return 'promotion';return sections[op.block]??'administrator';}
export async function resolveStaffUser(store:Store,u:RecordData):Promise<RecordData>{
 if(isStaffOwner(u))return {...u,staff_permissions:[...legacyStaffPermissions,'platform_owner']};
 if(u.staff_access_mode!=='managed')return u;
 const roleIds=Array.isArray(u.staff_role_ids)?u.staff_role_ids:[];
 const rows=await store.db.query<{data:RecordData}>("SELECT data FROM records WHERE kind='staff_role' AND country=$1 AND id::text=ANY($2::text[]) AND data->>'status'='active'",[u.country,roleIds]);
 const grants=[...new Set<string>(rows.rows.flatMap(x=>completeStaffGrants(x.data.grants??[])))].filter(id=>ids.has(id));const permissions=new Set<string>(['dynamic_staff']);
 for(const op of staffOperations)if(grants.includes(op.id)){const p=permission(op);if(p!=='administrator')permissions.add(p);if(op.path.endsWith('/internal-notes'))permissions.add('support_internal');if(op.path.endsWith('/security-events'))permissions.add('security');if(op.path.endsWith('/blacklist'))permissions.add('senior_moderator');if(op.path.includes('phone'))permissions.add('phone_view');if(op.path.endsWith('/appeal-decision'))permissions.add('senior_moderator');}
 if(grants.includes('sensitive.identity'))permissions.add('identity_view');if(grants.includes('sensitive.phone'))permissions.add('phone_view');for(const p of ['moderator','content','support'])if(grants.includes('files.'+p))permissions.add(p);
 return {...u,staff_permissions:[...permissions],staff_grants:grants,staff_role_names:rows.rows.map(x=>x.data.title)};
}
function deny(message='Действие недоступно вашей роли'):never{throw new HttpException({error:{code:'FORBIDDEN',message,retryable:false}},403);}
export function assertStaffOperation(u:RecordData,mfa:boolean,method:string,path:string,b:any={},q:any={}){
 if(u.staff_access_mode!=='managed')return;
 const grants:string[]=u.staff_grants??[];
 if(path.startsWith('/admin/')){
  if(!mfa||u.status!=='active')deny();
  if(path==='/admin/access/me'&&method==='GET')return;
  if(path==='/admin/country-capabilities'&&method==='GET'&&grants.length)return;
  const match=staffOperations.filter(op=>op.method===method&&new RegExp('^'+op.path.replace(/\{[^}]+\}/g,'[^/]+')+'$').test(path)).sort((a,b)=>(a.path.match(/\{/g)?.length??0)-(b.path.match(/\{/g)?.length??0))[0];
  if(!match||!grants.includes(match.id))deny();
  if(match.id==='POST /admin/support-threads/{id}/commands'&&!grants.includes('support.command.'+b.command))deny();
  if(q.include_phone==='true'&&!grants.includes('sensitive.phone'))deny('Нет права просмотра полного телефона');
  if(q.include_documents==='true'&&!grants.includes('sensitive.identity'))deny('Нет права просмотра исходников документов');
 }else if(path.startsWith('/uploads')){
  if(!mfa||u.status!=='active')deny();if(method==='GET'&&path.endsWith('/metadata')&&grants.includes('files.upload'))return;const read=method==='GET'||path.endsWith('/download-url');if(read?!grants.some(g=>['files.moderator','files.content','files.support','sensitive.identity'].includes(g)):!grants.includes('files.upload'))deny();
 }
}
function fail(code:string,message:string,status=422):never{throw new HttpException({error:{code,message,retryable:false}},status);};
export async function staffAccess(store:Store,a:{id:string,country:string,user:RecordData,mfa:boolean},method:string,path:string,b:any){
 if(!path.startsWith('/admin/access/'))return;
 if(!a.mfa||a.user.status!=='active'||!a.user.staff_permissions?.length)deny('Нужен служебный вход');
 if(path==='/admin/access/me'&&method==='GET')return {is_owner:isStaffOwner(a.user),managed:a.user.staff_access_mode==='managed',grants:a.user.staff_grants??[],role_names:a.user.staff_role_names??[],permissions:a.user.staff_permissions};
 if(!isStaffOwner(a.user))deny('Управление ролями доступно только владельцу');
 if(method!=='GET')await store.db.query('SELECT pg_advisory_xact_lock(hashtextextended($1,0))',['staff-access:'+a.country]);
 const audit=async(action:string,target:string,details:any={})=>{if(typeof b.reason!=='string'||b.reason.trim().length<10||b.reason.length>1000)fail('VALIDATION_ERROR','Укажите основание изменения');await store.put({id:randomUUID(),kind:'audit',owner:a.id,country:a.country,created_at:new Date().toISOString(),version:1,actor_id:a.id,action,target_id:target,reason:b.reason.trim(),...details});};
 if(path==='/admin/access/catalog'&&method==='GET')return {items:[...staffOperations,...extra]};
 if(path==='/admin/access/roles'&&method==='GET')return {items:(await store.all('staff_role',a.country)).filter(r=>r.status!=='deleted').map(r=>({...r,grants:completeStaffGrants(r.grants??[])}))};
 if(path==='/admin/access/staff'&&method==='GET')return {items:await Promise.all((await store.all('user',a.country)).filter(u=>u.staff_permissions?.length&&u.status!=='deleted').map(async u=>{const effective=await resolveStaffUser(store,u);return {id:u.id,display_name:u.display_name,identifier:u.phone,status:u.status,version:u.version,is_owner:isStaffOwner(u),managed:u.staff_access_mode==='managed',role_ids:u.staff_role_ids??[],role_names:effective.staff_role_names??[],effective_grant_count:effective.staff_grants?.length??0};}))};
 if(path==='/admin/access/staff'&&method==='POST'){
  const name=typeof b.display_name==='string'?b.display_name.trim():'',login=typeof b.login==='string'?b.login.trim().toLowerCase():'';
  if(name.length<2||name.length>120)fail('VALIDATION_ERROR','Имя сотрудника должно содержать от 2 до 120 символов');
  if(!/^[a-z][a-z0-9._@+-]{2,63}$/.test(login))fail('VALIDATION_ERROR','Логин: от 3 до 64 символов, первая — строчная латинская буква. Разрешены строчные буквы, цифры и . _ @ + -');
  if(typeof b.password!=='string'||b.password.length<6||b.password.length>128)fail('VALIDATION_ERROR','Пароль сотрудника должен содержать от 6 до 128 символов');
  if(!Array.isArray(b.role_ids)||!b.role_ids.length||b.role_ids.length>20||b.role_ids.some((id:any)=>typeof id!=='string'))fail('VALIDATION_ERROR','Выберите хотя бы одну роль сотрудника');
  const roles=await store.all('staff_role',a.country);if(b.role_ids.some((id:string)=>!roles.some(r=>r.id===id&&r.status==='active')))fail('VALIDATION_ERROR','Выберите действующие роли этой страны');
  const exists=(await store.db.query('SELECT user_id FROM credentials WHERE country=$1 AND lower(phone)=lower($2)',[a.country,login])).rows.length;
  if(exists)fail('STAFF_LOGIN_TAKEN','Этот логин уже используется. Укажите другой.',409);
  const id=randomUUID(),roleIds=[...new Set(b.role_ids)],employee={id,owner:id,kind:'user',country:a.country,created_at:new Date().toISOString(),version:1,status:'active',display_name:name,phone:login,roles:[],locale:'ru',staff_permissions:['dynamic_staff'],staff_access_mode:'managed',staff_auth_mode:'password',staff_role_ids:roleIds};
  await store.put(employee);
  await store.db.query('INSERT INTO credentials(country,phone,user_id,password_hash) VALUES($1,$2,$3,$4)',[a.country,login,id,await hash(b.password)]);
  await audit('staff.account_created',id,{after:{display_name:name,login,role_ids:roleIds}});
  return {id,display_name:name,identifier:login,country:a.country,status:'active',version:1,is_owner:false,managed:true,role_ids:roleIds};
 }
 const employeePath=path.match(/^\/admin\/access\/staff\/([^/]+)(?:\/(block|unblock))?$/);
 if(employeePath&&(employeePath[2]?method==='POST':['PATCH','DELETE'].includes(method))){
  const target=await store.get(employeePath[1]);if(!target||target.kind!=='user'||target.country!==a.country||!target.staff_permissions?.length||target.status==='deleted')fail('NOT_FOUND','Сотрудник не найден',404);
  if(isStaffOwner(target))deny('Учётную запись владельца нельзя изменять, блокировать или удалять здесь');
  if(b.expected_version!==target.version)fail('STATE_CONFLICT','Данные сотрудника изменились. Обновите список',409);
  let next:RecordData={...target,version:target.version+1},passwordChanged=false,loginChanged=false;
  if(method==='PATCH'){
   const name=b.display_name===undefined?target.display_name:typeof b.display_name==='string'?b.display_name.trim():'';
   const login=b.login===undefined?target.phone:typeof b.login==='string'?b.login.trim().toLowerCase():'';
   if(typeof name!=='string'||name.length<2||name.length>120)fail('VALIDATION_ERROR','Имя сотрудника должно содержать от 2 до 120 символов');
   if(!/^[a-z][a-z0-9._@+-]{2,63}$/.test(login))fail('VALIDATION_ERROR','Логин: от 3 до 64 латинских букв, цифр и символов . _ @ + -');
   if((await store.db.query('SELECT user_id FROM credentials WHERE country=$1 AND lower(phone)=lower($2) AND user_id<>$3',[a.country,login,target.id])).rows.length)fail('STAFF_LOGIN_TAKEN','Этот логин уже используется',409);
   if(b.password!==undefined&&(typeof b.password!=='string'||b.password.length<6||b.password.length>128))fail('VALIDATION_ERROR','Пароль должен содержать от 6 до 128 символов');
   if(b.role_ids!==undefined){
    const roles=await store.all('staff_role',a.country);if(!Array.isArray(b.role_ids)||b.role_ids.length>20||b.role_ids.some((id:any)=>typeof id!=='string'||!roles.some(r=>r.id===id&&(r.status==='active'||['blocked','archived'].includes(r.status)&&(target.staff_role_ids??[]).includes(id)))))fail('VALIDATION_ERROR','Выберите действующие роли этой страны');
    next.staff_role_ids=[...new Set(b.role_ids)];next.staff_access_mode='managed';next.staff_permissions=['dynamic_staff'];
   }
   loginChanged=login!==target.phone;passwordChanged=b.password!==undefined;
   next.display_name=name;next.phone=login;next.staff_auth_mode='password';
   await store.db.query('UPDATE credentials SET phone=$1 WHERE user_id=$2 AND country=$3',[login,target.id,a.country]);
   if(passwordChanged)await store.db.query('UPDATE credentials SET password_hash=$1 WHERE user_id=$2 AND country=$3',[await hash(b.password),target.id,a.country]);
  }else if(method==='DELETE'){
   next={...next,status:'deleted',staff_permissions:[],staff_role_ids:[],deleted_at:new Date().toISOString()};
   await store.db.query('DELETE FROM credentials WHERE user_id=$1 AND country=$2',[target.id,a.country]);
  }else{next.status=employeePath[2]==='block'?'blocked':'active';next.admin_blocked=employeePath[2]==='block';}
  if(method==='DELETE'||employeePath[2]==='block'||loginChanged||passwordChanged)await store.db.query('UPDATE tokens SET revoked=true WHERE user_id=$1 AND country=$2',[target.id,a.country]);
  await audit(method==='PATCH'?'staff.account_updated':method==='DELETE'?'staff.account_deleted':'staff.account_'+employeePath[2],target.id,{before:{display_name:target.display_name,login:target.phone,status:target.status,role_ids:target.staff_role_ids??[]},after:{display_name:next.display_name,login:next.phone,status:next.status,role_ids:next.staff_role_ids??[]},password_changed:passwordChanged});
  await store.put(next);return {id:next.id,status:next.status,version:next.version,deleted:method==='DELETE'};
 }
 const roleAction=path.match(/^\/admin\/access\/roles\/([^/]+)(?:\/(block|unblock))?$/);
 if(roleAction&&(roleAction[2]?method==='POST':method==='DELETE')){
  const role=await store.get(roleAction[1]);if(!role||role.kind!=='staff_role'||role.country!==a.country||role.status==='deleted')fail('NOT_FOUND','Роль не найдена',404);
  if(b.expected_version!==role.version)fail('STATE_CONFLICT','Роль изменена. Обновите список',409);
  const status=method==='DELETE'?'deleted':roleAction[2]==='block'?'blocked':'active';
  if(status==='active'&&(await store.all('staff_role',a.country)).some(r=>r.id!==role.id&&r.status==='active'&&r.title.toLocaleLowerCase()===role.title.toLocaleLowerCase()))fail('ROLE_NAME_TAKEN','Действующая роль с таким названием уже существует',409);
  if(status==='deleted')for(const user of await store.all('user',a.country))if(user.staff_role_ids?.includes(role.id))await store.put({...user,staff_role_ids:user.staff_role_ids.filter((id:string)=>id!==role.id),version:user.version+1});
  await audit(status==='deleted'?'staff.role_deleted':'staff.role_'+roleAction[2],role.id,{before:{status:role.status,grants:role.grants},after:{status}});
  return store.put({...role,status,version:role.version+1});
 }
 const rolePath=path.match(/^\/admin\/access\/roles\/([^/]+)(?:\/(archive))?$/),assignment=path.match(/^\/admin\/access\/staff\/([^/]+)\/roles$/);
 if(path==='/admin/access/roles'&&method==='POST'||rolePath&&['PATCH','POST'].includes(method)){
  const old=rolePath?await store.get(rolePath[1]):undefined;if(rolePath&&(!old||old.kind!=='staff_role'||old.country!==a.country||old.status==='deleted'))fail('NOT_FOUND','Роль не найдена',404);
  if(old&&b.expected_version!==old.version)fail('STATE_CONFLICT','Роль изменена. Обновите данные',409);
  if(rolePath?.[2]==='archive'){if(method!=='POST'||old!.status!=='active')fail('STATE_CONFLICT','Роль уже архивирована',409);await audit('staff.role_archived',old!.id,{before:{grants:old!.grants,status:old!.status},after:{status:'archived'}});return store.put({...old!,status:'archived',version:old!.version+1});}
  if(method!==(old?'PATCH':'POST')||old?.status==='archived')fail('STATE_CONFLICT','Создайте новую активную роль',409);
  if(typeof b.title!=='string'||b.title.trim().length<2||b.title.trim().length>80||!Array.isArray(b.grants)||!b.grants.length||b.grants.length>500||b.grants.some((g:any)=>typeof g!=='string'||!ids.has(g)))fail('VALIDATION_ERROR','Проверьте название и выбранные функции');
  const duplicate=(await store.all('staff_role',a.country)).some(r=>r.id!==old?.id&&r.status==='active'&&r.title.toLocaleLowerCase()===b.title.trim().toLocaleLowerCase());if(duplicate)fail('ROLE_NAME_TAKEN','Название уже используется',409);
  const r={...(old??{id:randomUUID(),kind:'staff_role',owner:a.id,country:a.country,created_at:new Date().toISOString(),version:0}),title:b.title.trim(),grants:completeStaffGrants([...new Set([...b.grants,...(b.grants.some((g:string)=>g.startsWith('support.command.'))?['POST /admin/support-threads/{id}/commands']:[])])]),status:old?.status??'active',version:(old?.version??0)+1};await audit(old?'staff.role_updated':'staff.role_created',r.id,{before:{title:old?.title,grants:old?.grants??[]},after:{title:r.title,grants:r.grants}});return store.put(r);
 }
 if(assignment&&method==='PUT'){
  const target=await store.get(assignment[1]);if(!target||target.kind!=='user'||target.country!==a.country||!target.staff_permissions?.length)fail('NOT_FOUND','Служебная учётная запись не найдена',404);
   if(isStaffOwner(target!))deny('Права владельца изменяются только отдельной процедурой');if(b.expected_version!==target!.version)fail('STATE_CONFLICT','Сотрудник изменён. Обновите данные',409);
  if(!Array.isArray(b.role_ids)||b.role_ids.length>20||b.role_ids.some((id:any)=>typeof id!=='string'))fail('VALIDATION_ERROR','Проверьте назначенные роли');
  const roles=await store.all('staff_role',a.country);if(b.role_ids.some((id:string)=>!roles.some(r=>r.id===id&&r.status==='active')))fail('VALIDATION_ERROR','Выберите действующие роли этой страны');
  await audit('staff.roles_assigned',target!.id,{before:{role_ids:target!.staff_role_ids??[],legacy_permissions:target!.staff_permissions},after:{role_ids:[...new Set(b.role_ids)]}});await store.put({...target!,staff_permissions:['dynamic_staff'],staff_access_mode:'managed',staff_role_ids:[...new Set(b.role_ids)],version:target!.version+1});
  return {id:target!.id,role_ids:[...new Set(b.role_ids)],version:target!.version+1};
 }
 fail('NOT_FOUND','Действие не найдено',404);
}
