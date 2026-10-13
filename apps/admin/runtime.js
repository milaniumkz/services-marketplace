import './design.js';
const {routes,render,card,tablecard,field,note,metric,badge}=window.JOBA_ADMIN;
const designMode=new URLSearchParams(location.search).has('design');
const esc=v=>String(v??'').replace(/[&<>"']/g,c=>({'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;',"'":'&#39;'}[c]));
let session,loginDraft,cache={},error='',generation=0;
const cursors={},configRoutes=new Set(['prices','pricing','monetization','push','referrals','dictionaries','dictionary','categories','ranking','campaigns','placements','verificationPolicies','retention']);
const sections={users:['users','Аккаунты'],orders:['orders','Заказы'],support:['support-threads','Поддержка'],moderation:['cases','Дела'],portfolio:['portfolio','Портфолио'],privacy:['privacy-requests','Запросы приватности'],blacklist:['blacklist','Черный список'],audit:['audit','Аудит'],prices:['price-versions','Цены'],monetization:['monetization-configs','Монетизация'],push:['push-campaigns','Рассылки'],referrals:['referral-campaigns','Реферальные кампании'],dictionaries:['moderation-dictionaries','Словари'],categories:['categories','Категории'],ranking:['ranking-configs','Рейтинг'],pricing:['price-versions','Каталог цен'],campaigns:['promotions','Кампании'],dictionary:['moderation-dictionaries','Запрещенные слова'],verification:['verifications','Проверка документов'],top100:['boost-reports','Топ и продвижение'],placements:['placement-policies','Размещения'],verificationPolicies:['verification-policies','Правила проверки'],retention:['retention-policies','Сроки хранения']};
async function api(path,method='GET',body={}) {
  const r=await fetch('/api/v1'+path,{method,headers:{'Content-Type':'application/json',...(session?{Authorization:'Bearer '+session.access_token}:{}),...(method==='GET'?{}:{'Idempotency-Key':crypto.randomUUID()})},body:method==='GET'?undefined:JSON.stringify(body)});
  const j=await r.json();if(!r.ok){const e=Error(j.error?.message??'Ошибка сервиса');e.code=j.error?.code;throw e;}return j.data;
}
const namedField=(label,name,type='text')=>field(label,'',type).replace('<input ','<input name="'+name+'" ').replace('<textarea ','<textarea name="'+name+'" ');
if(!designMode) {
  routes.login.body=()=>`<div class="login"><section class="loginbrand"><div class="brand"><img src="/assets/joba-logo-original.jpeg" alt="JOBA"><div><b>JOBA</b><small>CONTROL CENTER</small></div></div><div><div class="eyebrow" style="color:#92B5F5;margin-bottom:18px">СЕРВИС НАЧИНАЕТСЯ С ДОВЕРИЯ</div><h1>Все инструменты.<br>Одна рабочая среда.</h1><p>Операции, поддержка и безопасность маркетплейса услуг JOBA.</p></div><div class="tiny" style="color:#92A9CE">Только для уполномоченных сотрудников</div></section><section class="loginform"><span class="demobadge">СЛУЖЕБНЫЙ ВХОД</span><h1 style="margin-top:18px">Вход в панель</h1><p class="muted" style="margin-top:10px">Используйте служебную учетную запись. Доступ определяется ролью и страной.</p><form id="staff-login" class="stack">${namedField('Рабочий идентификатор','phone')}${namedField('Пароль','password','password')}<div class="formfield"><label for="staff-country">Страна</label><select id="staff-country" name="country"><option>KZ</option><option>RS</option><option>RU</option><option>BY</option></select></div><button class="primary">Продолжить</button></form>${error?note(esc(error),'danger'):''}<div class="notice-slim" style="margin-top:20px">После ввода пароля потребуется второй фактор. Это отдельный вход, не пользовательский аккаунт JOBA.</div><p class="helptext" style="margin-top:32px">Возникли проблемы со входом? Обратитесь к ответственному за доступ в вашей организации.</p></section></div>`;
  routes.mfa.body=()=>`<div style="max-width:440px;margin:65px auto">${card('Подтвердите доступ',`${note('Служебная сессия · '+esc(loginDraft?.phone)+' · страна '+esc(loginDraft?.country),'','shield')}<form id="staff-mfa" class="stack">${namedField('Код второго фактора','mfa_code')}<button class="primary">Продолжить</button></form>${error?note(esc(error),'danger'):''}<p class="helptext" style="margin-top:20px"><a href="#login">Вернуться ко входу</a></p>`)}</div>`;
  routes.dashboard.body=()=>cache.dashboard?`<div class="grid cols4">${metric('Пользователи',cache.dashboard.users,'','В текущем регионе')}${metric('Заказы',cache.dashboard.orders,'','Все состояния')}${metric('Открытые обращения',cache.dashboard.support,'','Требуют внимания')}${metric('Страна',cache.dashboard.country,'','Служебная область')}</div>${note('Коммерческие launch gates не пройдены. Оплата и рекламные награды отключены.','warn')}`:note('Загрузка данных…');
  for(const [route,[endpoint,label]] of Object.entries(sections)) {
    if(!routes[route])routes[route]={key:route,id:route,title:label,section:label,actions:''};
    routes[route].subtitle='Данные API · область текущего сотрудника';
    routes[route].actions='';
    routes[route].body=()=> {
      const data=cache[route];if(!data)return note('Загрузка данных…');
      const configs=configRoutes.has(route);
      const rows=data.items.map(x=>[esc(x.id),esc(x.display_name??x.title??x.subject??x.action??x.reason??x.type??''),badge(esc(x.status??'')),esc(x.created_at),route==='moderation'?`<a href="#case-live/${x.id}">Открыть →</a>`:route==='support'?`<a href="#support-live/${x.id}">Открыть →</a>`:configs?`<button type="button" data-record="${esc(x.id)}">Открыть</button>`:'']);
      return tablecard(label,['ID','Описание','Статус','Дата',''],rows,'',`${data.items.length} записей · ${data.meta?.next_cursor?'Есть следующая страница':'Конец списка'}`)+`<div class="actions"><button id="first-page">Первая страница</button>${data.meta?.next_cursor?'<button id="next-page">Следующая страница</button>':''}</div>`+(configs?card('Новый черновик',`<form id="draft-config" class="stack">${namedField('Название','title')}${namedField('Причина','reason')}${namedField('Параметры JSON','payload','textarea')}<button class="primary">Сохранить черновик</button></form>${note('Публикация требует проверки политики и провайдеров. Сохранение черновика не включает платный доступ.','warn')}`):'');
    };
  }
  // Unimplemented operations remain clearly identified as design references.
  for(const [key,r] of Object.entries(routes))if(!['login','mfa','dashboard',...Object.keys(sections)].includes(key)) {
    r.actions='';r.body=()=>note('Сценарий этого раздела ещё не подключён к API.','warn');
  }
}
function bind(key) {
  const next=document.getElementById('next-page');if(next)next.onclick=()=>{cursors[key]=cache[key]?.meta?.next_cursor;draw();};
  const first=document.getElementById('first-page');if(first)first.onclick=()=>{delete cursors[key];draw();};
  document.querySelectorAll('[data-record]').forEach(button=>button.onclick=()=>{
    const record=cache[key].items.find(r=>r.id===button.dataset.record);
    if(!record)return;
    const panel=document.createElement('section');panel.className='card';
    panel.innerHTML=`<div class="cardbody"><h2>${esc(record.title)}</h2><pre>${esc(JSON.stringify(record.payload,null,2))}</pre><form class="stack">${namedField('Служебная причина','reason','textarea')}<div class="actions">${['validate','preview',...(record.status==='draft'?['publish']:['stop','rollback'])].map(command=>`<button type="submit" value="${command}">${{validate:'Проверить',preview:'Предпросмотр',publish:'Опубликовать',stop:'Остановить',rollback:'Черновик отката'}[command]}</button>`).join('')}</div></form><pre class="result" role="status"></pre></div>`;
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
  const form=document.getElementById('draft-config');if(form)form.onsubmit=async e=>{e.preventDefault();try{const b=Object.fromEntries(new FormData(form));b.payload=JSON.parse(b.payload||'{}');await api('/admin/'+sections[key][0],'POST',b);await draw();}catch(e){error=e.message;draw(false);}};
  const caseReply=document.getElementById('case-reply');if(caseReply)caseReply.onsubmit=async e=>{e.preventDefault();const button=caseReply.querySelector('button');button.disabled=true;try{await api('/admin/cases/'+cache.case.id+'/messages','POST',Object.fromEntries(new FormData(caseReply)));await draw();}catch(e){error=e.message;draw(false);}finally{button.disabled=false;}};
  const caseDecision=document.getElementById('case-decision');if(caseDecision)caseDecision.onsubmit=async e=>{e.preventDefault();const button=caseDecision.querySelector('button');button.disabled=true;try{await api('/admin/cases/'+cache.case.id+'/'+(cache.case.status==='appealed'?'appeal-decision':'resolve'),'POST',{...Object.fromEntries(new FormData(caseDecision)),expected_version:cache.case.version});await draw();}catch(e){error=e.message;draw(false);}finally{button.disabled=false;}};
  const assign=document.getElementById('assign-support');if(assign)assign.onclick=async()=>{try{await api('/admin/support-threads/'+cache.thread.id+'/commands','POST',{command:'assign',reason:'Назначение обращения сотруднику поддержки',expected_version:cache.thread.version});await draw();}catch(e){error=e.message;draw(false);}};
  const reply=document.getElementById('reply-support');if(reply)reply.onsubmit=async e=>{e.preventDefault();try{await api('/admin/support-threads/'+cache.thread.id+'/messages','POST',{text:new FormData(reply).get('text'),client_message_id:crypto.randomUUID()});await draw();}catch(e){error=e.message;draw(false);}};
}
async function draw(reload=true) {
  if(designMode){render();return;}
  const key=location.hash.slice(1).split('?')[0]||'dashboard',g=++generation;
  if(!session&&key!=='login'&&!(key==='mfa'&&loginDraft)){location.hash='login';return;}
  if(key==='login')loginDraft=undefined;
  try {
    if(reload&&session){
      if(key==='dashboard')cache.dashboard=await api('/admin/dashboard');
      if(sections[key])cache[key]=await api('/admin/'+sections[key][0]+(cursors[key]?'?cursor='+encodeURIComponent(cursors[key]):''));
      if(key.startsWith('case-live/')){
        const caseId=key.split('/')[1];cache.case=await api('/admin/cases/'+caseId);const messages=await api('/admin/cases/'+caseId+'/messages');
        routes[key]={key,id:'A06',title:'Дело и апелляция',subtitle:caseId,section:'Модерация',actions:'',body:()=>`<div class="grid cols2">${card('Обстоятельства',`${badge(esc(cache.case.status))}<p>${esc(cache.case.description??cache.case.reason_code)}</p><p>${esc(cache.case.appeal_reason??'')}</p><p>${esc(cache.case.reason??'')}</p>${cache.case.status==='resolved'?'':`<form id="case-decision" class="stack"><label>Решение</label><select name="decision"><option value="no_violation">Нарушение не подтверждено</option><option value="content_removed">Материал удалён</option><option value="sanction_upheld">Ограничение подтверждено</option><option value="overturned">Решение отменено</option></select>${namedField('Основание решения','reason','textarea')}<button class="primary">${cache.case.status==='appealed'?'Решение по апелляции':'Зафиксировать решение'}</button></form>`}`)}${card('Переписка по делу',`${messages.items.map(m=>`<div class="event"><b>${m.internal?'Внутренняя заметка':m.owner===session.user.id?'Сотрудник':'Участник'}</b><p>${esc(m.text)}</p><time>${esc(m.created_at)}</time></div>`).join('')}<form id="case-reply" class="stack">${namedField('Сообщение участникам','text','textarea')}${namedField('Служебная причина','reason','textarea')}<button class="primary">Отправить сообщение</button></form>`)}</div>`};
      }
      if(key.startsWith('support-live/')) {
        const list=await api('/admin/support-threads');cache.thread=list.items.find(x=>x.id===key.split('/')[1]);
        if(!cache.thread)throw Error('Обращение не найдено');
        let messages=[];if(cache.thread.assignee_id===session.user.id)messages=(await api('/admin/support-threads/'+cache.thread.id+'/messages')).items;
        routes[key]={key,id:'A14',title:cache.thread.subject,subtitle:cache.thread.id,section:'Поддержка',actions:'',body:()=>card('Обращение',`${badge(esc(cache.thread.status))}<p>${esc(cache.thread.subject)}</p>${cache.thread.assignee_id!==session.user.id?'<button class="primary" id="assign-support">Назначить себе</button>':messages.map(m=>`<div class="event"><b>${m.owner===session.user.id?'Поддержка':'Пользователь'}</b><p>${esc(m.text)}</p><time>${esc(m.created_at)}</time></div>`).join('')+`<form id="reply-support" class="stack">${namedField('Ответ поддержки','text','textarea')}<button class="primary">Отправить</button></form>`}`)};
      }
    }
  }catch(e){error=e.message;if(e.code==='TOKEN_EXPIRED'){session=undefined;location.hash='login';return;}}
  if(g!==generation)return;render();document.querySelector('.statebar')?.remove();
  if(session){
    document.querySelectorAll('.nav .count').forEach(el=>el.remove());
    const account=document.querySelector('.account');if(account)account.innerHTML=`<span class="avatar">${esc((session.user.display_name||session.user.phone||'').slice(0,2))}</span><div><b>${esc(session.user.display_name||session.user.phone)}</b><small>${esc(session.user.country)} · сотрудник</small></div><button id="staff-logout">Выйти</button>`;
    document.querySelector('#staff-logout')?.addEventListener('click',async()=>{try{await api('/auth/logout','POST');}finally{session=undefined;cache={};location.hash='login';}});
    const country=document.querySelector('.select-country');if(country)country.textContent=session.user.country;
    const env=document.querySelector('.env');if(env)env.textContent='API · служебный доступ';
    const demo=document.querySelector('.demobadge');if(demo)demo.textContent='API';
    const foot=document.querySelector('.sidebarfoot .tiny');if(foot)foot.textContent='JOBA · ТЗ v1.1';
    const status=document.querySelector('.statusbar');if(status)status.textContent='Данные API · '+session.user.country;
  }
  if(error&&!['login','mfa'].includes(key)){const el=document.createElement('div');el.innerHTML=note(esc(error),'danger');el.setAttribute('role','alert');document.querySelector('.workspace')?.prepend(el);}
  bind(key);
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
