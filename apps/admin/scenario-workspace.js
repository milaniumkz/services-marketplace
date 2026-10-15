// Live state views. Every selection and preview uses the current regional API.
export const scenarioRoutes=new Set(['legal-holds','bulk-preview','bulk-result','revision-conflict','revenue','blacklist-detail','security-full','languages','dictionary-dryrun','promo-preview','referral-preview','monetization-preview','promo','rewarded','archive','country-detail','verification-review','id-auth','deletion','banner-detail','push-compose']);
export async function scenarioWorkspace({key,api,esc,card,tablecard,note,namedField,onRefresh}){
 const params=new URLSearchParams(location.hash.split('?')[1]||'');
 const result=(title,body,bind=()=>{})=>({key,id:'',title,subtitle:'Текущая страна · данные API',section:'Управление',actions:'<button id="refresh-data">Обновить</button>',body:()=>body,bind});
 const output=data=>`<pre class="result" role="status">${esc(JSON.stringify(data,null,2))}</pre>`;
 const wire=(selector,send)=>{const form=document.querySelector(selector);if(!form)return;form.onsubmit=async e=>{e.preventDefault();const values=Object.fromEntries(new FormData(form));const buttons=[...form.querySelectorAll('button')];buttons.forEach(b=>b.disabled=true);try{const data=await send(values);form.querySelector('[role=status]').textContent=JSON.stringify(data,null,2);}catch(error){form.querySelector('[role=alert]').textContent=error.message;}finally{buttons.forEach(b=>b.disabled=false);}};};
 const alerts='<div role="alert"></div><pre role="status"></pre>';
 const selection=async(endpoint,label)=>{
  const data=await api(endpoint+'?'+new URLSearchParams({limit:'100',...(params.get('status')?{status:params.get('status')}:{})}));
  if(key==='deletion')data.items=data.items.filter(r=>r.type==='delete');
  const record=data.items.find(r=>r.id===params.get('id'));
  const picker=`<form id="scenario-picker" class="filters"><label>Выберите запись<select name="id"><option value="">Выберите запись</option>${data.items.map(r=>`<option value="${esc(r.id)}" ${r.id===record?.id?'selected':''}>${esc(r.title??r.display_name??r.id)} · ${esc(r.status??'')}</option>`).join('')}</select></label><button>Открыть</button></form>${data.items.length?'':note('В этой стране нет записей для выбранного состояния.')} ${data.meta?.next_cursor?`<p class="muted">Показаны первые 100 записей. Для остальных используйте основной список и ID.</p>`:''}`;
  return {record,picker,bind(){document.getElementById('scenario-picker').onsubmit=e=>{e.preventDefault();const id=new FormData(e.currentTarget).get('id');if(id)location.hash=key+'?id='+encodeURIComponent(id);};}};
 };
 if(key==='legal-holds'){
  const data=await api('/admin/legal-holds?limit=100');
  return result('Законное удержание данных',card('Конкретные данные и основание',`<form id="hold-create" class="stack">${namedField('ID записи','target_id')}${namedField('Поля через запятую: file, document_refs, upload_ids, photos или gallery_ids','fields')}${namedField('Объяснение для пользователя','basis','textarea')}${namedField('Внутреннее основание','reason','textarea')}${namedField('Дата пересмотра (UTC)','review_at','datetime-local')}<button class="primary">Зафиксировать удержание</button>${alerts}</form>`)+data.items.map(r=>card('Удержание '+esc(r.id),`<p>${esc(r.basis)}</p><p>${esc(r.status)} · пересмотр ${esc(r.review_at)}</p>${r.status==='active'?`<form data-release-hold="${esc(r.id)}" class="stack">${namedField('Основание снятия','reason','textarea')}<button>Снять удержание</button>${alerts}</form>`:''}`)).join(''),()=>{wire('#hold-create',async v=>{const r=await api('/admin/legal-holds','POST',{...v,fields:v.fields.split(',').map(x=>x.trim()).filter(Boolean),review_at:new Date(v.review_at+'Z').toISOString()});await onRefresh();return r;});document.querySelectorAll('[data-release-hold]').forEach(form=>{const r=data.items.find(x=>x.id===form.dataset.releaseHold);wire('[data-release-hold="'+r.id+'"]',async v=>{const result=await api('/admin/legal-holds/'+r.id+'/release','POST',{...v,expected_version:r.version});await onRefresh();return result;});});});
 }
 if(key==='bulk-preview'){
  const profiles=await api('/admin/contractors?limit=100');
  return result('Массовое изменение профилей',card('Выбор записей',`<form id="bulk-preview" class="stack"><label>Действие<select name="action"><option value="pause_contractors">Приостановить публикацию</option><option value="resume_contractors">Возобновить публикацию</option></select></label>${profiles.items.map(r=>`<label class="row"><input type="checkbox" name="ids" value="${esc(r.id)}">${esc(r.title??r.id)} · ${esc(r.status)}</label>`).join('')}${namedField('Основание операции','reason','textarea')}<button class="primary">Рассчитать влияние</button>${alerts}</form>`),()=>wire('#bulk-preview',async v=>{const form=document.getElementById('bulk-preview');const job=await api('/admin/bulk/preview','POST',{action:v.action,reason:v.reason,ids:new FormData(form).getAll('ids')});location.hash='bulk-result?id='+encodeURIComponent(job.id);return job;}));
 }
 if(key==='bulk-result'){
  if(!params.get('id'))return result('Результат операции',note('Операция ещё не выбрана.')+'<a class="btn primary" href="#bulk-preview">Создать предпросмотр</a>');
  const job=await api('/admin/bulk/'+encodeURIComponent(params.get('id')));
  return result(job.status==='previewed'?'Подтверждение операции':'Результат операции',card('Снимок выбора',`<p>Записей: ${job.snapshot.length} · обработано: ${job.processed} · ${esc(job.status)}</p>${tablecard('Состав операции',['ID','Версия','Результат'],job.snapshot.map(r=>[esc(r.id),r.version,esc(job.results.find(x=>x.id===r.id)?.code??job.results.find(x=>x.id===r.id)?.status??'Ожидает подтверждения')]))}${job.status==='previewed'?`<form id="bulk-execute" class="stack"><label><input type="checkbox" name="confirm" required>Проверил состав и подтверждаю изменение</label>${namedField('Основание подтверждения','reason','textarea')}<button class="primary">Выполнить операцию</button>${alerts}</form>`:''}`)+'<a class="btn" href="#bulk-preview">Новая операция</a>',()=>wire('#bulk-execute',async v=>{const data=await api('/admin/bulk/'+job.id+'/execute','POST',{reason:v.reason,confirm:v.confirm==='on',expected_version:job.version});await onRefresh();return data;}));
 }
 if(key==='revision-conflict'){
  const s=await selection('/admin/cases','Дело');
  const current=s.record?await api('/admin/cases/'+s.record.id):null;
  return result('Актуальная версия записи',s.picker+(current?card('Текущие условия',`<p>Версия ${current.version}. Отменённая команда не повторяется автоматически.</p><p>${esc(current.description??current.reason_code)}</p><a class="btn primary" href="#case-live/${esc(current.id)}">Перечитать и принять решение</a>`):''),()=>s.bind());
 }
 if(key==='revenue'){
  const days=params.get('days')||'30',data=await api('/admin/revenue?days='+days);
  return result('Доход рекламных сетей',`<form id="revenue-period" class="filters"><label>Период<select name="days">${[7,30,90].map(n=>`<option ${String(n)===days?'selected':''} value="${n}">${n} дней</option>`).join('')}</select></label><button>Применить</button></form>${!data.data_available?note(data.note,'warn'):''}${tablecard('Отчёты сети',['Источник','Валюта','Тип отчёта','Сумма','Получен'],data.items.map(r=>[esc(r.provider),esc(r.currency),esc(r.status),esc(new Intl.NumberFormat('ru',{style:'currency',currency:r.currency}).format(r.amount_minor/100)),esc(r.received_at)]))}`,()=>{document.getElementById('revenue-period').onsubmit=e=>{e.preventDefault();location.hash='revenue?days='+new FormData(e.currentTarget).get('days');};});
 }
 if(key==='languages'){
  const data=await api('/admin/languages');return result('Языки интерфейса',tablecard('Поддерживаемые языки',['Код','Язык','Аккаунтов'],data.items.map(r=>[esc(r.code),esc(r.title),r.active_users]))+note('Переводы версионируются вместе с приложением. Настройка языка отдельного аккаунта не изменяет язык других пользователей.'));
 }
 if(key==='country-detail'){
  const data=await api('/admin/country-capabilities');return result('Готовность страны',card('Подключения и опубликованные политики',output(data))+'<a class="btn primary" href="#countries">Управление страной</a>');
 }
 if(['promo-preview','referral-preview','monetization-preview','promo','rewarded','banner-detail'].includes(key)){
  const endpoint=key.startsWith('promo')?'promotions':key.startsWith('referral')?'referral-campaigns':'monetization-configs';
  const s=await selection('/admin/'+endpoint,'Версия');
  return result('Предпросмотр конфигурации',s.picker+(s.record?card(s.record.title,output(s.record.payload)+`<form id="scenario-command" class="stack">${namedField('Служебная причина','reason','textarea')}<button class="primary">Проверить и показать влияние</button>${alerts}</form>`):''),()=>{s.bind();wire('#scenario-command',v=>api('/admin/'+endpoint+'/'+s.record.id+'/preview','POST',{...v,expected_version:s.record.version}));});
 }
 if(key==='dictionary-dryrun'){
  const s=await selection('/admin/moderation-dictionaries','Словарь');
  return result('Проверка словаря на тексте',s.picker+(s.record?card('Пробный запуск',`<p>${esc(s.record.title)} · версия ${s.record.version}</p><form id="dictionary-dryrun" class="stack"><label>Поверхность<select name="surface">${['order','contractor','portfolio','message','offer','review','user'].map(x=>`<option>${x}</option>`).join('')}</select></label>${namedField('Текст для проверки','text','textarea')}${namedField('Причина проверки','reason','textarea')}<button class="primary">Проверить текст</button>${alerts}</form>${note('Проверка не публикует словарь, не меняет контент и не накладывает санкции.')}`):''),()=>{s.bind();wire('#dictionary-dryrun',v=>api('/admin/moderation-dictionaries/'+s.record.id+'/dry-run','POST',{...v,expected_version:s.record.version}));});
 }
 if(key==='security-full'){
  const s=await selection('/admin/security-events','Событие');
  return result('Защищённый просмотр события',s.picker+(s.record?card('Разрешение просмотра',`<p>${esc(s.record.event)} · ${esc(s.record.created_at)}</p><form id="security-disclose" class="stack">${namedField('Служебная причина раскрытия','reason','textarea')}<button class="primary">Показать полные данные события</button>${alerts}</form>${note('Просмотр фиксируется в неизменяемом аудите. Токены и секреты не раскрываются.')}`):''),()=>{s.bind();wire('#security-disclose',v=>api('/admin/security-events/'+s.record.id+'/disclose','POST',v));});
 }
 if(key==='blacklist-detail'){
  const s=await selection('/admin/blacklist','Ограничение');const r=s.record?await api('/admin/blacklist/'+s.record.id):null;
  return result('Решение по ограничению',s.picker+(r?card('Действующее решение',output(r)+`<form id="blacklist-decision" class="stack"><label>Решение<select name="decision"><option value="release">Снять ограничение</option><option value="extend">Продлить</option><option value="overturn">Отменить решение</option></select></label>${namedField('Конечный срок (UTC)','ends_at','datetime-local')}${namedField('Основание решения','reason','textarea')}<button class="primary">Зафиксировать решение</button>${alerts}</form>`):''),()=>{s.bind();wire('#blacklist-decision',v=>api('/admin/blacklist/'+r.id+'/decision','POST',{...v,ends_at:v.ends_at?new Date(v.ends_at+'Z').toISOString():undefined,expected_version:r.version}));});
 }
 if(['verification-review','id-auth','deletion'].includes(key)){
  const type=key==='deletion'?'privacy-requests':'verifications',s=await selection('/admin/'+type,'Заявка');
  return result(key==='deletion'?'Запрос удаления':'Проверка документов',s.picker+(s.record?card('Состояние заявки',output({id:s.record.id,status:s.record.status,version:s.record.version,created_at:s.record.created_at})+`<a class="btn primary" href="#record-live/${key==='deletion'?'privacy':'verification'}/${esc(s.record.id)}">${key==='deletion'?'Открыть запрос':'Открыть проверку и разрешение просмотра'}</a>`):''),()=>s.bind());
 }
 if(key==='archive'){
  const [push,promo]=await Promise.all([api('/admin/push-campaigns?status=completed'),api('/admin/promotions?status=expired')]);
  return result('Архив кампаний',tablecard('Завершённые версии',['Тип','Название','Состояние','Дата'],[...push.items.map(r=>['Рассылка',esc(r.title),esc(r.status),esc(r.created_at)]),...promo.items.map(r=>['Промо',esc(r.title),esc(r.status),esc(r.created_at)])]));
 }
 if(key==='push-compose'){
  return result('Новая push-кампания',card('Локализованное сообщение',`<form id="push-compose" class="stack">${namedField('Название кампании','title')}${namedField('Заголовок','message_title')}${namedField('Сообщение','message_body','textarea')}<label>Язык<select name="locale"><option>ru</option><option>kk</option><option>sr</option><option>be</option></select></label><label>Тип<select name="type"><option value="service">Сервисное</option><option value="marketing">Маркетинговое</option></select></label>${namedField('Разрешённая ссылка приложения','deep_link')}${namedField('Время отправки (UTC)','send_at','datetime-local')}${namedField('Основание','reason','textarea')}<button class="primary">Сохранить черновик</button>${alerts}</form>`),()=>wire('#push-compose',v=>api('/admin/push-campaigns','POST',{title:v.title,reason:v.reason,payload:{type:v.type,locales:[v.locale],roles:['customer','executor'],title:{[v.locale]:v.message_title},body:{[v.locale]:v.message_body},deep_link:v.deep_link,send_at:v.send_at?new Date(v.send_at+'Z').toISOString():null,time_zone:'UTC'}})));
 }
 throw Error('Неизвестный сценарий');
}
