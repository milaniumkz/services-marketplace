import './design.js';

const { routes, page, shell, field, btn, link, top, badge, notice, title, icon } = window.JOBA;
const designMode = new URLSearchParams(location.search).has('design');
const escape = value => String(value ?? '').replace(/[&<>"']/g,c=>({'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;',"'":'&#39;'}[c]));
let session, profile, orders=[], currentOrder, offers=[], conversations=[], currentChat, messages=[], threads=[], projects=[];
let country='KZ', error='', busy=false, draft;
const labels={draft:'Черновик',open:'Открыт',in_progress:'В работе',completion_requested:'Ожидает подтверждения',completed:'Завершён',canceled:'Отменён'};
const money = (amount,currency='KZT') => amount===null?'По договорённости':new Intl.NumberFormat('ru',{style:'currency',currency}).format(amount/100);
const form = (id,body,button) => `<form id="${id}">${body}<button class="btn mt20" ${busy?'disabled':''}>${button}</button></form>`;
const input = (label,name,value='',type='text') => field(label,escape(value),{type}).replace('<input ','<input name="'+name+'" ');
const area = (label,name,value='') => field(label,escape(value),{textarea:true}).replace('<textarea ','<textarea name="'+name+'" ');
const card = o=>`<a class="order-card" href="#order/${o.id}"><div class="row between">${badge(labels[o.status]??o.status)}<span class="tiny muted">${escape(o.city)}</span></div><h3>${escape(o.title)}</h3><p class="small muted">${escape(o.description)}</p><div class="money mt16">${money(o.budget_amount,o.currency)}</div></a>`;
const err = ()=>error?`<div role="alert" class="notice bad mt16">${escape(error)}</div>`:'';
const renderPage = (heading,body,opts={}) => page(heading,body+err(),opts);
async function request(path,{method='GET',body,key=crypto.randomUUID(),token=session?.access_token}={}) {
  const response=await fetch('/api/v1'+path,{method,headers:{'Content-Type':'application/json',...(token?{Authorization:'Bearer '+token}:{}),...(method!=='GET'?{'Idempotency-Key':key}:{})},body:method==='GET'?undefined:JSON.stringify(body??{})});
  const result=await response.json();
  if(!response.ok){const e=Error(result.error?.message??'Сервис недоступен');e.code=result.error?.code;throw e;}
  return result.data;
}
const go = route=>{error='';location.hash=route;};
function activeRoute(){return location.hash.slice(1)||'welcome';}
function registerRoute(id,title,body){routes[id]={id,title,render:body};}
if(!designMode) {
  registerRoute('welcome','Начало',()=>renderPage('Добро пожаловать',`${title('Дела становятся проще','Находите специалистов и заказы в вашем городе.')}
    <img class="brand-img" src="/assets/joba-logo.png" alt="JOBA"><label class="label" for="country">Страна услуг</label><select id="country" class="field"><option value="KZ">Казахстан</option><option value="KG">Кыргызстан</option><option value="RU">Россия</option><option value="BY">Беларусь</option></select>${notice('Среда разработки. Коммерческий запуск стран пока не подтверждён.')}${btn('Войти','login')}${btn('Создать аккаунт','register','outline')}`));
  registerRoute('login','Вход',()=>renderPage('Вход в JOBA',`${title('С возвращением','Вход по телефону и паролю. Без SMS и почты.')}${form('login-form',input('Номер телефона','phone','','tel')+input('Пароль','password','','password'),'Войти')}${btn('Создать аккаунт','register','ghost')}${btn('Помощь со входом','recovery','ghost')}`,{back:'welcome'}));
  registerRoute('register','Регистрация',()=>renderPage('Новый аккаунт',`${title('Добро пожаловать','Телефон — неподтверждённый идентификатор входа.')}${form('register-form',input('Как к вам обращаться','display_name')+input('Номер телефона','phone','','tel')+input('Пароль — не менее 15 символов','password','','password')+input('Повторите пароль','password_repeat','','password'),'Создать аккаунт')}${notice('Не используйте настоящие персональные данные: правовые документы и инфраструктура production не утверждены.')}`,{back:'login'}));
  registerRoute('home','Главная',()=>shell(`<div class="homebar"><div class="row between"><a class="wordmark" href="#home">JOBA<span class="dot"></span></a>${link('account','Мой профиль','role')}</div><p class="location mt8">${escape(profile?.city||country)}</p></div><div class="pad white"><h1>Хорошие мастера.<br><span class="accent">Ваши задачи.</span></h1><div class="categories mt20">${['Ремонт','Уборка','Перевозки','Красота','Обучение','Все услуги'].map(c=>link('catalog',`<div class="cat-icon">${icon('tool')}</div>${c}`,'category')).join('')}</div></div><div class="pad"><div class="hero-card"><h2>Расскажите о задаче</h2><p>Специалисты предложат цену и время</p>${btn('Создать заказ','create','sm')}</div><div class="section-title"><h2>Ваши заказы</h2>${link('orders','Все')}</div><div class="stack">${orders.length?orders.slice(0,3).map(card).join(''):'<p class="muted">Заказов пока нет</p>'}</div>${err()}</div>`,{nav:'home'}));
  registerRoute('orders','Мои заказы',()=>renderPage('Мои заказы',`${btn('Создать заказ','create')}<div class="stack mt20">${orders.length?orders.map(card).join(''):'<p class="muted">Пока нет заказов</p>'}</div>`,{back:'home',nav:'home'}));
  registerRoute('create','Создание заказа',()=>renderPage('Новый заказ',`${badge('Черновик','neutral')}${title('Что нужно сделать?')}${form('create-form',input('Категория','category_id',draft?.category_id??'1')+input('Название','title',draft?.title??'')+area('Опишите задачу','description',draft?.description??'')+input('Город','city',draft?.city??profile?.city??'')+input('Бюджет в валюте страны','budget',draft?.budget??'','number'),'Предпросмотр заказа')}${notice('Точный адрес не публикуется. Цена услуги согласуется сторонами.')}`,{back:'home'}));
  registerRoute('publish','Публикация заказа',()=>renderPage('Проверьте заказ',draft?`${title(escape(draft.title))}<p>${escape(draft.description)}</p><p class="mt16">${escape(draft.city)} · ${escape(draft.budget||'По договорённости')}</p><button id="publish-order" class="btn mt20">Опубликовать заказ</button>${btn('Изменить','create','outline')}`:'<p>Сначала создайте черновик</p>',{back:'create'}));
  registerRoute('account','Мой профиль',()=>renderPage('Мой профиль',`${title(escape(profile?.display_name??''))}<p class="muted">${escape(profile?.city??'')} · ${escape(profile?.country??'')}</p>${badge('Телефон не подтверждён','neutral')}<p class="mt16">${escape(profile?.phone??'')}</p><div class="list mt20">${link('orders','Мои заказы','list-row')}${link('profile-edit','Редактировать профиль','list-row')}${link('portfolio','Портфолио','list-row')}${link('messages','Сообщения','list-row')}${link('support','Поддержка','list-row')}${link('privacy','Приватность','list-row')}${link('my-access','Мой доступ','list-row')}</div><button id="logout" class="btn outline mt20">Выйти</button>`,{back:'home',nav:'account'}));
  registerRoute('profile-edit','Редактирование профиля',()=>renderPage('Мой профиль',form('profile-form',input('Имя','display_name',profile?.display_name)+input('Город','city',profile?.city),'Сохранить'),{back:'account'}));
  registerRoute('support','Поддержка',()=>renderPage('Поддержка JOBA',`${title('Мы рядом','Поддержка доступна без подписки.')}${form('support-form',input('Тема обращения','subject'),'Начать обращение')}<div class="list mt20">${threads.map(t=>link('support-chat/'+t.id,escape(t.subject),'list-row')).join('')||'<p class="muted">Обращений пока нет</p>'}</div>`,{back:'account'}));
  registerRoute('recovery','Помощь со входом',()=>renderPage('Помощь со входом',`${notice('Не отправляйте пароль, PIN или документ. Обращение не даёт доступ к аккаунту.')}${form('recovery-form',input('Тема','subject')+area('Как мы можем помочь?','text'),'Создать приватное обращение')}`,{back:'login'}));
  registerRoute('privacy','Приватность',()=>renderPage('Ваши данные',`${notice('Запрос создаётся в очереди. Экспорт и удаление не объявляются выполненными до обработки.')}${form('privacy-form','<label class="label">Тип запроса</label><select name="type" class="field"><option value="export">Экспорт данных</option><option value="delete">Удаление аккаунта</option></select>'+input('Текущий пароль','current_password','','password'),'Создать запрос')}`,{back:'account'}));
  registerRoute('messages','Сообщения',()=>renderPage('Сообщения',`<div class="list">${conversations.map(c=>link('chat/'+c.id,`Чат заказа · ${escape(c.status)}`,'list-row')).join('')||'<p class="muted">Чатов пока нет. Чат создаётся вместе с откликом.</p>'}</div>`,{back:'home',nav:'messages'}));
  registerRoute('catalog','Специалисты',()=>renderPage('Специалисты',notice('Каталог запрашивается с серверной проверкой действующего доступа. Реальные карточки появятся после проверки исполнителей.'),{back:'home',nav:'catalog'}));
  registerRoute('jobs','Заказы для исполнителя',()=>renderPage('Открытые заказы','<div id="job-list" class="stack"></div>',{back:'home'}));
  registerRoute('my-access','Мой доступ',()=>renderPage('Доступ',notice('Платежи и rewarded-реклама закрыты до подтверждения провайдера и country gate. Не вводите данные карты.'),{back:'account'}));
  registerRoute('portfolio','Портфолио',()=>renderPage('Мои проекты',`${form('portfolio-form',input('Название проекта','title')+area('Описание','description')+input('Категория','category_id','1'),'Сохранить черновик')}<div class="stack mt20">${projects.map(p=>`<div class="card"><h3>${escape(p.title)}</h3><p>${escape(p.description)}</p>${badge(p.status)}</div>`).join('')}</div>`,{back:'account'}));
}
function orderPage(o) {
  const own=o.owner===profile?.id,assigned=o.executor_id===profile?.id;
  let actions='';
  if(o.status==='open'&&own)actions=`<h2 class="mt24">Отклики</h2><div class="stack mt16">${offers.map(f=>`<div class="card"><p>${escape(f.text)}</p><strong>${money(f.amount,f.currency)}</strong>${btn('Открыть чат','chat/'+f.conversation_id,'outline')}<button class="btn mt16 select-offer" data-offer="${f.id}">Выбрать исполнителя</button></div>`).join('')||'<p class="muted">Пока нет откликов</p>'}</div>`;
  if(o.status==='open'&&!own)actions=form('offer-form',area('Ваше предложение','text')+input('Цена','amount','','number'),'Отправить отклик');
  if(o.status==='in_progress'&&assigned)actions='<button id="request-completion" class="btn mt20">Работа выполнена</button>';
  if(o.status==='completion_requested'&&own)actions='<button id="confirm-completion" class="btn mt20">Принять работу</button>';
  if(o.status==='completed')actions=form('review-form',input('Оценка от 1 до 5','rating','5','number')+area('Отзыв','text'),'Оставить отзыв');
  return renderPage('Заказ',`${badge(labels[o.status]??o.status)}${title(escape(o.title))}<p>${escape(o.description)}</p><div class="card mt20"><p>${escape(o.city)}</p><strong>${money(o.budget_amount,o.currency)}</strong></div>${actions}${btn('Мои сообщения','messages','outline')}`,{back:'orders'});
}
function chatPage(support=false) {
  return shell(messages.map(m=>`<div class="bubble ${m.owner===profile?.id?'mine':''}">${escape(m.text)}<div class="time">${escape(new Date(m.created_at).toLocaleTimeString('ru',{hour:'2-digit',minute:'2-digit'}))} · ${escape(m.delivery_state??'sent')}</div></div>`).join('')+err(),{cls:'chat-scroll',header:top(support?'Поддержка JOBA':'Чат заказа',support?'support':'messages'),bottom:'<form class="composer" id="live-chat"><input name="text" aria-label="Сообщение" placeholder="Сообщение" maxlength="3000" required><button class="iconbtn send" aria-label="Отправить">'+icon('send')+'</button></form>'});
}
async function load(route) {
  if(!session || ['login','register','welcome','recovery'].includes(route))return;
  profile=await request('/me');
  if(['home','orders'].includes(route))orders=(await request('/me/orders')).items;
  if(route==='support')threads=(await request('/me/support-threads')).items;
  if(route==='messages')conversations=(await request('/me/conversations')).items;
  if(route==='portfolio')projects=(await request('/me/portfolio-projects')).items;
  if(route.startsWith('order/')) {
    currentOrder=await request('/orders/'+route.split('/')[1]);
    offers=currentOrder.owner===profile.id?(await request('/orders/'+currentOrder.id+'/offers')).items:[];
    routes[route]={title:currentOrder.title,render:()=>orderPage(currentOrder)};
  }
  if(route.startsWith('chat/')||route.startsWith('support-chat/')) {
    currentChat=route.split('/')[1];const support=route.startsWith('support-chat/');
    messages=(await request((support?'/support/threads/':'/conversations/')+currentChat+'/messages')).items;
    routes[route]={title:'Чат',render:()=>chatPage(support)};
  }
}
function bindForm(id,callback) {
  const el=document.getElementById(id);if(!el)return;
  el.onsubmit=async e=>{e.preventDefault();if(busy)return;busy=true;const values=Object.fromEntries(new FormData(el));
    el.querySelector('button[type=submit],button:last-child')?.setAttribute('disabled','');
    try{error='';await callback(values);}catch(e){error=e.message;const alert=document.createElement('p');alert.className='field-error';alert.role='alert';alert.textContent=error;el.append(alert);}finally{busy=false;el.querySelector('button[type=submit],button:last-child')?.removeAttribute('disabled');}};
}
function command(id,callback){const el=document.getElementById(id);if(el)el.onclick=async()=>{if(busy)return;busy=true;el.disabled=true;try{error='';await callback();}catch(e){error=e.message;await draw(false);}finally{busy=false;el.disabled=false;}};}
function bind(route) {
  document.getElementById('country')?.addEventListener('change',e=>country=e.target.value);
  bindForm('login-form',async b=>{session=await request('/auth/login',{method:'POST',body:{...b,country}});profile=session.user;go('home');});
  bindForm('register-form',async b=>{if(b.password!==b.password_repeat)throw Error('Пароли не совпадают');session=await request('/auth/register',{method:'POST',body:{...b,country}});profile=session.user;go('account');});
  bindForm('create-form',async b=>{draft=b;go('publish');});
  command('publish-order',async()=>{const amount=draft.budget===''?null:Math.round(Number(draft.budget)*100);const o=await request('/orders',{method:'POST',body:{...draft,budget_amount:amount}});await request('/orders/'+o.id+'/publish',{method:'POST',body:{expected_version:o.version}});draft=undefined;go('orders');});
  bindForm('profile-form',async b=>{const me=await request('/me');await request('/me',{method:'PATCH',body:{...b,expected_version:me.version}});go('account');});
  bindForm('support-form',async b=>{const t=await request('/support/threads',{method:'POST',body:b});go('support-chat/'+t.id);});
  bindForm('recovery-form',async b=>{const t=await request('/public/recovery-threads',{method:'POST',body:{...b,country}});error='Обращение создано: '+t.id+'. Сохраните эту вкладку для продолжения.';await draw(false);});
  bindForm('privacy-form',async b=>{const t=await request('/me/privacy-requests',{method:'POST',body:b});error='Запрос создан. Статус: '+t.status;await draw(false);});
  bindForm('portfolio-form',async b=>{await request('/me/portfolio-projects',{method:'POST',body:b});await draw();});
  bindForm('offer-form',async b=>{await request('/orders/'+currentOrder.id+'/offers',{method:'POST',body:{text:b.text,amount:Math.round(Number(b.amount)*100),acknowledged_revision:currentOrder.revision}});go('messages');});
  document.querySelectorAll('.select-offer').forEach(el=>el.onclick=async()=>{const f=offers.find(x=>x.id===el.dataset.offer);if(!confirm('Выбрать исполнителя и закрепить условия отклика?'))return;try{await request('/orders/'+currentOrder.id+'/select',{method:'POST',body:{expected_version:currentOrder.version,offer_id:f.id,offer_version:f.version}});await draw();}catch(e){error=e.message;await draw(false);}});
  command('request-completion',async()=>{await request('/orders/'+currentOrder.id+'/complete',{method:'POST',body:{expected_version:currentOrder.version}});await draw();});
  command('confirm-completion',async()=>{if(!confirm('Подтверждаете, что работа выполнена?'))return;await request('/orders/'+currentOrder.id+'/confirm-completion',{method:'POST',body:{expected_version:currentOrder.version}});await draw();});
  bindForm('review-form',async b=>{await request('/reviews',{method:'POST',body:{...b,rating:Number(b.rating),order_id:currentOrder.id}});error='Отзыв сохранён. Он публикуется после взаимного отзыва.';await draw(false);});
  bindForm('live-chat',async b=>{const path=route.startsWith('support-chat/')?'/support/threads/':'/conversations/';await request(path+currentChat+'/messages',{method:'POST',body:{text:b.text,client_message_id:crypto.randomUUID()}});await draw();});
  command('logout',async()=>{await request('/auth/logout',{method:'POST'});session=undefined;profile=undefined;go('login');});
  if(route==='catalog')request('/contractors').then(r=>{const el=document.querySelector('main .pad');el.insertAdjacentHTML('beforeend',r.items.length?r.items.map(p=>`<div class="pro-card"><h3>${escape(p.title)}</h3><p>${escape(p.description)}</p></div>`).join(''):'<p class="muted mt20">Специалистов пока нет</p>');}).catch(e=>{document.querySelector('main .pad').insertAdjacentHTML('beforeend',`<div role="alert" class="notice warn mt20">${escape(e.message)}</div>`);});
  if(route==='jobs')request('/orders').then(r=>{document.getElementById('job-list').innerHTML=r.items.map(card).join('')||'<p>Нет открытых заказов</p>';}).catch(e=>{document.getElementById('job-list').textContent=e.message;});
}
let generation=0;
async function draw(reload=true) {
  const route=activeRoute(),g=++generation;
  if(designMode){window.JOBA.render();return;}
  if(!session&&!['welcome','register','login','recovery'].includes(route)){go('login');return;}
  try{if(reload)await load(route);}catch(e){error=e.message;if(e.code==='TOKEN_EXPIRED'){session=undefined;go('login');return;}}
  if(g!==generation)return;
  if(!routes[route]){routes[route]={title:'Экран',render:()=>renderPage('Экран недоступен',notice('Этот сценарий ещё не подключён к API.'),{back:'home'})};}
  window.JOBA.render();bind(route);
}
window.addEventListener('hashchange',()=>draw());
window.addEventListener('offline',()=>{error='Нет сети. Публикация, оплата и отправка недоступны.';draw(false);});
window.addEventListener('online',()=>{error='';draw();});
draw();
