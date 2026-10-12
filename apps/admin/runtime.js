import './design.js';
const {routes,render,card,tablecard,field,note,metric,badge}=window.JOBA_ADMIN;
const designMode=new URLSearchParams(location.search).has('design');
const esc=v=>String(v??'').replace(/[&<>"']/g,c=>({'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;',"'":'&#39;'}[c]));
let session,cache={},error='',generation=0;
const sections={users:['users','Аккаунты'],orders:['orders','Заказы'],support:['support-threads','Поддержка'],moderation:['cases','Дела'],portfolio:['portfolio','Портфолио'],privacy:['privacy-requests','Запросы приватности'],blacklist:['blacklist','Черный список'],audit:['audit','Аудит'],prices:['price-versions','Цены'],monetization:['monetization-configs','Монетизация'],push:['push-campaigns','Рассылки'],referrals:['referral-campaigns','Реферальные кампании'],dictionaries:['moderation-dictionaries','Словари'],categories:['categories','Категории'],ranking:['ranking-configs','Рейтинг']};
async function api(path,method='GET',body={}) {
  const r=await fetch('/api/v1'+path,{method,headers:{'Content-Type':'application/json',...(session?{Authorization:'Bearer '+session.access_token}:{}),...(method==='GET'?{}:{'Idempotency-Key':crypto.randomUUID()})},body:method==='GET'?undefined:JSON.stringify(body)});
  const j=await r.json();if(!r.ok){const e=Error(j.error?.message??'Ошибка сервиса');e.code=j.error?.code;throw e;}return j.data;
}
const namedField=(label,name,type='text')=>field(label,'',type).replace('<input ','<input name="'+name+'" ').replace('<textarea ','<textarea name="'+name+'" ');
if(!designMode) {
  routes.login.body=()=>`<div class="login-page"><section class="loginvisual"><img class="login-logo" src="/assets/joba-logo-original.jpeg" alt="JOBA"><div><h1>Все инструменты.<br>Одна рабочая среда.</h1><p>Операции, поддержка и безопасность JOBA.</p></div></section><section class="loginform"><h1>Вход в панель</h1><p class="muted mt">Отдельный служебный вход с обязательным MFA.</p><form id="staff-login" class="stack">${namedField('Рабочий идентификатор','phone')}${namedField('Пароль','password','password')}${namedField('Код второго фактора','mfa_code')}<label>Страна</label><select name="country"><option>KZ</option><option>RS</option><option>RU</option><option>BY</option></select><button class="primary">Войти</button></form>${error?note(esc(error),'danger'):''}<p class="helptext">Локальные тестовые учетные записи не предназначены для production.</p></section></div>`;
  routes.dashboard.body=()=>cache.dashboard?`<div class="grid cols4">${metric('Пользователи',cache.dashboard.users,'','В текущем регионе')}${metric('Заказы',cache.dashboard.orders,'','Все состояния')}${metric('Открытые обращения',cache.dashboard.support,'','Требуют внимания')}${metric('Страна',cache.dashboard.country,'','Служебная область')}</div>${note('Коммерческие launch gates не пройдены. Оплата и рекламные награды отключены.','warn')}`:note('Загрузка данных…');
  for(const [route,[endpoint,label]] of Object.entries(sections)) {
    if(!routes[route])routes[route]={key:route,id:route,title:label,section:label,actions:''};
    routes[route].subtitle='Данные API · область текущего сотрудника';
    routes[route].actions='';
    routes[route].body=()=> {
      const data=cache[route];if(!data)return note('Загрузка данных…');
      const rows=data.items.map(x=>[esc(x.id),esc(x.display_name??x.title??x.subject??x.action??x.reason??x.type??''),badge(esc(x.status??'')),esc(x.created_at),route==='support'?`<a href="#support-live/${x.id}">Открыть →</a>`:'']);
      const configs=['prices','monetization','push','referrals','dictionaries','categories','ranking'].includes(route);
      return tablecard(label,['ID','Описание','Статус','Дата',''],rows,'',`${data.items.length} записей · ${data.meta?.next_cursor?'Есть следующая страница':'Конец списка'}`)+(configs?card('Новый черновик',`<form id="draft-config" class="stack">${namedField('Название','title')}${namedField('Причина','reason')}${namedField('Параметры JSON','payload','textarea')}<button class="primary">Сохранить черновик</button></form>${note('Публикация требует проверки политики и провайдеров. Сохранение черновика не включает платный доступ.','warn')}`):'');
    };
  }
  // Unimplemented operations remain clearly identified as design references.
  for(const [key,r] of Object.entries(routes))if(!['login','dashboard',...Object.keys(sections)].includes(key)) {
    const original=r.body;r.body=()=>note('Макет: серверный сценарий этого раздела ещё не подключён. Изменения не выполняются.','warn')+original();
  }
}
function bind(key) {
  const login=document.getElementById('staff-login');if(login)login.onsubmit=async e=>{e.preventDefault();const b=Object.fromEntries(new FormData(login));try{session=await api('/auth/staff-login','POST',b);error='';location.hash='dashboard';}catch(e){error=e.message;draw(false);}};
  const form=document.getElementById('draft-config');if(form)form.onsubmit=async e=>{e.preventDefault();try{const b=Object.fromEntries(new FormData(form));b.payload=JSON.parse(b.payload||'{}');await api('/admin/'+sections[key][0],'POST',b);await draw();}catch(e){error=e.message;draw(false);}};
  const assign=document.getElementById('assign-support');if(assign)assign.onclick=async()=>{try{await api('/admin/support-threads/'+cache.thread.id+'/commands','POST',{command:'assign',reason:'Назначение обращения сотруднику поддержки',expected_version:cache.thread.version});await draw();}catch(e){error=e.message;draw(false);}};
  const reply=document.getElementById('reply-support');if(reply)reply.onsubmit=async e=>{e.preventDefault();try{await api('/admin/support-threads/'+cache.thread.id+'/messages','POST',{text:new FormData(reply).get('text'),client_message_id:crypto.randomUUID()});await draw();}catch(e){error=e.message;draw(false);}};
}
async function draw(reload=true) {
  if(designMode){render();return;}
  const key=location.hash.slice(1).split('?')[0]||'dashboard',g=++generation;
  if(!session&&key!=='login'){location.hash='login';return;}
  try {
    if(reload&&session){
      if(key==='dashboard')cache.dashboard=await api('/admin/dashboard');
      if(sections[key])cache[key]=await api('/admin/'+sections[key][0]);
      if(key.startsWith('support-live/')) {
        const list=await api('/admin/support-threads');cache.thread=list.items.find(x=>x.id===key.split('/')[1]);
        if(!cache.thread)throw Error('Обращение не найдено');
        let messages=[];if(cache.thread.assignee_id===session.user.id)messages=(await api('/admin/support-threads/'+cache.thread.id+'/messages')).items;
        routes[key]={key,id:'A14',title:cache.thread.subject,subtitle:cache.thread.id,section:'Поддержка',actions:'',body:()=>card('Обращение',`${badge(esc(cache.thread.status))}<p>${esc(cache.thread.subject)}</p>${cache.thread.assignee_id!==session.user.id?'<button class="primary" id="assign-support">Назначить себе</button>':messages.map(m=>`<div class="event"><b>${m.owner===session.user.id?'Поддержка':'Пользователь'}</b><p>${esc(m.text)}</p><time>${esc(m.created_at)}</time></div>`).join('')+`<form id="reply-support" class="stack">${namedField('Ответ поддержки','text','textarea')}<button class="primary">Отправить</button></form>`}`)};
      }
    }
  }catch(e){error=e.message;if(e.code==='TOKEN_EXPIRED'){session=undefined;location.hash='login';return;}}
  if(g!==generation)return;render();document.querySelector('.statebar')?.remove();
  if(error&&key!=='login'){const el=document.createElement('div');el.innerHTML=note(esc(error),'danger');el.setAttribute('role','alert');document.querySelector('.workspace')?.prepend(el);}
  bind(key);
}
window.addEventListener('hashchange',()=>{error='';draw();});
draw();
