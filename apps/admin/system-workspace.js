const names={KZ:'Казахстан',KG:'Кыргызстан',RU:'Россия',BY:'Беларусь'};
const states={requested:'В очереди',pending:'Ожидание',retry:'Повтор запланирован',processing:'Обработка',scanning:'Проверка файла',sending:'Отправка',sent:'Доставлено',ready:'Готово',completed:'Завершено',failed:'Ошибка',dead_letter:'Требует разбора',clean:'Проверен',rejected:'Отклонён',infected:'Заблокирован',expired:'Срок истёк'};
const date=value=>value?new Intl.DateTimeFormat('ru',{dateStyle:'short',timeStyle:'short',timeZone:'UTC'}).format(new Date(value)):'—';
function chart(rows,esc){
 const maximum=Math.max(3,...rows.flatMap(row=>[row.published,row.completed]));
 const points=key=>rows.map((row,index)=>`${35+index*585/Math.max(1,rows.length-1)},${146-row[key]*126/maximum}`).join(' ');
 const interval=Math.max(1,Math.ceil(rows.length/7));
 return `<svg class="chart" viewBox="0 0 640 185" role="img" aria-label="Опубликованные и завершённые заказы по дням UTC"><g stroke="#EBEFF6"><path d="M34 20H620M34 62H620M34 104H620M34 146H620"/></g>${[0,1,2,3].map(index=>`<text x="0" y="${24+index*42}">${Math.round(maximum*(3-index)/3)}</text>`).join('')}<polyline fill="none" stroke="#245BDB" stroke-width="2.5" points="${points('published')}"/><polyline fill="none" stroke="#7F8CA4" stroke-width="2" points="${points('completed')}"/>${rows.filter((_,index)=>index%interval===0||index===rows.length-1).map(row=>`<text x="${35+rows.indexOf(row)*585/Math.max(1,rows.length-1)}" y="177" text-anchor="middle">${esc(row.day.slice(5))}</text>`).join('')}</svg>`;
}
function exportSummary(data){
 const blob=new Blob([JSON.stringify(data,null,2)],{type:'application/json;charset=utf-8'}),url=URL.createObjectURL(blob),link=document.createElement('a');
 link.href=url;link.download=`JOBA-${data.country}-${data.server_time.slice(0,10)}.json`;link.click();setTimeout(()=>URL.revokeObjectURL(url),1000);
}
export async function systemWorkspace({key,api,esc,card,tablecard,note,metric,badge,onRefresh}){
 if(key==='analytics'){
  const params=new URLSearchParams(location.hash.split('?')[1]||''),days=params.get('days')||'7';
  const data=await api('/admin/analytics?'+new URLSearchParams({days})),f=data.funnel;
  const percent=value=>value===null?'—':new Intl.NumberFormat('ru',{style:'percent',maximumFractionDigits:1}).format(value);
  const labels={published:'Опубликован заказ',with_offer:'Получен хотя бы один отклик',selected:'Выбран исполнитель',completed:'Завершён заказ',mutual_review:'Получен взаимный отзыв'};
  return {key,id:'A02.analytics',title:'Аналитика продукта',section:'Обзор',subtitle:'Агрегированные показатели текущей страны, без персональных данных.',actions:'<button id="analytics-export">Экспорт сводки</button>',
   body:()=>`<div class="filters"><span>${esc(names[data.country]||data.country)}</span><select id="analytics-period" aria-label="Период аналитики">${[7,30,90].map(n=>`<option value="${n}" ${data.days===n?'selected':''}>Последние ${n} дней</option>`).join('')}</select><span>UTC · ${esc(data.from.slice(0,10))} — ${esc(data.server_time.slice(0,10))}</span></div><div class="grid cols4">${metric('Выбор исполнителя',percent(data.rates.selection),`${f.selected} / ${f.published}`,'заказов когорты')}${metric('Завершение',percent(data.rates.completion),`${f.completed} / ${f.published}`,'заказов когорты')}${metric('Обращения',percent(data.rates.cases),`${f.with_case} / ${f.published}`,'заказов с обращением')}${metric('Взаимные отзывы',f.mutual_review,'Опубликованы','обоими участниками')}</div><div class="grid split mt">${card('Воронка заказа',`<div class="stack">${Object.entries(labels).map(([k,label])=>`<div><div class="row tiny" style="margin-bottom:8px"><span>${label}</span><b data-funnel="${k}">${f[k]}</b></div><div class="progress"><i style="width:${f.published?Math.min(100,f[k]*100/f.published):0}%"></i></div></div>`).join('')}</div>`)}${card('Определения',Object.entries(data.definitions).map(([k,text])=>`<div class="event"><b>${esc(({cohort:'Когорта',series:'Динамика',...labels,with_case:'Обращения'})[k]||k)}</b><p>${esc(text)}</p></div>`).join(''))}</div><div class="mt">${card('Динамика заказов',chart(data.series,esc),'<a href="#dashboard">Операционный обзор →</a>')}</div>${note('Проценты рассчитаны от опубликованных за выбранный период заказов. Пустая когорта обозначается «—». Доход и возвраты провайдеров не подменяются оценками.')}`,
   bind(){document.getElementById('analytics-period').onchange=e=>{location.hash='analytics?days='+e.target.value;};document.getElementById('analytics-export').onclick=()=>exportSummary(data);}};
 }
 if(key==='dashboard'){
  const params=new URLSearchParams(location.hash.split('?')[1]||''),days=params.get('days')||'7';
  const data=await api('/admin/dashboard?'+new URLSearchParams({days}));
  return {key,id:'A02',title:'Обзор платформы',subtitle:`${names[data.country]} · ${date(data.server_time)} UTC`,section:'Обзор',
   actions:'<button id="dashboard-export" type="button">Экспорт сводки</button>',
   body:()=>`<div class="filters"><span>${esc(names[data.country])}</span><select id="dashboard-period" aria-label="Период"><option value="7">Последние 7 дней</option><option value="30">Последние 30 дней</option><option value="90">Последние 90 дней</option></select><span class="resultcount">UTC · ${esc(data.from.slice(0,10))} — ${esc(data.server_time.slice(0,10))}</span></div>
    <div class="grid cols4">${metric('Активные пользователи',data.active_users,'','За выбранный период','users')}${metric('Опубликованные заказы',data.published_orders,'','За выбранный период','briefcase')}${metric('Завершено заказов',data.completed_orders,'','За выбранный период','check')}${metric('Активные подписки',data.active_subscriptions,'','Подтверждены провайдером','credit')}</div>
    <div class="grid split mt">${card(`Заказы за последние ${data.days} дней`,chart(data.series,esc),'<div class="legend"><span>Опубликовано</span><span class="gray">Завершено</span></div>')}${card('Требует внимания',`<div class="lineitem"><div><b>Документы на проверке</b><p>Ожидают решения сотрудника</p></div><div class="tail"><h2>${data.attention.verifications}</h2><a href="#verification">Открыть →</a></div></div><div class="lineitem"><div><b>Поддержка</b><p>${data.attention.unassigned_support} без назначения</p></div><div class="tail"><h2>${data.attention.support}</h2><a href="#support">Открыть →</a></div></div><div class="lineitem"><div><b>Задачи доставки</b><p>Ожидают отправки или повторной обработки</p></div><div class="tail"><h2>${data.attention.outbox}</h2><a href="#jobs">Проверить →</a></div></div>`)}</div>
    <div class="grid split mt">${tablecard('Доход рекламы',['Источник','Предварительно','Подтверждено','Сверка'],[],'<a href="#monetization">Настройки рекламы →</a>','Отчёты рекламной сети ещё не поступили.')}${card('Качество сервиса',`<div class="info-row"><span>Открытых обращений по нарушениям</span><b>${data.attention.cases}</b></div><div class="info-row"><span>Аккаунты в текущей стране</span><b>${data.users}</b></div><div class="info-row"><span>Заказы, все состояния</span><b>${data.orders}</b></div>`)}</div>
    <div class="state-footer"><button id="metric-definitions" type="button">Определения всех метрик</button><div id="metric-definitions-result" hidden>${Object.entries(data.definitions).map(([name,value])=>`<p><b>${esc(({active_users:'Активные пользователи',published_orders:'Опубликованные заказы',completed_orders:'Завершённые заказы',active_subscriptions:'Активные подписки'})[name]||name)}</b>: ${esc(value)}</p>`).join('')}</div></div>`,
   bind(){const period=document.getElementById('dashboard-period');period.value=String(data.days);period.onchange=()=>{location.hash='dashboard?days='+period.value;};
    document.getElementById('dashboard-export').onclick=()=>exportSummary(data);
    document.getElementById('metric-definitions').onclick=()=>{const result=document.getElementById('metric-definitions-result');result.hidden=!result.hidden;};}};
 }
 if(key==='security'){
  const params=new URLSearchParams(location.hash.split('?')[1]||'');
  const data=await api('/admin/security-events?'+params);
  const rows=data.items.map(event=>[esc(date(event.occurred_at||event.created_at)),esc(event.event),esc(event.owner),esc(event.ip_summary),badge(event.mfa?'MFA':'Без MFA',event.mfa?'green':'')]);
  return {key,id:'A12',title:'События безопасности',subtitle:'Входы и изменение доступа в текущей стране',section:'Система',actions:'<button id="refresh-system">Обновить</button>',
   body:()=>`<form id="system-filter" class="filters"><input name="q" aria-label="Поиск события" placeholder="ID, аккаунт или тип события" value="${esc(params.get('q'))}"><button>Найти</button><button id="system-reset" type="button">Сбросить</button></form>${tablecard('События безопасности',['Время UTC','Событие','Аккаунт','IP · сокращённо','Второй фактор'],rows,'',`${rows.length} записей`)}${data.meta?.next_cursor?'<button id="system-next">Следующая страница</button>':''}${note('Полные сведения по аккаунту просматриваются по отдельной служебной причине с аудитом.')}`,
   bind(){document.getElementById('refresh-system').onclick=onRefresh;
    document.getElementById('system-filter').onsubmit=event=>{event.preventDefault();location.hash='security?'+new URLSearchParams(new FormData(event.currentTarget));};
    document.getElementById('system-reset').onclick=()=>{location.hash='security';};
    const next=document.getElementById('system-next');if(next)next.onclick=()=>{params.set('cursor',data.meta.next_cursor);location.hash='security?'+params;};}};
 }
 if(key==='job-detail'){
  const params=new URLSearchParams(location.hash.split('?')[1]||''),id=params.get('job_id');
  if(!id){const data=await api('/admin/jobs?'+new URLSearchParams({limit:'20',...(params.get('cursor')?{cursor:params.get('cursor')}:{})}));
   return {key,id:'A15.retry',title:'Карточка задачи',section:'Система',subtitle:'Выберите задачу текущей страны',actions:'<a class="btn" href="#jobs">К списку</a>',body:()=>tablecard('Задачи',['ID','Тип','Состояние',''],data.items.map(job=>[esc(job.id),esc(job.type),badge(esc(states[job.status]||job.status)),`<a href="#job-detail?job_id=${job.id}">Открыть →</a>`]),'',`${data.items.length} записей на странице`)+(data.meta?.next_cursor?`<a class="btn" href="#job-detail?${new URLSearchParams({cursor:data.meta.next_cursor})}">Следующая страница</a>`:'')};}
  const job=await api('/admin/jobs/'+encodeURIComponent(id));
  const eligible=job.source_kind==='privacy'&&job.status==='failed'||job.source_kind==='outbox'&&['dead_letter','retry'].includes(job.status)||job.source_kind==='upload'&&['processing','rejected'].includes(job.status)&&['SCANNER_UNAVAILABLE','PDF_SANITIZER_UNAVAILABLE','FILE_PROCESSING_UNAVAILABLE'].includes(job.failure_code);
  return {key,id:'A15.retry',title:'Карточка задачи',section:'Система',subtitle:job.id,actions:'<a class="btn" href="#jobs">К списку</a><button id="refresh-system">Обновить</button>',
   body:()=>`<div class="grid cols4">${metric('Состояние',esc(states[job.status]||job.status),'','Текущее состояние')}${metric('Попытки',job.attempts,'','По данным обработчика')}${metric('Ревизия',job.version,'','Контроль параллельных действий')}${metric('Тип',esc(job.type),'','Серверная задача')}</div><div class="grid split mt">${card('Сведения',`<div class="info-row"><span>Следующая попытка UTC</span><b>${esc(date(job.next_attempt_at))}</b></div><div class="info-row"><span>Захват обработчиком до UTC</span><b>${esc(date(job.lease_until))}</b></div><div class="info-row"><span>Создано UTC</span><b>${esc(date(job.created_at))}</b></div><div class="info-row"><span>Код ошибки</span><b>${esc(job.failure_code||'—')}</b></div>${note('Приватный payload, документы, токены и пользовательские файлы в карточку задачи не включаются.')}`)}${card('Повторная обработка',eligible?'<form id="detail-retry" class="stack"><label for="detail-retry-reason">Служебная причина</label><textarea id="detail-retry-reason" name="reason" minlength="10" maxlength="1000" required></textarea><button class="primary">Поставить повтор в очередь</button><div role="alert"></div></form>':note('Повторная обработка для текущего состояния недоступна.'))}</div>`,
   bind(){document.getElementById('refresh-system').onclick=onRefresh;const form=document.getElementById('detail-retry');if(form)form.onsubmit=async e=>{e.preventDefault();form.querySelector('button').disabled=true;form.querySelector('[role=alert]').textContent='';
    try{await api('/admin/jobs/'+encodeURIComponent(job.id)+'/retry','POST',{reason:String(new FormData(form).get('reason')),expected_version:job.version});await onRefresh();}
    catch(error){form.querySelector('[role=alert]').textContent=error.message;form.querySelector('button').disabled=false;}};}};
 }
 if(key==='jobs'||key==='scheduled'){
  const params=new URLSearchParams(location.hash.split('?')[1]||'');
  if(key==='scheduled')params.set('scheduled','true');
  const data=await api('/admin/jobs?'+params);
  return {key,id:'A15',title:key==='scheduled'?'Запланированные задачи':'Jobs и интеграции',subtitle:'Асинхронная обработка в текущей стране',section:'Система',actions:'<button id="refresh-system">Обновить</button>',
   body:()=>`<div class="tabs"><a href="#jobs" class="${key==='jobs'?'active':''}">Все задачи</a><a href="#scheduled" class="${key==='scheduled'?'active':''}">Запланированные</a></div><div class="grid cols4">${metric(key==='scheduled'?'Запланировано':'В очереди',key==='scheduled'?data.counts.scheduled:data.counts.queued,'','Сохранены для обработки')}${metric('Выполняется',data.counts.running,'','Активная обработка')}${metric('Требует разбора',data.counts.failed,'','Ошибки и отложенные повторы')}${metric('Платёжных адаптеров',data.providers.billing.length,'','Зарегистрированы на сервере')}</div>
    <form id="system-filter" class="filters"><input name="q" aria-label="Поиск задачи" placeholder="ID или тип задачи" value="${esc(params.get('q'))}"><input name="status" aria-label="Статус задачи" placeholder="Статус" value="${esc(params.get('status'))}"><button>Найти</button><button id="system-reset" type="button">Сбросить</button></form>
    ${tablecard('Задачи и повторная обработка',['Job / тип','Попытки','Следующий запуск UTC','Состояние','Результат'],data.items.map(job=>[`<a href="#job-detail?job_id=${job.id}"><b>${esc(job.type)}</b></a><span class="sub">${esc(job.id)}</span>`,esc(job.attempts),esc(date(job.next_attempt_at)),badge(esc(states[job.status]||job.status)),`${esc(job.failure_code||'—')}${['failed','dead_letter','retry'].includes(job.status)||job.failure_code?` <button type="button" data-job="${job.id}">Проверить повтор</button>`:''}`]),'',`${data.items.length} записей`)}
    ${data.meta?.next_cursor?'<button id="system-next">Следующая страница</button>':''}
    <div id="job-review"></div>${card('Подключения',`<div class="info-row"><span>Push</span><b>${data.providers.push_configured?'Адаптер настроен':'Не подключён'}</b></div><div class="info-row"><span>Проверка файлов</span><b>${data.providers.scanner_configured?'Адаптер настроен':'Не подключён'}</b></div><div class="info-row"><span>PDF</span><b>${data.providers.pdf_sanitizer_configured?'Адаптер настроен':'Не подключён'}</b></div>`)}`,
   bind(){document.getElementById('refresh-system').onclick=onRefresh;
    document.getElementById('system-filter').onsubmit=event=>{event.preventDefault();location.hash=key+'?'+new URLSearchParams(new FormData(event.currentTarget));};
    document.querySelectorAll('[data-job]').forEach(button=>button.onclick=()=>{
      const job=data.items.find(item=>item.id===button.dataset.job),panel=document.getElementById('job-review');
      panel.innerHTML=card('Повторная обработка',`<form id="retry-job" class="stack"><p>${esc(job.type)} · ${esc(job.id)}</p><label for="retry-reason">Служебная причина</label><textarea id="retry-reason" name="reason" minlength="10" required></textarea><button class="primary">Поставить повтор в очередь</button><div role="alert"></div></form>`);
      panel.querySelector('form').onsubmit=async event=>{event.preventDefault();const form=event.currentTarget,reason=new FormData(form).get('reason');form.querySelector('button').disabled=true;
        try{await api('/admin/jobs/'+job.id+'/retry','POST',{expected_version:job.version,reason});await onRefresh();}
        catch(error){form.querySelector('[role=alert]').textContent=error.message;form.querySelector('button').disabled=false;}
      };panel.scrollIntoView({block:'nearest'});
    });
    document.getElementById('system-reset').onclick=()=>{location.hash=key;};const next=document.getElementById('system-next');if(next)next.onclick=()=>{params.set('cursor',data.meta.next_cursor);location.hash=key+'?'+params;};}};
 }
 throw Error('Неизвестный системный раздел');
}
