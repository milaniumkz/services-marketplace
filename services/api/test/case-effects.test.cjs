const {test}=require('node:test');
const assert=require('node:assert/strict');
const {randomUUID}=require('node:crypto');
const {Store}=require('../dist/store');
const {Marketplace}=require('../dist/marketplace');
const {freezeTarget}=require('../dist/case-evidence');
async function scenario(run){
 const api=new Marketplace(new Store('memory://'));await api.initialize();
 try{
  const reg=phone=>api.handle('POST','/auth/register',{country:'KZ',phone,password:'Isolated case resolution fixture!'},undefined,undefined,{},phone);
  const user=await reg('+77000000311'),moderator=await reg('+77000000312'),senior=await reg('+77000000313');
  for(const [session,permissions]of [[moderator,['moderator']],[senior,['moderator','senior_moderator']]]){
   const account=await api.store.get(session.user.id);await api.store.put({...account,staff_permissions:permissions});await api.store.db.query('UPDATE tokens SET mfa_verified=true WHERE user_id=$1',[account.id]);
  }
  const call=(session,method,path,body={},query={})=>api.handle(method,path,body,'Bearer '+session.access_token,randomUUID(),query);
  const put=(kind,data={},owner=user.user.id)=>api.store.put({id:randomUUID(),kind,owner,country:'KZ',version:1,created_at:new Date().toISOString(),...data});
  const decision=async(session,incident,value,path='resolve')=>{
   const context=await call(session,'GET','/admin/cases/'+incident.id);
   return call(session,'POST','/admin/cases/'+incident.id+'/'+path,{expected_version:context.version,expected_target_version:context.target_context?.version,decision:value,reason:'Основание проверенного решения по материалу'});
  };
  await run({api,user,moderator,senior,call,put,decision});
 }finally{await api.store.close();}
}
test('case false positive restores the frozen draft, preserves published content and releases only its incident hold',()=>scenario(async({api,user,moderator,call,put,decision})=>{
 await put('dictionary',{status:'published',payload:{rules:[{type:'exact_word',value:'badword'}]}});
 const profile=await put('contractor',{status:'published',title:'Опубликованная работа',description:'Описание опубликованного профиля'});
 await api.store.put({...profile,version:2,draft:{title:'badword черновик',description:'Исправляемый материал',status:'draft'}});
 const incident=(await api.store.all('case','KZ'))[0],stored=await api.store.get(profile.id);
 assert.equal(stored.status,'published');assert.equal(stored.draft.status,'pending_moderation');assert.equal(incident.target_scope,'draft');
 const publicCase=await call(user,'GET','/cases/'+incident.id);assert.equal(publicCase.target_snapshot,undefined);assert.equal(publicCase.target_content_hash,undefined);
 const result=await decision(moderator,incident,'no_violation');assert.equal(result.effects.target_action,'restored');
 const restored=await api.store.get(profile.id);assert.equal(restored.title,'Опубликованная работа');assert.equal(restored.status,'published');assert.equal(restored.draft.status,'draft');assert.equal(restored.draft.moderation_status,'reviewed');
 assert.equal((await api.store.get(user.user.id)).status,'active');assert.equal((await api.store.all('auto_hold','KZ'))[0].status,'released');
 await assert.rejects(()=>decision(moderator,result,'no_violation'),e=>e.getResponse().error.code==='STATE_CONFLICT');
}));
test('content removal preserves active work and independent appeal restores its frozen material',()=>scenario(async({api,user,moderator,senior,call,put,decision})=>{
 await put('dictionary',{status:'published',payload:{rules:[{type:'exact_word',value:'badword'}]}});
 const order=await put('order',{status:'in_progress',executor_id:randomUUID(),title:'badword материал',description:'Материал существующей работы',revision:3});
 const incident=(await api.store.all('case','KZ'))[0];assert.equal((await api.store.get(order.id)).status,'in_progress');
 const removed=await decision(moderator,incident,'content_removed');assert.equal((await api.store.get(order.id)).status,'in_progress');assert.equal((await api.store.get(order.id)).moderation_status,'hidden');
 const appealed=await call(user,'POST','/cases/'+incident.id+'/appeals',{expected_version:removed.version,reason:'Прошу независимую проверку решения по материалу'});
 await assert.rejects(()=>decision(moderator,appealed,'overturned','appeal-decision'),e=>e.getStatus()===403);
 await decision(senior,appealed,'overturned','appeal-decision');assert.equal((await api.store.get(order.id)).moderation_status,'reviewed');assert.equal((await api.store.get(order.id)).title,'badword материал');assert.equal((await api.store.get(order.id)).status,'in_progress');
 assert.equal((await api.store.all('case','KZ')).length,1);assert.equal((await api.store.all('blacklist','KZ')).length,0);
}));
test('stale cases cannot remove a newer version, and clearing one hold never overrides another incident',()=>scenario(async({api,user,moderator,put,decision})=>{
 const order=await put('order',{status:'open',title:'Исходная задача',description:'Описание исходной задачи',expires_at:new Date(Date.now()+86400000).toISOString()});
 const incident=await put('case',{target_type:'order',target_id:order.id,status:'new',subject_user_id:user.user.id,...freezeTarget(order)});
 await api.store.put({...order,title:'Другая версия задачи',version:2});
 await assert.rejects(()=>decision(moderator,incident,'content_removed'),e=>e.getResponse().error.code==='TARGET_CHANGED');
 const identity=await api.store.get(user.user.id);await api.store.put({...identity,status:'restricted'});
 await put('auto_hold',{user_id:user.user.id,case_id:incident.id,status:'active',expires_at:new Date(Date.now()+600000).toISOString()});
 await put('auto_hold',{user_id:user.user.id,case_id:randomUUID(),status:'active',expires_at:new Date(Date.now()+600000).toISOString()});
 const resolved=await decision(moderator,incident,'no_violation');assert.equal(resolved.effects.target_action,'superseded');assert.equal((await api.store.get(order.id)).title,'Другая версия задачи');assert.equal((await api.store.get(user.user.id)).status,'restricted');
 assert.equal((await api.store.all('auto_hold','KZ')).filter(h=>h.status==='active').length,1);
}));
test('private reports create an appealable subject notice without revealing the reporter or their evidence',()=>scenario(async({api,user,moderator,senior,call,put,decision})=>{
 const subject=await api.handle('POST','/auth/register',{country:'KZ',phone:'+77000000314',password:'Isolated subject fixture!'},undefined,undefined,{},'case-subject');
 const order=await put('order',{status:'open',title:'Материал субъекта',description:'Описание открытой задачи',expires_at:new Date(Date.now()+86400000).toISOString()},subject.user.id);
 const incident=await call(user,'POST','/cases',{target_type:'order',target_id:order.id,reason_code:'content',description:'Приватные подробности от заявителя'});
 const context=await call(moderator,'GET','/admin/cases/'+incident.id);
 await call(moderator,'POST','/admin/cases/'+incident.id+'/resolve',{expected_version:context.version,expected_target_version:context.target_context.version,decision:'content_removed',reason:'Проверены основания ограничения материала',public_reason:'Материал нарушает правила содержания. Вы можете обжаловать решение.'});
 const subjectCases=(await call(subject,'GET','/me/cases')).items;assert.equal(subjectCases.length,1);const notice=subjectCases[0];
 assert.equal(notice.owner,subject.user.id);assert.equal(notice.source_private_case_id,undefined);assert.equal(notice.target_snapshot,undefined);assert.ok(!JSON.stringify(notice).includes('Приватные подробности'));
 await assert.rejects(()=>call(subject,'GET','/cases/'+incident.id),e=>e.getStatus()===404);
 await call(subject,'POST','/cases/'+notice.id+'/appeals',{expected_version:notice.version,reason:'Прошу независимую проверку зафиксированной версии'});
 const appeal=(await call(senior,'GET','/admin/cases/'+notice.id));await decision(senior,appeal,'overturned','appeal-decision');
 assert.equal((await api.store.get(order.id)).moderation_status,'reviewed');assert.equal((await api.store.get(incident.id)).decision,'overturned');
 assert.ok((await call(subject,'GET','/me/notifications')).items.some(n=>n.type==='case.updated'&&n.target_id===notice.id));
}));
test('unavailable material releases its own hold without overriding a permanent sanction',()=>scenario(async({api,user,moderator,put,decision})=>{
 const incident=await put('case',{target_type:'order',target_id:randomUUID(),status:'new',subject_user_id:user.user.id});
 const owner=await api.store.get(user.user.id);await api.store.put({...owner,status:'restricted'});
 await put('auto_hold',{user_id:user.user.id,case_id:incident.id,status:'active',expires_at:new Date(Date.now()+600000).toISOString()});
 await put('blacklist',{user_id:user.user.id,case_id:randomUUID(),status:'active'});
 const resolved=await decision(moderator,incident,'no_violation');assert.equal(resolved.effects.target_action,'not_available');assert.equal(resolved.effects.restriction_released,false);
 assert.equal((await api.store.all('auto_hold','KZ'))[0].status,'released');assert.equal((await api.store.get(user.user.id)).status,'restricted');
}));
