import {orderStatuses} from './order-status.js';
import {mountUserOverview} from './user-overview.js';
import {userEventLabel} from './user-activity.js';
import {reviewWorkspace} from './review-workspace.js';

export const userRoutes=new Set(['user-detail','user-orders','user-cases','user-decisions','user-security']);
const tabs=[['Обзор','user-detail'],['Безопасность','user-security'],['Заказы','user-orders'],['Обращения','user-cases'],['Решения','user-decisions']];
const auditLabels={'verification.passed':'Документ проверен','verification.rejected':'Проверка документа отклонена','security.events_read':'Служебный просмотр безопасности','user.phone_read':'Служебный просмотр контакта','job.retry_requested':'Повторная обработка запрошена','content.approved':'Материал опубликован','content.rejected':'Материал отклонён'};
const titles={'user-detail':'Карточка пользователя','user-orders':'Заказы пользователя','user-cases':'Обращения пользователя','user-decisions':'История решений','user-security':'Безопасность пользователя'};
const statuses={...orderStatuses,open:'Открыто',draft:'Черновик',published:'Опубликовано',in_progress:'В работе',completed:'Завершено',cancelled:'Отменено',resolved:'Решено',closed:'Закрыто',assigned:'Назначено',waiting_support:'Ожидает поддержки',active:'Активен',blocked:'Заблокирован',restricted:'Ограничен',deleted:'Удалён',passed:'Документ проверен',not_started:'Документ не проверен',rejected:'Проверка отклонена'};
const date=value=>value?new Intl.DateTimeFormat('ru',{dateStyle:'short',timeStyle:'short',timeZone:'UTC'}).format(new Date(value))+' UTC':'—';
const route=(key,id,extra={})=>'#'+key+'?'+new URLSearchParams({user_id:id,...extra});

export async function userWorkspace({key,api,esc,card,tablecard,note,badge,namedField,sections,onRefresh,staffAccess}){
 const params=new URLSearchParams(location.hash.split('?')[1]||'');
 const selected=key.startsWith('record-live/users/')?key.split('/')[2]:params.get('user_id');
 const tab=key.startsWith('record-live/')?'user-detail':key;
 if(!selected){
  const query={limit:'20',...(params.get('q')?{q:params.get('q')}:{}),...(params.get('cursor')?{cursor:params.get('cursor')}:{})};
  const data=await api('/admin/users?'+new URLSearchParams(query));
  return {key,id:'A03',title:titles[tab],section:'Пользователи',subtitle:'Выберите аккаунт текущей страны',actions:'',
   body:()=>`<form id="choose-user" class="filters"><input name="q" aria-label="Найти пользователя" value="${esc(params.get('q')||'')}" placeholder="Имя или user ID"><button class="primary">Найти</button></form>${tablecard('Пользователи',['Имя','ID','Город','Состояние',''],data.items.map(u=>[esc(u.display_name||'—'),esc(u.id),esc(u.city||'—'),badge(esc(statuses[u.status]||u.status)),`<a href="${route(tab,u.id)}">Открыть →</a>`]),'',`${data.items.length} записей на странице`)}${data.meta?.next_cursor?`<a class="btn" href="#${tab}?${new URLSearchParams({q:params.get('q')||'',cursor:data.meta.next_cursor})}">Следующая страница</a>`:''}`,
   bind(){document.getElementById('choose-user').onsubmit=e=>{e.preventDefault();location.hash=tab+'?'+new URLSearchParams(new FormData(e.currentTarget));};}};
 }
 const base='/admin/users/'+encodeURIComponent(selected),user=await api(base);
 const status=value=>esc(statuses[value]||value||'—');
 const summary=`<div class="profile-top"><span class="avatar">${esc((user.display_name||'').slice(0,2)||'—')}</span><div><h2>${esc(user.display_name||'—')}</h2><small>${esc(user.id)} · ${esc(user.country)} · ${esc(user.city||'Город не указан')}</small><div class="badges" style="margin-top:7px">${(user.roles||[]).map(role=>badge(esc({customer:'Заказчик',executor:'Исполнитель'}[role]||role))).join('')}${badge(status(user.status),user.status==='active'?'green':'orange')}${badge(status(user.verification),user.verification==='passed'?'green':'')}</div></div></div>`;
 const navigation=`<div class="tabs" aria-label="Разделы пользователя">${tabs.map(([label,page])=>`<a class="tab ${tab===page?'active':''}" href="${route(page,user.id)}">${label}</a>`).join('')}</div>`;
 const pagination=(cursor,name='cursor')=>cursor?`<a class="btn" href="${route(tab,user.id,{[name]:cursor,...(params.get('q')?{q:params.get('q')}:{}),...(params.get('status')?{status:params.get('status')}:{}),...(name==='cases_cursor'&&params.get('support_cursor')?{support_cursor:params.get('support_cursor')}:{}) ,...(name==='support_cursor'&&params.get('cases_cursor')?{cases_cursor:params.get('cases_cursor')}:{})})}">Следующая страница</a>`:'';
 const page={key,id:'A03',title:titles[tab],section:'Пользователи',subtitle:`${user.id} · ${user.country}`,actions:`<a class="btn" href="#users">К списку</a><button id="refresh-data" type="button">Обновить</button>`};
 if(tab==='user-detail'){
  const detail=await reviewWorkspace({key:'record-live/users/'+user.id,api:(path,...args)=>path===base&&!args.length?Promise.resolve(user):api(path,...args),esc,card,note,namedField,sections,onRefresh,staffAccess});
  return {...detail,...page,body:()=>summary+navigation+detail.body()+'<div id="user-overview" class="mt"></div>',bind(){detail.bind();mountUserOverview({user,api,esc,card,staffAccess});}};
 }
 if(tab==='user-orders'){
  const data=await api(base+'/orders?'+new URLSearchParams({limit:'20',...(params.get('q')?{q:params.get('q')}:{}),...(params.get('status')?{status:params.get('status')}:{}),...(params.get('cursor')?{cursor:params.get('cursor')}:{})}));
  const money=r=>{const amount=r.agreed_amount??r.budget_amount;return amount==null?'По договорённости':new Intl.NumberFormat('ru',{style:'currency',currency:r.currency||({KZ:'KZT',KG:'KGS',RU:'RUB',BY:'BYN'}[user.country])}).format(amount/100);};
  return {...page,body:()=>summary+navigation+`<form id="user-order-search" class="filters"><input name="q" aria-label="Поиск по order ID или названию" placeholder="Поиск по order ID или названию" value="${esc(params.get('q')||'')}"><select aria-label="Страна аккаунта" disabled><option>${esc({KZ:'Казахстан',KG:'Кыргызстан',RU:'Россия',BY:'Беларусь'}[user.country]||user.country)}</option></select><select name="status" aria-label="Состояние заказа">${[['','Все состояния'],['open','Открытые'],['in_progress','В работе'],['completed','Завершённые'],['cancelled','Отменённые'],['draft','Черновики']].map(([value,label])=>`<option value="${value}" ${params.get('status')===value?'selected':''}>${label}</option>`).join('')}</select><button type="submit">Найти</button><button type="button" id="user-order-reset">Сбросить</button></form>`+tablecard('Связанные заказы',['ID / название','Роль','Условия','Состояние','Обновлён',''],data.items.map(r=>[`${esc(r.id)}<span class="sub">${esc(r.title)}</span>`,r.role==='customer'?'Заказчик':'Исполнитель',esc(money(r)),badge(status(r.status)),esc(date(r.updated_at||r.created_at)),`<a href="#record-live/orders/${r.id}">Открыть →</a>`]),'',`${data.items.length} записей на странице`)+pagination(data.meta?.next_cursor),bind(){
    document.getElementById('user-order-search').onsubmit=e=>{e.preventDefault();location.hash=route(tab,user.id,{q:String(new FormData(e.currentTarget).get('q')),status:String(new FormData(e.currentTarget).get('status'))});};
    document.getElementById('user-order-reset').onclick=()=>{location.hash=route(tab,user.id);};
   }};
 }
 if(tab==='user-cases'){
  const [cases,support]=await Promise.all([
   api(base+'/cases?'+new URLSearchParams({limit:'20',...(params.get('cases_cursor')?{cursor:params.get('cases_cursor')}:{})})),
   api(base+'/support-threads?'+new URLSearchParams({limit:'20',...(params.get('support_cursor')?{cursor:params.get('support_cursor')}:{})}))]);
  const rows=[...cases.items.map(r=>[esc(r.id),esc(r.reason_code||'Дело'), 'Модерация',badge(status(r.status)),esc(date(r.updated_at||r.created_at)),`<a href="#case-live/${r.id}">Дело →</a>`]),...support.items.map(r=>[esc(r.id),esc(r.subject),'Поддержка',badge(status(r.status)),esc(date(r.updated_at||r.created_at)),`<a href="#support-live/${r.id}">Чат →</a>`])];
  return {...page,body:()=>summary+navigation+tablecard('Связанные дела и поддержка',['Номер','Тема','Тип','Состояние','Обновлено',''],rows,'',`${rows.length} записей на текущих страницах`)+`<div class="actions">${cases.meta?.next_cursor?'<span>Дела</span>'+pagination(cases.meta.next_cursor,'cases_cursor'):''}${support.meta?.next_cursor?'<span>Поддержка</span>'+pagination(support.meta.next_cursor,'support_cursor'):''}</div>`+note('Документы, частные сообщения и данные заявителя не включаются в эту сводку. Доступ к содержимому проверяется при открытии дела или обращения.')};
 }
 if(tab==='user-decisions'){
  const data=await api(base+'/decisions?'+new URLSearchParams({limit:'20',...(params.get('cursor')?{cursor:params.get('cursor')}:{})}));
  return {...page,body:()=>summary+navigation+card('Хронология аккаунта',data.items.length?`<div class="timeline">${data.items.map(r=>`<div class="event"><h3>${esc(auditLabels[r.action]||r.action)}</h3><p>${esc(r.reason)}</p><p class="tiny muted">${esc(r.target_id)} · ${esc(r.actor_id)}</p><time>${esc(date(r.created_at))}</time></div>`).join('')}</div>`:'Решений пока нет')+pagination(data.meta?.next_cursor)+note('История неизменяема. Исправление решения создаёт отдельную запись.')};
 }
 return {...page,body:()=>summary+navigation+note('Данные доступны по правам вашей роли. Просмотр автоматически фиксируется в журнале.')+`<div class="grid split">${card('Контакты и контекст событий',`<div class="kv"><div><label>Телефон</label><b class="protectedvalue">Скрыт</b></div><div><label>Город профиля</label><b>${esc(user.city||'—')} · указан пользователем</b></div><div><label>Проверка</label><b>${status(user.verification)}</b></div></div><p class="helptext">IP не подтверждает адрес проживания. Точные адреса и идентификаторы сессий здесь не раскрываются.</p><a class="btn" href="${route('user-detail',user.id)}">Служебный просмотр контакта</a>`)}${card('Контроль доступа',`<form id="account-security" class="stack"><button class="primary">Загрузить события</button><div role="alert" id="account-security-error"></div></form>`)}</div><div id="account-security-result" class="mt"></div>`,bind(){
   const form=document.getElementById('account-security'),result=document.getElementById('account-security-result'),error=document.getElementById('account-security-error');
   const load=async(reason,cursor)=>{form.querySelector('button').disabled=true;error.textContent='';
    try{const data=await api(base+'/security-events?'+new URLSearchParams({reason,limit:'20',...(cursor?{cursor}:{})}));
     result.innerHTML=tablecard('События безопасности',['Время UTC','Событие','IP события','MFA',''],data.items.map(r=>[esc(date(r.occurred_at||r.created_at)),esc(userEventLabel(r)),esc(r.ip_summary),r.mfa?'Подтверждён':'—',!staffAccess?.managed||staffAccess.grants.includes('POST /admin/security-events/{id}/disclose')?`<button type="button" data-disclose-event="${esc(r.id)}">Показать полный IP</button>`:'']),'',`${data.items.length} записей на странице`)+(data.meta?.next_cursor?'<button type="button" id="account-security-next">Следующая страница</button>':'');
     result.querySelectorAll('[data-disclose-event]').forEach(button=>button.onclick=async()=>{
      button.disabled=true;error.textContent='';
      try{const event=await api('/admin/security-events/'+encodeURIComponent(button.dataset.discloseEvent)+'/disclose','POST',{reason});const value=document.createElement('p');value.setAttribute('role','status');value.textContent='IP: '+(event.ip||'Не записан')+(event.user_agent?' · Устройство: '+event.user_agent:'');button.replaceWith(value);}catch(e){error.textContent=e.message;button.disabled=false;}
     });
     result.querySelectorAll('.cardfoot>span:last-child').forEach(element=>element.remove());
     result.querySelector('#account-security-next')?.addEventListener('click',()=>load(reason,data.meta.next_cursor));
    }catch(e){error.textContent=e.message;}finally{form.querySelector('button').disabled=false;}};
   form.onsubmit=e=>{e.preventDefault();load('Просмотр безопасности в карточке пользователя');};
   load('Просмотр безопасности в карточке пользователя');
  }};
}
