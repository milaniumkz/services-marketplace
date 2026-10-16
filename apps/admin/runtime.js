import {placementWorkspace} from './placement-workspace.js';
import {rankingWorkspace} from './ranking-workspace.js';
import {referralWorkspace} from './referral-workspace.js';
import {categoryWorkspace} from './category-workspace.js';
import {priceWorkspace} from './price-workspace.js';
import {documentPolicyWorkspace} from './document-policy-workspace.js';
import {bannerWorkspace} from './banner-workspace.js';
import {promotionWorkspace} from './promotion-workspace.js';
import {pushRoutes,pushWorkspace} from './push-workspace.js';
import {scenarioRoutes,scenarioWorkspace} from './scenario-workspace.js';
import {brandingBuildWorkspace} from './branding-build-workspace.js';
import {boostWorkspace} from './boost-workspace.js';
import {userWorkspace,userRoutes} from './user-workspace.js';
import {brandingWorkspace} from './branding-workspace.js';
import {countryWorkspace} from './country-workspace.js';
import {wireLiveShell,clearStaffDialogs} from './live-shell.js';
import {systemWorkspace} from './system-workspace.js';
import {monetizationWorkspace} from './monetization-workspace.js';
import {operationsWorkspace} from './operations-workspace.js';
import {reviewWorkspace} from './review-workspace.js';
import './design.js';
import {staffApi} from './api.js';
const {routes,render,card,tablecard,field,note,metric,badge}=window.JOBA_ADMIN;
const designMode=new URLSearchParams(location.search).has('design');
const esc=v=>String(v??'').replace(/[&<>"']/g,c=>({'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;',"'":'&#39;'}[c]));
let session,loginDraft,cache={},error='',generation=0,disposeWorkspace;
const privateWorkspaces=new Set([...pushRoutes,...scenarioRoutes,...userRoutes,'placements','ranking','referrals','referral-preview','categories','prices','pricing','verificationPolicies','retention','campaigns','banner-detail','branding-build','boosts','boost-grant','analytics','dashboard','security','jobs','scheduled','job-detail','branding','countries','monetization','settings','legal']);
const cursors={},filters={},configRoutes=new Set(['prices','pricing','monetization','push','referrals','dictionaries','dictionary','categories','ranking','placements','verificationPolicies','retention']);
const sections={users:['users','Аккаунты'],orders:['orders','Заказы'],support:['support-threads','Поддержка'],'support-recovery':['recovery-threads','Восстановление доступа'],moderation:['cases','Дела'],portfolio:['portfolio','Портфолио'],contractors:['contractors','Профили исполнителей'],privacy:['privacy-requests','Запросы приватности'],blacklist:['blacklist','Черный список'],audit:['audit','Аудит'],prices:['price-versions','Цены'],monetization:['monetization-configs','Монетизация'],push:['push-campaigns','Рассылки'],referrals:['referral-campaigns','Реферальные кампании'],dictionaries:['moderation-dictionaries','Словари'],categories:['categories','Категории'],ranking:['ranking-configs','Рейтинг'],pricing:['price-versions','Каталог цен'],campaigns:['banner-campaigns','Кампании'],dictionary:['moderation-dictionaries','Запрещенные слова'],verification:['verifications','Проверка документов'],top100:['boost-reports','Топ и продвижение'],placements:['placement-policies','Размещения'],verificationPolicies:['verification-policies','Правила проверки'],retention:['retention-policies','Сроки хранения']};
function clearStaffState(){
 session=undefined;cache={};clearStaffDialogs();
 for(const route of Object.keys(routes))if(route.includes('-live/')||privateWorkspaces.has(route))delete routes[route];
}
const api=staffApi({getSession:()=>session,saveSession:value=>{session=value;}});
const namedField=(label,name,type='text')=>field(label,'',type).replace('<input ','<input name="'+name+'" ').replace('<textarea ','<textarea name="'+name+'" ');
if(!designMode) {
  routes.login.body=()=>`<div class="login"><section class="loginbrand"><div class="brand"><img src="/assets/joba-logo-original.jpeg" alt="JOBA"><div><b>JOBA</b><small>CONTROL CENTER</small></div></div><div><div class="eyebrow" style="color:#92B5F5;margin-bottom:18px">СЕРВИС НАЧИНАЕТСЯ С ДОВЕРИЯ</div><h1>Все инструменты.<br>Одна рабочая среда.</h1><p>Операции, поддержка и безопасность маркетплейса услуг JOBA.</p></div><div class="tiny" style="color:#92A9CE">Только для уполномоченных сотрудников</div></section><section class="loginform"><span class="demobadge">СЛУЖЕБНЫЙ ВХОД</span><h1 style="margin-top:18px">Вход в панель</h1><p class="muted" style="margin-top:10px">Используйте служебную учетную запись. Доступ определяется ролью и страной.</p><form id="staff-login" class="stack">${namedField('Рабочий идентификатор','phone')}${namedField('Пароль','password','password')}<div class="formfield"><label for="staff-country">Страна</label><select id="staff-country" name="country"><option>KZ</option><option>KG</option><option>RU</option><option>BY</option></select></div><button class="primary">Продолжить</button></form>${error?note(esc(error),'danger'):''}<div class="notice-slim" style="margin-top:20px">После ввода пароля потребуется второй фактор. Это отдельный вход, не пользовательский аккаунт JOBA.</div><p class="helptext" style="margin-top:32px">Возникли проблемы со входом? Обратитесь к ответственному за доступ в вашей организации.</p></section></div>`;
  routes.mfa.body=()=>`<div style="max-width:440px;margin:65px auto">${card('Подтвердите доступ',`${note('Служебная сессия · '+esc(loginDraft?.phone)+' · страна '+esc(loginDraft?.country),'','shield')}<form id="staff-mfa" class="stack">${namedField('Код второго фактора','mfa_code')}<button class="primary">Продолжить</button></form>${error?note(esc(error),'danger'):''}<p class="helptext" style="margin-top:20px"><a href="#login">Вернуться ко входу</a></p>`)}</div>`;
  routes.dashboard.body=()=>cache.dashboard?`<div class="grid cols4">${metric('Пользователи',cache.dashboard.users,'','В текущем регионе')}${metric('Заказы',cache.dashboard.orders,'','Все состояния')}${metric('Открытые обращения',cache.dashboard.support,'','Требуют внимания')}${metric('Страна',cache.dashboard.country,'','Служебная область')}</div>${note('Коммерческие launch gates не пройдены. Оплата и рекламные награды отключены.','warn')}`:note('Загрузка данных…');
  for(const [route,[endpoint,label]] of Object.entries(sections)) {
    if(!routes[route])routes[route]={key:route,id:route,title:label,section:label,actions:''};
    routes[route].subtitle='Данные API · область текущего сотрудника';
    routes[route].actions='<button id="refresh-data" type="button">Обновить</button>'+(route==='privacy'?'<a class="btn" href="#legal-holds">Законное удержание</a>':'');
    if(route==='top100')routes[route].actions+='<a class="btn" href="#ranking">Настройки рейтинга</a>';
    if(route==='contractors')routes[route].actions+='<a class="btn" href="#bulk-preview">Массовая операция</a>';
    if(route==='push')routes[route].actions+='<a class="btn" href="#push-compose">Новое сообщение</a>';
    routes[route].body=()=> {
      const data=cache[route];if(!data)return note('Загрузка данных…');
      const configs=configRoutes.has(route);
      const rows=data.items.map(x=>[esc(x.id),esc(x.display_name??x.title??x.subject??x.action??x.reason??x.type??''),badge(esc(x.status??'')),esc(x.created_at),route==='blacklist'?`<a href="#blacklist-detail?id=${esc(x.id)}">Открыть →</a>`:route==='moderation'?`<a href="#case-live/${x.id}">Открыть →</a>`:route==='support-recovery'?`<a href="#recovery-live/${x.id}">Открыть →</a>`:route==='support'?`<a href="#support-live/${x.id}">Открыть →</a>`:['users','orders','portfolio','contractors','verification','privacy'].includes(route)?`<a href="#record-live/${route}/${x.id}">Открыть →</a>`:configs?`<button type="button" data-record="${esc(x.id)}">Открыть</button>`:'']);
      return `<form id="list-filters" class="filters"><input name="q" aria-label="Поиск по ID или названию" placeholder="ID или название" value="${esc(filters[route]?.q)}"><input name="status" aria-label="Статус записи" placeholder="Статус" value="${esc(filters[route]?.status)}"><button type="submit">Найти</button><button id="reset-filters" type="button">Сбросить</button></form>`+tablecard(label,['ID','Описание','Статус','Дата',''],rows,'',`${data.items.length} записей · ${data.meta?.next_cursor?'Есть следующая страница':'Конец списка'}`)+`<div class="actions"><button id="first-page">Первая страница</button>${data.meta?.next_cursor?'<button id="next-page">Следующая страница</button>':''}</div>`+(configs?card('Новый черновик',`<form id="draft-config" class="stack">${namedField('Название','title')}${namedField('Причина','reason')}${namedField('Параметры JSON','payload','textarea')}<button class="primary">Сохранить черновик</button></form>${note('Публикация требует проверки политики и провайдеров. Сохранение черновика не включает платный доступ.','warn')}`):'');
    };
  }
  // Unimplemented operations remain clearly identified as design references.
  for(const [key,r] of Object.entries(routes))if(!['login','mfa','dashboard',...Object.keys(sections)].includes(key)) {
    r.actions='';r.body=()=>note('Сценарий этого раздела ещё не подключён к API.','warn');
  }
}
function formError(form,failure){let alert=form.querySelector('[role=alert]');if(!alert){alert=document.createElement('div');alert.className='note danger';alert.role='alert';form.append(alert);}alert.textContent=failure.message;}
function formBusy(form,busy){form.querySelectorAll('button,input,textarea,select').forEach(element=>element.disabled=busy);}
function bind(key) {
  const filter=document.getElementById('list-filters');if(filter)filter.onsubmit=e=>{e.preventDefault();filters[key]=Object.fromEntries(new FormData(filter));delete cursors[key];draw();};
  const reset=document.getElementById('reset-filters');if(reset)reset.onclick=()=>{delete filters[key];delete cursors[key];draw();};
  const refresh=document.getElementById('refresh-data');if(refresh)refresh.onclick=()=>draw();
  const next=document.getElementById('next-page');if(next)next.onclick=()=>{cursors[key]=cache[key]?.meta?.next_cursor;draw();};
  const first=document.getElementById('first-page');if(first)first.onclick=()=>{delete cursors[key];draw();};
  document.querySelectorAll('[data-record]').forEach(button=>button.onclick=()=>{
    const record=cache[key].items.find(r=>r.id===button.dataset.record);
    const previewRoute={dictionary:'dictionary-dryrun',dictionaries:'dictionary-dryrun',campaigns:'promo-preview',referrals:'referral-preview',monetization:'monetization-preview'}[key];
    if(!record)return;
    const panel=document.createElement('section');panel.className='card';
    panel.innerHTML=`<div class="cardbody"><h2>${esc(record.title)}</h2>${previewRoute?`<a class="btn" href="#${previewRoute}?id=${esc(record.id)}">${previewRoute==='dictionary-dryrun'?'Проверить текст':'Предпросмотр'}</a>`:''}<pre>${esc(JSON.stringify(record.payload,null,2))}</pre><form class="stack">${namedField('Служебная причина','reason','textarea')}<div class="actions">${['validate','preview',...(record.status==='draft'?['publish']:['stop','rollback'])].map(command=>`<button type="submit" value="${command}">${{validate:'Проверить',preview:'Предпросмотр',publish:'Опубликовать',stop:'Остановить',rollback:'Черновик отката'}[command]}</button>`).join('')}</div></form><pre class="result" role="status"></pre></div>`;
    document.querySelector('.workspace')?.append(panel);panel.scrollIntoView({behavior:'smooth'});
    panel.querySelector('form').onsubmit=async e=>{e.preventDefault();const command=e.submitter?.value;if(!command)return;
      const form=e.currentTarget;const buttons=[...form.querySelectorAll('button')];buttons.forEach(b=>b.disabled=true);
      try{const result=await api('/admin/'+sections[key][0]+'/'+record.id+'/'+command,'POST',{expected_version:record.version,reason:new FormData(form).get('reason')});
        if(['validate','preview'].includes(command))panel.querySelector('.result').textContent=JSON.stringify(result,null,2);else await draw();
      }catch(error){panel.querySelector('.result').textContent=error.message;}finally{buttons.forEach(b=>b.disabled=false);}
    };
  });

  const login=document.getElementById('staff-login');if(login)login.onsubmit=e=>{e.preventDefault();loginDraft=Object.fromEntries(new FormData(login));error='';location.hash='mfa';};
  const mfa=document.getElementById('staff-mfa');if(mfa)mfa.onsubmit=async e=>{e.preventDefault();const button=mfa.querySelector('button');button.disabled=true;
    try{session=await api('/auth/staff-login','POST',{...loginDraft,...Object.fromEntries(new FormData(mfa))});loginDraft=undefined;error='';location.hash='dashboard';}
    catch(e){error=e.message;draw(false);}finally{button.disabled=false;}};
  const form=document.getElementById('draft-config');if(form)form.onsubmit=async event=>{event.preventDefault();const values=Object.fromEntries(new FormData(form));formBusy(form,true);try{values.payload=JSON.parse(values.payload||'{}');await api('/admin/'+sections[key][0],'POST',values);await draw();}catch(failure){formError(form,failure);}finally{formBusy(form,false);}};
  const evidence=document.getElementById('case-appeal-evidence');if(evidence){const viewGeneration=generation,viewer=session.user.id,country=session.user.country;evidence.onsubmit=async e=>{
    e.preventDefault();const values=Object.fromEntries(new FormData(evidence));formBusy(evidence,true);try{
      const blob=await api.download('/uploads/'+encodeURIComponent(values.upload_id)+'/download?'+new URLSearchParams({reason:values.reason}));
      if(viewGeneration!==generation||session?.user?.id!==viewer||session?.user?.country!==country)return;
      const url=URL.createObjectURL(blob),link=document.createElement('a');link.href=url;link.download='appeal-evidence-'+values.upload_id+(blob.type==='application/pdf'?'.pdf':blob.type==='image/png'?'.png':'.jpg');document.body.append(link);link.click();link.remove();setTimeout(()=>URL.revokeObjectURL(url),1000);
    }catch(error){if(viewGeneration===generation)formError(evidence,error);}finally{formBusy(evidence,false);}
  };}
  const caseReply=document.getElementById('case-reply');if(caseReply)caseReply.onsubmit=async e=>{e.preventDefault();const button=caseReply.querySelector('button');button.disabled=true;try{await api('/admin/cases/'+cache.case.id+'/messages','POST',Object.fromEntries(new FormData(caseReply)));await draw();}catch(e){formError(caseReply,e);}finally{button.disabled=false;}};
  const caseDecision=document.getElementById('case-decision');if(caseDecision)caseDecision.onsubmit=async e=>{e.preventDefault();const button=caseDecision.querySelector('button');button.disabled=true;try{await api('/admin/cases/'+cache.case.id+'/'+(cache.case.status==='appealed'?'appeal-decision':'resolve'),'POST',{...Object.fromEntries(new FormData(caseDecision)),expected_version:cache.case.version,expected_target_version:cache.case.target_context?.version});await draw();}catch(e){formError(caseDecision,e);}finally{button.disabled=false;}};
  const assign=document.getElementById('assign-support');if(assign)assign.onclick=async()=>{try{await api('/admin/support-threads/'+cache.thread.id+'/commands','POST',{command:'assign',reason:'Назначение обращения сотруднику поддержки',expected_version:cache.thread.version});await draw();}catch(e){error=e.message;draw(false);}};
  const reply=document.getElementById('reply-support');if(reply){const pendingMessages=new Map(),threadId=cache.thread.id;reply.onsubmit=async e=>{e.preventDefault();const text=String(new FormData(reply).get('text')||'').trim();const messageId=pendingMessages.get(text)||crypto.randomUUID();pendingMessages.set(text,messageId);while(pendingMessages.size>20)pendingMessages.delete(pendingMessages.keys().next().value);formBusy(reply,true);try{await api('/admin/support-threads/'+threadId+'/messages','POST',{text,client_message_id:messageId});await draw();}catch(e){formError(reply,e);}finally{formBusy(reply,false);}};}
}
async function draw(reload=true) {
  if(designMode){render();return;}
  disposeWorkspace?.();disposeWorkspace=undefined;
  clearStaffDialogs();
  const key=location.hash.slice(1).split('?')[0]||'dashboard',g=++generation;
  if(!session&&key!=='login'&&!(key==='mfa'&&loginDraft)){location.hash='login';return;}
  if(key==='login')loginDraft=undefined;
  const request=async(...args)=>{if(g!==generation)throw Error('Экран изменился');const data=await api(...args);if(g!==generation)throw Error('Экран изменился');return data;};
  try {
    if(reload&&session){
      const workspace=document.querySelector('.workspace');if(workspace){workspace.innerHTML=note('Загрузка данных…');workspace.setAttribute('aria-busy','true');}
      if(pushRoutes.has(key))routes[key]=await pushWorkspace({key,country:session.user.country,canManageTests:session.user.staff_permissions?.includes('administrator'),api:request,esc,card,tablecard,note,badge,namedField,onRefresh:()=>draw()});
      if(scenarioRoutes.has(key)&&!['promo','promo-preview','banner-detail','referral-preview'].includes(key))routes[key]=await scenarioWorkspace({key,api:request,esc,card,tablecard,note,namedField,onRefresh:()=>draw()});
      if(['boosts','boost-grant'].includes(key))routes[key]=await boostWorkspace({key,api:request,esc,card,tablecard,note,badge,onRefresh:()=>draw()});
      if(key==='branding-build')routes[key]=await brandingBuildWorkspace({key,api:request,download:api.download,esc,card,tablecard,note,badge,onRefresh:()=>draw()});
      if(key==='branding')routes[key]=await brandingWorkspace({key,api:request,files:{upload:async file=>{if(g!==generation)throw Error('Экран изменился');const result=await api.upload(file);if(g!==generation)throw Error('Экран изменился');return result;},download:async path=>{if(g!==generation)throw Error('Экран изменился');const result=await api.download(path);if(g!==generation)throw Error('Экран изменился');return result;}},esc,card,note,badge,namedField,onRefresh:()=>draw()});
      if(key==='countries')routes[key]=await countryWorkspace({key,api:request,esc,card,note,badge,namedField,onRefresh:()=>draw()});
      if(['analytics','dashboard','security','jobs','scheduled','job-detail'].includes(key))routes[key]=await systemWorkspace({key,api:request,esc,card,tablecard,note,metric,badge,onRefresh:()=>draw()});
      if(key==='security')routes[key].actions+='<a class="btn" href="#security-full">Защищённый просмотр</a>';
      if(sections[key]&&!pushRoutes.has(key)&&!['placements','ranking','referrals','campaigns','verificationPolicies','retention','prices','pricing','categories'].includes(key))cache[key]=await request('/admin/'+sections[key][0]+'?'+new URLSearchParams({...filters[key],...(cursors[key]?{cursor:cursors[key]}:{})}));
      if(key==='categories')routes[key]=await categoryWorkspace({key,api:request,esc,card,note,tablecard,country:session.user.country,actorId:session.user.id,onRefresh:()=>draw()});
      if(['verificationPolicies','retention'].includes(key))routes[key]=await documentPolicyWorkspace({key,api:request,esc,card,note,tablecard,country:session.user.country,actorId:session.user.id,onRefresh:()=>draw()});
      if(['campaigns','banner-detail'].includes(key))routes[key]=await bannerWorkspace({key,api:request,files:{upload:async file=>{if(g!==generation)throw Error('Экран изменился');const result=await api.upload(file,'banner');if(g!==generation)throw Error('Экран изменился');return result;},download:async path=>{if(g!==generation)throw Error('Экран изменился');const result=await api.download(path);if(g!==generation)throw Error('Экран изменился');return result;}},esc,card,note,tablecard,country:session.user.country,actorId:session.user.id,onRefresh:()=>draw()});
      if(['promo','promo-preview'].includes(key))routes[key]=await promotionWorkspace({key,api:request,esc,card,note,tablecard,country:session.user.country,actorId:session.user.id,onRefresh:()=>draw()});
      if(key==='placements')routes[key]=await placementWorkspace({key,api:request,esc,card,note,tablecard,country:session.user.country,actorId:session.user.id,onRefresh:()=>draw()});
      if(key==='ranking')routes[key]=await rankingWorkspace({key,api:request,esc,card,note,tablecard,country:session.user.country,actorId:session.user.id,onRefresh:()=>draw()});
      if(['referrals','referral-preview'].includes(key))routes[key]=await referralWorkspace({key,api:request,esc,card,note,tablecard,country:session.user.country,actorId:session.user.id,onRefresh:()=>draw()});
      if(['pricing','prices'].includes(key))routes[key]=await priceWorkspace({key,api:request,esc,card,note,tablecard,country:session.user.country,actorId:session.user.id,onRefresh:()=>draw()});
      if(key==='monetization')routes[key]=await monetizationWorkspace({key,api:request,esc,card,note,metric,badge,namedField,onRefresh:()=>draw()});
      if(['settings','legal'].includes(key)||key.startsWith('recovery-live/'))routes[key]=await operationsWorkspace({key,api:request,esc,card,note,namedField,onRefresh:()=>draw()});
      if(userRoutes.has(key)||key.startsWith('record-live/users/'))routes[key]=await userWorkspace({key,api:request,esc,card,tablecard,note,badge,namedField,sections,onRefresh:()=>draw()});
      if(key.startsWith('record-live/')&&!key.startsWith('record-live/users/')){
        routes[key]=await reviewWorkspace({key,api:request,esc,card,note,namedField,sections,onRefresh:()=>draw()});
      }
      if(key.startsWith('case-live/')){
        const caseId=key.split('/')[1];cache.case=await request('/admin/cases/'+caseId);const messages=await request('/admin/cases/'+caseId+'/messages');
        routes[key]={key,id:'A06',title:'Дело и апелляция',subtitle:caseId,section:'Модерация',actions:'<button id="refresh-data" type="button">Обновить</button>',body:()=>`<div class="grid cols2">${card('Обстоятельства',`${badge(esc(cache.case.status))}<p>${esc(cache.case.description??cache.case.reason_code)}</p><p>${esc(cache.case.appeal_reason??'')}</p><p>${esc(cache.case.reason??'')}</p>${cache.case.target_snapshot?`<details><summary>Зафиксированный материал · версия ${esc(cache.case.target_version)}</summary><pre>${esc(JSON.stringify(cache.case.target_snapshot,null,2))}</pre></details>`:''}${cache.case.target_context?.changed?note('Материал после обращения изменён. Решение не удаляет другую версию.','warn'):''}${cache.case.status==='resolved'?'':`<form id="case-decision" class="stack"><label>Решение</label><select name="decision">${cache.case.status==='appealed'?'<option value="sanction_upheld">Оставить решение</option><option value="overturned">Отменить решение</option>':'<option value="no_violation">Нарушение не подтверждено</option><option value="content_removed">Скрыть материал</option><option value="sanction_upheld">Подтвердить существующее ограничение</option>'}</select>${namedField('Основание решения','reason','textarea')}${cache.case.reporter_private?namedField('Объяснение субъекту без данных заявителя','public_reason','textarea'):''}<button class="primary">${cache.case.status==='appealed'?'Решение по апелляции':'Зафиксировать решение'}</button></form>`}`)}${cache.case.appeal_upload_ids?.length?card('Материалы апелляции',`<form id="case-appeal-evidence" class="stack"><label for="appeal-evidence-file">Файл</label><select id="appeal-evidence-file" name="upload_id">${cache.case.appeal_upload_ids.map((id,index)=>`<option value="${esc(id)}">Файл ${index+1}</option>`).join('')}</select>${namedField('Служебная причина просмотра материалов','reason','textarea')}<button class="primary">Скачать материал</button></form>`):''}${card('Переписка по делу',`${messages.items.map(m=>`<div class="event"><b>${m.internal?'Внутренняя заметка':m.owner===session.user.id?'Сотрудник':'Участник'}</b><p>${esc(m.text)}</p><time>${esc(m.created_at)}</time></div>`).join('')}<form id="case-reply" class="stack">${namedField('Сообщение участникам','text','textarea')}${namedField('Служебная причина','reason','textarea')}<button class="primary">Отправить сообщение</button></form>`)}</div>`};
      }
      if(key.startsWith('support-live/')) {
        cache.thread=await request('/admin/support-threads/'+encodeURIComponent(key.split('/')[1]));
        if(!cache.thread)throw Error('Обращение не найдено');
        let messages=[];if(cache.thread.assignee_id===session.user.id)messages=(await request('/admin/support-threads/'+cache.thread.id+'/messages')).items;
        routes[key]={key,id:'A14',title:cache.thread.subject,subtitle:cache.thread.id,section:'Поддержка',actions:'',body:()=>card('Обращение',`${badge(esc(cache.thread.status))}<p>${esc(cache.thread.subject)}</p>${cache.thread.assignee_id!==session.user.id?'<button class="primary" id="assign-support">Назначить себе</button>':messages.map(m=>`<div class="event"><b>${m.owner===session.user.id?'Поддержка':'Пользователь'}</b><p>${esc(m.text)}</p><time>${esc(m.created_at)}</time></div>`).join('')+`<form id="reply-support" class="stack">${namedField('Ответ поддержки','text','textarea')}<button class="primary">Отправить</button></form>`}`)};
      }
    }
  }catch(e){if(g!==generation)return;error=e.message;if(!['login','mfa'].includes(key))routes[key]={key,id:'',title:'Карточка недоступна',subtitle:'',section:'',actions:'',body:()=>note(esc(e.message),'danger')};if(e.code==='TOKEN_EXPIRED'){clearStaffState();location.hash='login';return;}}
  if(g!==generation)return;render();document.querySelector('.workspace')?.removeAttribute('aria-busy');document.querySelector('.statebar')?.remove();
  if(session){
    const portfolioLink=document.querySelector('.nav a[href="#portfolio"]');if(portfolioLink&&!document.querySelector('.nav a[href="#contractors"]')){const link=document.createElement('a');link.href='#contractors';link.textContent='Профили исполнителей';portfolioLink.after(link);}
    const nav=document.querySelector('.nav');if(nav&&!nav.querySelector('[href="#legal"]')){const link=document.createElement('a');link.href='#legal';link.textContent='Правовые документы';nav.append(link);}
    document.querySelectorAll('.nav .count').forEach(el=>el.remove());
    const account=document.querySelector('.account');if(account)account.innerHTML=`<span class="avatar">${esc((session.user.display_name||session.user.phone||'').slice(0,2))}</span><div><b>${esc(session.user.display_name||session.user.phone)}</b><small>${esc(session.user.country)} · сотрудник</small></div><button id="staff-logout">Выйти</button>`;
    document.querySelector('#staff-logout')?.addEventListener('click',async()=>{try{await api('/auth/logout','POST');}finally{clearStaffState();location.hash='login';}});
    const country=document.querySelector('.select-country');if(country)country.textContent=session.user.country;
    const env=document.querySelector('.env');if(env)env.textContent='API · служебный доступ';
    const demo=document.querySelector('.demobadge');if(demo)demo.textContent='API';
    const foot=document.querySelector('.sidebarfoot .tiny');if(foot)foot.textContent='JOBA · ТЗ v1.1';
    const status=document.querySelector('.statusbar');if(status)status.textContent='Данные API · '+session.user.country;
  }
  if(error&&!['login','mfa'].includes(key)){const el=document.createElement('div');el.innerHTML=note(esc(error),'danger');el.setAttribute('role','alert');document.querySelector('.workspace')?.prepend(el);}
  bind(key);
  routes[key]?.bind?.();disposeWorkspace=routes[key]?.dispose;
  if(session)wireLiveShell({api,esc,card,onRefresh:()=>draw()});
}
window.addEventListener('hashchange',()=>{error='';draw();});
draw();

// Prototype actions must never present synthetic success in the live panel.
document.addEventListener('click',event=>{
 if(designMode)return;
 const button=event.target.closest('[data-action]');if(!button)return;
 event.stopImmediatePropagation();
 const action=button.dataset.action;
 if(routes[action])location.hash=action;
 else if(action==='navigation')document.querySelector('.sidebar')?.classList.toggle('open');
},true);
