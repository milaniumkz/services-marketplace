import {verificationStatus} from './verification-status.js';
import {privacyProgress} from './privacy-progress.js';
// Staff review cards use the same country-scoped API as the operational lists.
export async function reviewWorkspace({key,api,esc,card,note,namedField,sections,onRefresh,staffAccess}) {
  const [,section,id]=key.split('/');
  if(!sections[section]||!id)throw Error('Карточка не найдена');
  const base='/admin/'+sections[section][0]+'/'+encodeURIComponent(id);
  const record=await api(base);
  const labels={users:'Аккаунт',orders:'Заказ',portfolio:'Проект портфолио',contractors:'Профиль исполнителя',verification:'Проверка документов',privacy:'Запрос приватности'};
  const stateNames={pending_review:'Ожидает проверки',pending_moderation:'Ожидает модерации',published:'Опубликовано',paused:'Приостановлено',archived:'Архив',passed:'Проверка пройдена',rejected:'Отклонено',expired:'Срок истёк',draft:'Черновик',not_started:'Не пройдена',active:'Активен',blocked:'Заблокирован',deleted:'Удалён'};
  const when=value=>value&&Number.isFinite(Date.parse(value))?new Intl.DateTimeFormat('ru',{dateStyle:'short',timeStyle:'short',timeZone:'UTC'}).format(new Date(value))+' UTC':'Не указано';
  const details=Object.entries({
    'ID':record.id,'Страна':record.country,'Статус':section==='verification'?verificationStatus(record.status):stateNames[record.status]||record.status,'Ревизия':record.version,
    'Имя':record.display_name,'Название':record.title,'Описание':record.description,
    'Город':record.city,'Категория':record.category_id,'ID пользователя':record.owner,
    'Исполнитель':record.executor_id,'Проверка аккаунта':record.verification?verificationStatus(record.verification):undefined,
    'Тип документа':({id_card:'Удостоверение личности',passport:'Паспорт'})[record.document_type]||record.document_type,'Ревизия документов':record.document_revision,
    'Причина решения':record.reason,'Создано':when(record.created_at),'Решение принято':record.decided_at?when(record.decided_at):undefined,'Срок подтверждения':section==='verification'&&record.status==='passed'?'Бессрочно, до ручного отзыва':undefined
  }).filter(([,v])=>v!==undefined&&v!==null).map(([k,v])=>`<div class="event"><b>${esc(k)}</b><p>${esc(v)}</p></div>`).join('');
  const allowed=grant=>!staffAccess?.managed||staffAccess.grants.includes(grant);
  const gate=grant=>allowed(grant)?'':' disabled title="Действие не разрешено вашей ролью"';
  const user=record.subject;
  const row=(label,value)=>`<div class="event"><b>${esc(label)}</b><p>${esc(value??'Не указано')}</p></div>`;
  const subjectCard=['verification','contractors','portfolio'].includes(section)?card('Пользователь',user?
    row('Имя в профиле',user.display_name||'Не указано')+row('ID аккаунта',user.id)+
    row('Телефон',user.phone||user.phone_masked||'Не указан')+`<p id="verification-phone"></p>`+
    row('Город',user.city||'Не указан')+row('Страна',({KZ:'Казахстан',RU:'Россия',BY:'Беларусь',KG:'Кыргызстан'})[user.country]||user.country)+
    row('Роли',(user.roles||[]).map(role=>({customer:'Заказчик',executor:'Исполнитель'})[role]||role).join(', '))+
    row('Активная роль',({customer:'Заказчик',executor:'Исполнитель'})[user.active_role]||user.active_role)+
    row('Состояние аккаунта',stateNames[user.status]||user.status)+row('Проверка личности',verificationStatus(user.verification))+
    row('Дата регистрации',when(user.created_at))+
    (allowed('GET /admin/users/{id}')?`<a class="btn" href="#user-detail?user_id=${encodeURIComponent(user.id)}">Открыть аккаунт пользователя</a>`:''):
    note('Данные аккаунта недоступны или уже удалены.')):'';
  const historyCard=section==='verification'?card('История проверок пользователя',record.history?.length?record.history.map(v=>`<div class="event"><b>${esc(verificationStatus(v.status))}${v.id===record.id?' · текущая заявка':''}</b><p>${esc(when(v.created_at))} · ${esc(v.document_type==='id_card'?'Удостоверение личности':v.document_type==='passport'?'Паспорт':v.document_type)}</p>${v.decided_at?`<p>Решение: ${esc(when(v.decided_at))}</p>`:''}${v.reason?`<p>${esc(v.reason)}</p>`:''}${v.reviewer_id?`<small>Сотрудник: ${esc(v.reviewer_id)}</small>`:''}${v.id!==record.id?`<p><a href="#record-live/verification/${encodeURIComponent(v.id)}">Открыть заявку</a></p>`:''}</div>`).join('')+note('Показаны последние '+record.history_limit+' заявок.'):note('Предыдущих заявок нет.')):'';
  let controls='';
  if(section==='users')controls=card('Доступ к персональным данным',`<form id="sensitive-read" class="stack" data-staff-read>${namedField('Цель просмотра телефона','reason','textarea')}<small>Цель уже заполнена. При необходимости уточните её — просмотр записывается в журнал.</small><button class="primary"${gate('sensitive.phone')}>Показать телефон</button><p id="sensitive-result" role="status"></p></form>`);
  if(section==='users'&&!record.staff_permissions?.length&&record.status!=='deleted'&&['block','unblock','delete'].some(action=>allowed('POST /admin/users/{id}/'+action)))controls+=card('Управление аккаунтом',`<form id="account-action" class="stack"><label>Действие<select name="action">${[['block','Заблокировать (бан)'],['unblock','Разблокировать'],['delete','Удалить аккаунт']].filter(([action])=>allowed('POST /admin/users/{id}/'+action)).map(([action,label])=>`<option value="${action}">${label}</option>`).join('')}</select></label>${namedField('Причина действия','reason','textarea')}<p>Блокировка закрывает вход. Для удаления выберите действие, укажите причину и нажмите «Удалить аккаунт». Доступ закрывается сразу.</p><button class="primary">Выполнить действие</button><p role="status"></p></form>`);
  if(section==='verification') {
    controls=card('Документы',`<form id="sensitive-read" class="stack" data-staff-read>${namedField('Служебная причина просмотра','reason','textarea')}<button class="primary"${gate('sensitive.identity')}>Открыть документы</button><p class="muted">Две стороны удостоверения и селфи загружаются автоматически для сотрудника с правом просмотра. Просмотр записывается в журнал.</p><div id="sensitive-result" class="verification-media-grid" role="status"></div></form>`);
    if(['pending_review','passed'].includes(record.status))controls+=card('Решение по проверке',`<form id="review-decision" class="stack"><label for="review-decision-value">Решение</label><select id="review-decision-value" name="decision">${record.status==='passed'?'<option value="revoked">Отозвать подтверждение личности</option>':'<option value="passed">Подтвердить личность — бессрочно</option><option value="rejected">Запросить исправления</option>'}</select><p>Подтверждение действует бессрочно до ручного отзыва. Повторная загрузка по календарю не требуется.</p>${namedField('Основание решения','reason','textarea')}<button class="primary"${gate('POST /admin/'+sections[section][0]+'/{id}/decision')}>Сохранить решение</button></form>`);
  }
  if(['portfolio','contractors'].includes(section)&&['pending_review','pending_moderation'].includes(record.status))controls=card('Модерация проекта',`<form id="review-decision" class="stack"><label for="review-decision-value">Решение</label><select id="review-decision-value" name="decision"><option value="approve">Опубликовать</option><option value="reject">Отклонить</option></select>${namedField('Основание решения','reason','textarea')}<button class="primary"${gate('POST /admin/'+sections[section][0]+'/{id}/decision')}>Сохранить решение</button></form>`);
  if(section==='privacy')controls+=privacyProgress({record,esc,card,note});
  if(section==='verification'&&record.retention_minimized_at)controls=card('Хранение документов',note('Персональные поля проверки минимизированы по опубликованному сроку аудита. Решение и технические идентификаторы сохранены; файлы удалены.'));
  const contentSection=['portfolio','contractors'].includes(section);
  const photos=[...(record.subject?.avatar_id?[{id:record.subject.avatar_id,label:'Фото профиля'}]:[]),...(record.photos||record.gallery_ids||[]).map((id,index)=>({id,label:'Фотография работы '+(index+1)}))];
  const valueNames={onsite:'На выезде',workshop:'В мастерской',remote:'Удалённо',hybrid:'Смешанный формат',available:'Свободен',busy:'Занят',paused:'Приостановлен',ru:'Русский',kk:'Казахский',ky:'Кыргызский',be:'Белорусский',en:'Английский'};
  const names=values=>(values||[]).map(v=>valueNames[v]||v).join(', ');
  const price=record.price;
  const priceText=!price?'Не указана':price.mode==='negotiable'?'Договорная':`${new Intl.NumberFormat('ru').format(price.amount_min/100)}${price.amount_max!=null?' — '+new Intl.NumberFormat('ru').format(price.amount_max/100):''} ${price.currency} · ${{fixed:'за работу',hourly:'в час',per_unit:'за единицу'}[price.mode]||price.mode}${price.unit?' · '+({job:'работа',hour:'час',day:'день',piece:'штука',m2:'м²',m3:'м³',meter:'метр',visit:'выезд'}[price.unit]||price.unit):''}`;
  const serviceCard=contentSection?card('Подробности услуги',row('Категории',(record.categories||[]).map(c=>c.name).join(', ')||record.category_id)+row('Стоимость',priceText)+row('Города обслуживания',(record.service_cities||[]).join(', ')||record.city)+row('Радиус выезда, км',record.travel_radius_km)+row('Опыт, лет',record.experience_years)+row('Формат работы',names(record.work_modes))+row('Языки',names(record.languages))+row('Доступность',valueNames[record.availability]||record.availability)+row('Статус публикации',record.public_status)+row('Модерация',record.moderation_status)+row('Причина отклонения',record.rejection_reason||record.reason)+row('Число фотографий работы',(record.photos||record.gallery_ids||[]).length)):'';
  const relatedCard=contentSection?card('Связанные записи',Object.entries({services:['Услуги','contractors'],portfolio:['Портфолио','portfolio'],verifications:['Проверки личности','verification']}).map(([key,[label,route]])=>`<h3>${label}</h3>${record.related?.[key]?.length?record.related[key].map(r=>`<div class="event"><a href="#record-live/${route}/${encodeURIComponent(r.id)}">${esc(r.title||(key==='verifications'?verificationStatus(r.status):stateNames[r.status]||r.status))}</a><p>${esc(key==='verifications'?verificationStatus(r.status):stateNames[r.status]||r.status)} · ${esc(when(r.created_at))}</p></div>`).join(''):'<p>Записей нет или раздел недоступен вашей роли.</p>'}`).join('')+note('До '+(record.related_limit||20)+' последних записей каждого типа.')):'';
  if(contentSection&&photos.length&&record.status!=='archived')controls+=card('Фотографии текущей ревизии',`<form id="content-media" class="stack" data-staff-read>${namedField('Причина просмотра фотографий','reason','textarea')}<button class="primary"${gate('files.content')}>Показать фотографии</button><p>Фотографии загружаются автоматически с записью просмотра в журнал.</p><div id="content-media-result" class="verification-media-grid" role="status"></div></form>`);
  if(contentSection&&!photos.length)controls+=card('Фотографии',note('Фотографии профиля и работ ещё не загружены.'));
  return {key,id:section==='verification'?'A07':section==='privacy'?'A11':'A04',title:labels[section],subtitle:record.id,section:sections[section][1],actions:`<a class="btn" href="#${section}">К списку</a><button id="refresh-data" type="button">Обновить</button>`,body:()=>`<div class="grid cols2"><div class="stack">${subjectCard}${card('Сведения',details)}${serviceCard}${relatedCard}${historyCard}</div><div class="stack">${controls||note('Данные текущей ревизии записи.')}</div></div>`,bind(){
    const wire=(selector,action)=>{const form=document.querySelector(selector);if(!form)return;form.onsubmit=async event=>{event.preventDefault();const values=Object.fromEntries(new FormData(form));form.querySelectorAll('button').forEach(b=>b.disabled=true);form.querySelector('[role=alert]')?.remove();try{await action(values);}catch(error){const alert=document.createElement('p');alert.role='alert';alert.className='note danger';alert.textContent=error.message;form.append(alert);}finally{form.querySelectorAll('button').forEach(b=>b.disabled=false);}};};
    const phoneForm=section==='users'?document.querySelector('#sensitive-read'):null;
    if(phoneForm){const reason=phoneForm.elements.reason;reason.value='Просмотр контактного телефона в карточке пользователя';reason.required=true;reason.minLength=10;reason.maxLength=1000;}
    const accountForm=document.querySelector('#account-action');
    if(accountForm){
      const reasons={block:'Блокировка аккаунта по решению администратора',unblock:'Разблокировка аккаунта по решению администратора',delete:'Удаление аккаунта по решению администратора'};
      const reason=accountForm.elements.reason;
      reason.required=true;reason.minLength=10;reason.maxLength=1000;
      let previousDefault='';
      const updateAction=()=>{const action=accountForm.elements.action.value;if(!reason.value.trim()||reason.value===previousDefault)reason.value=action==='delete'?'':reasons[action];previousDefault=reasons[action];reason.minLength=action==='delete'?3:10;reason.placeholder='Причина действия: от '+reason.minLength+' до 1000 символов';accountForm.querySelector('button').textContent=({block:'Заблокировать',unblock:'Разблокировать',delete:'Удалить аккаунт'})[action];};
      accountForm.elements.action.addEventListener('change',updateAction);updateAction();
    }
    wire('#account-action',async values=>{
      const grant='POST /admin/users/{id}/'+values.action;
      if(!allowed(grant))throw Error('Действие не разрешено вашей ролью');
      values.reason=String(values.reason||'').trim();
      const minimum=values.action==='delete'?3:10;
      if(values.reason.length<minimum||values.reason.length>1000)throw Error('Укажите причину действия: от '+minimum+' до 1000 символов.');
      if(values.action!=='delete'&&!window.confirm(({block:'Заблокировать',unblock:'Разблокировать',delete:'Удалить'}[values.action]||'Изменить')+' аккаунт '+record.id+'?'))return;
      const result=await api(base+'/'+values.action,'POST',{expected_version:record.version,reason:values.reason});
      if(result.deletion_request_id){location.hash='users';return;}
      await onRefresh();
    });
    wire('#review-decision',async values=>{
      if(values.expires_at) {const value=new Date(values.expires_at+'Z');if(!Number.isFinite(value.getTime()))throw Error('Проверьте срок действия');values.expires_at=value.toISOString();}
      if(values.decision==='revoked'&&!window.confirm('Отозвать подтверждение личности? Действия, для которых оно требуется, станут недоступны.'))return;
      await api(base+'/decision','POST',{...values,expected_version:record.version,...(section==='verification'?{document_revision:record.document_revision}:{})});await onRefresh();
    });
    wire('#content-media',async({reason})=>{
      if(!allowed('files.content'))throw Error('Нет права просмотра фотографий контента');
      const result=document.getElementById('content-media-result');result.replaceChildren();
      await Promise.all(photos.map(async({id,label})=>{
        const figure=document.createElement('figure');figure.className='verification-photo';
        const caption=document.createElement('figcaption');caption.textContent=label;
        const image=document.createElement('img');image.alt=label;image.referrerPolicy='no-referrer';
        const message=document.createElement('p');message.role='status';
        const retry=document.createElement('button');retry.type='button';retry.textContent='Загрузить повторно';retry.hidden=true;
        const zoom=document.createElement('button');zoom.type='button';zoom.textContent='Увеличить';zoom.setAttribute('aria-expanded','false');zoom.onclick=()=>{const expanded=figure.classList.toggle('expanded');zoom.textContent=expanded?'Уменьшить':'Увеличить';zoom.setAttribute('aria-expanded',String(expanded));};
        figure.append(caption,image,message,zoom,retry);result.append(figure);
        const load=async()=>{retry.hidden=true;retry.disabled=true;image.hidden=true;message.textContent='Загрузка фотографии…';try{
          const ticket=await api('/uploads/'+encodeURIComponent(id)+'/download-url?'+new URLSearchParams({reason}));
          const url=new URL(ticket.url,location.origin);if(url.origin!==location.origin||!url.pathname.startsWith('/api/v1/private-files/'))throw Error('Некорректный адрес фотографии');
          image.onload=()=>{image.hidden=false;message.textContent='';};image.onerror=()=>{message.textContent='Не удалось загрузить фотографию';retry.hidden=false;retry.disabled=false;};image.src=url.href;
        }catch(error){message.textContent=error.message;retry.hidden=false;retry.disabled=false;}};
        retry.onclick=load;await load();
      }));
    });
    if(contentSection&&user&&allowed('sensitive.phone')&&allowed('GET /admin/users/{id}')){const target=document.getElementById('verification-phone');api('/admin/users/'+encodeURIComponent(user.id)+'?'+new URLSearchParams({include_phone:'true',reason:'Проверка контакта по карточке '+record.id})).then(data=>{if(target?.isConnected)target.textContent=data.phone?'Полный телефон: '+data.phone:'';}).catch(()=>{});}
    if(contentSection){const form=document.getElementById('content-media');if(form&&allowed('files.content')){form.elements.reason.value='Проверка фотографий '+section+' '+record.id;form.requestSubmit();}else if(form){document.getElementById('content-media-result').textContent='Для просмотра требуется право «Файлы контента». Обратитесь к владельцу для назначения доступа.';}}
    wire('#sensitive-read',async({reason})=>{
      const result=document.querySelector('#sensitive-result');
      reason=String(reason||'').trim();if(reason.length<10||reason.length>1000)throw Error('Укажите цель просмотра: от 10 до 1000 символов.');
      const data=await api(base+'?'+new URLSearchParams({reason,...(section==='users'?{include_phone:'true'}:{include_documents:'true'})}));
      result.replaceChildren();
      if(section==='users'){result.textContent=data.phone?'Телефон: '+data.phone:'Телефон не указан в аккаунте';return;}
      if(!data.document_refs?.length){result.textContent='Документы отсутствуют';return;}
      await Promise.all(data.document_refs.map(async(uploadId,index)=>{
        const figure=document.createElement('figure');figure.className='verification-photo';
        const caption=document.createElement('figcaption');caption.textContent=data.document_labels?.[index]||(index===data.selfie_index?'Селфи':'Документ '+(index+1));
        const image=document.createElement('img');image.alt=caption.textContent;image.referrerPolicy='no-referrer';
        const message=document.createElement('p');message.role='status';
        const retry=document.createElement('button');retry.type='button';retry.textContent='Загрузить повторно';retry.hidden=true;
        const zoom=document.createElement('button');zoom.type='button';zoom.textContent='Увеличить';zoom.setAttribute('aria-expanded','false');
        zoom.onclick=()=>{const expanded=figure.classList.toggle('expanded');zoom.textContent=expanded?'Уменьшить':'Увеличить';zoom.setAttribute('aria-expanded',String(expanded));};
        figure.append(caption,image,message,zoom,retry);result.append(figure);
        const load=async()=>{retry.disabled=true;retry.hidden=true;message.textContent='Загрузка фотографии…';image.hidden=true;
          try{
            const ticket=await api('/uploads/'+encodeURIComponent(uploadId)+'/download-url?'+new URLSearchParams({reason}));
            const url=new URL(ticket.url,location.origin);if(url.origin!==location.origin||!url.pathname.startsWith('/api/v1/private-files/'))throw Error('Некорректный адрес документа');
            image.onload=()=>{message.textContent='';image.hidden=false;};
            image.onerror=()=>{message.textContent='Не удалось загрузить фотографию. Повторите загрузку.';retry.hidden=false;retry.disabled=false;};
            image.src=url.href;
          }catch(error){message.textContent=error.message;retry.hidden=false;retry.disabled=false;}
        };
        retry.onclick=load;await load();
      }));
    });
    if(section==='verification'&&!record.retention_minimized_at){
      const form=document.getElementById('sensitive-read');
      if(form&&allowed('sensitive.identity')){
        form.elements.reason.value='Проверка личности по заявке '+record.id;
        form.requestSubmit();
      }else if(form){document.getElementById('sensitive-result').textContent='Для просмотра фотографий требуется право «Просмотр исходников документов».';}
      if(user&&allowed('sensitive.phone')){
        const target=document.getElementById('verification-phone');
        api(base+'?'+new URLSearchParams({include_phone:'true',reason:'Проверка контакта по заявке '+record.id})).then(data=>{
          if(target?.isConnected)target.textContent=data.subject?.phone?'Полный телефон: '+data.subject.phone:'';
        }).catch(()=>{});
      }
    }
  }};
}
