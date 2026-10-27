import {privacyProgress} from './privacy-progress.js';
// Staff review cards use the same country-scoped API as the operational lists.
export async function reviewWorkspace({key,api,esc,card,note,namedField,sections,onRefresh,staffAccess}) {
  const [,section,id]=key.split('/');
  if(!sections[section]||!id)throw Error('Карточка не найдена');
  const base='/admin/'+sections[section][0]+'/'+encodeURIComponent(id);
  const record=await api(base);
  const labels={users:'Аккаунт',orders:'Заказ',portfolio:'Проект портфолио',contractors:'Профиль исполнителя',verification:'Проверка документов',privacy:'Запрос приватности'};
  const stateNames={pending_review:'Ожидает проверки',passed:'Проверка пройдена',rejected:'Отклонено',expired:'Срок истёк',draft:'Черновик',not_started:'Не пройдена',active:'Активен',blocked:'Заблокирован',deleted:'Удалён'};
  const when=value=>value&&Number.isFinite(Date.parse(value))?new Intl.DateTimeFormat('ru',{dateStyle:'short',timeStyle:'short',timeZone:'UTC'}).format(new Date(value))+' UTC':'Не указано';
  const details=Object.entries({
    'ID':record.id,'Страна':record.country,'Статус':stateNames[record.status]||record.status,'Ревизия':record.version,
    'Имя':record.display_name,'Название':record.title,'Описание':record.description,
    'Город':record.city,'Категория':record.category_id,'ID пользователя':record.owner,
    'Исполнитель':record.executor_id,'Проверка аккаунта':record.verification,
    'Тип документа':({id_card:'Удостоверение личности',passport:'Паспорт'})[record.document_type]||record.document_type,'Ревизия документов':record.document_revision,
    'Причина решения':record.reason,'Создано':when(record.created_at),'Решение принято':record.decided_at?when(record.decided_at):undefined,'Действует до':record.expires_at?when(record.expires_at):undefined
  }).filter(([,v])=>v!==undefined&&v!==null).map(([k,v])=>`<div class="event"><b>${esc(k)}</b><p>${esc(v)}</p></div>`).join('');
  const allowed=grant=>!staffAccess?.managed||staffAccess.grants.includes(grant);
  const gate=grant=>allowed(grant)?'':' disabled title="Действие не разрешено вашей ролью"';
  const user=record.subject;
  const row=(label,value)=>`<div class="event"><b>${esc(label)}</b><p>${esc(value??'Не указано')}</p></div>`;
  const subjectCard=section==='verification'?card('Пользователь',user?
    row('Имя в профиле',user.display_name||'Не указано')+row('ID аккаунта',user.id)+
    row('Телефон',user.phone||user.phone_masked||'Не указан')+`<p id="verification-phone"></p>`+
    row('Город',user.city||'Не указан')+row('Страна',({KZ:'Казахстан',RU:'Россия',BY:'Беларусь',KG:'Кыргызстан'})[user.country]||user.country)+
    row('Роли',(user.roles||[]).map(role=>({customer:'Заказчик',executor:'Исполнитель'})[role]||role).join(', '))+
    row('Активная роль',({customer:'Заказчик',executor:'Исполнитель'})[user.active_role]||user.active_role)+
    row('Состояние аккаунта',stateNames[user.status]||user.status)+row('Проверка личности',stateNames[user.verification]||user.verification)+
    row('Дата регистрации',when(user.created_at))+
    (allowed('GET /admin/users/{id}')?`<a class="btn" href="#user-detail?user_id=${encodeURIComponent(user.id)}">Открыть аккаунт пользователя</a>`:''):
    note('Данные аккаунта недоступны или уже удалены.')):'';
  const historyCard=section==='verification'?card('История проверок пользователя',record.history?.length?record.history.map(v=>`<div class="event"><b>${esc(stateNames[v.status]||v.status)}${v.id===record.id?' · текущая заявка':''}</b><p>${esc(when(v.created_at))} · ${esc(v.document_type==='id_card'?'Удостоверение личности':v.document_type==='passport'?'Паспорт':v.document_type)}</p>${v.decided_at?`<p>Решение: ${esc(when(v.decided_at))}</p>`:''}${v.reason?`<p>${esc(v.reason)}</p>`:''}${v.reviewer_id?`<small>Сотрудник: ${esc(v.reviewer_id)}</small>`:''}${v.id!==record.id?`<p><a href="#record-live/verification/${encodeURIComponent(v.id)}">Открыть заявку</a></p>`:''}</div>`).join('')+note('Показаны последние '+record.history_limit+' заявок.'):note('Предыдущих заявок нет.')):'';
  let controls='';
  if(section==='users')controls=card('Доступ к персональным данным',`<form id="sensitive-read" class="stack" data-staff-read>${namedField('Служебная причина просмотра','reason','textarea')}<button class="primary">Показать телефон</button><p id="sensitive-result" role="status"></p></form>`);
  if(section==='users'&&!record.staff_permissions?.length&&record.status!=='deleted'&&['block','unblock','delete'].some(action=>allowed('POST /admin/users/{id}/'+action)))controls+=card('Управление аккаунтом',`<form id="account-action" class="stack"><label>Действие<select name="action">${[['block','Заблокировать (бан)'],['unblock','Разблокировать'],['delete','Удалить аккаунт']].filter(([action])=>allowed('POST /admin/users/{id}/'+action)).map(([action,label])=>`<option value="${action}">${label}</option>`).join('')}</select></label>${namedField('Причина — минимум 10 символов','reason','textarea')}${namedField('Для удаления введите ID аккаунта','confirmation')}<p>Блокировка закрывает вход и завершает сессии. Удаление закрывает доступ сразу; обработка данных выполняется через раздел приватности с учётом текущих заказов и сроков хранения.</p><button class="primary">Выполнить действие</button><p role="status"></p></form>`);
  if(section==='verification') {
    controls=card('Документы',`<form id="sensitive-read" class="stack" data-staff-read>${namedField('Служебная причина просмотра','reason','textarea')}<button class="primary"${gate('sensitive.identity')}>Открыть документы</button><p class="muted">Две стороны удостоверения и селфи загружаются автоматически для сотрудника с правом просмотра. Просмотр записывается в журнал.</p><div id="sensitive-result" class="verification-media-grid" role="status"></div></form>`);
    if(record.status==='pending_review')controls+=card('Решение по проверке',`<form id="review-decision" class="stack"><label for="review-decision-value">Решение</label><select id="review-decision-value" name="decision"><option value="passed">Проверка пройдена</option><option value="rejected">Отказать</option></select>${namedField('Действует до (UTC)','expires_at','datetime-local')}${namedField('Основание решения','reason','textarea')}<button class="primary"${gate('POST /admin/'+sections[section][0]+'/{id}/decision')}>Сохранить решение</button></form>`);
  }
  if(['portfolio','contractors'].includes(section)&&['pending_review','pending_moderation'].includes(record.status))controls=card('Модерация проекта',`<form id="review-decision" class="stack"><label for="review-decision-value">Решение</label><select id="review-decision-value" name="decision"><option value="approve">Опубликовать</option><option value="reject">Отклонить</option></select>${namedField('Основание решения','reason','textarea')}<button class="primary"${gate('POST /admin/'+sections[section][0]+'/{id}/decision')}>Сохранить решение</button></form>`);
  if(section==='privacy')controls+=privacyProgress({record,esc,card,note});
  if(section==='verification'&&record.retention_minimized_at)controls=card('Хранение документов',note('Персональные поля проверки минимизированы по опубликованному сроку аудита. Решение и технические идентификаторы сохранены; файлы удалены.'));
  const photos=record.photos||record.gallery_ids||[];
  if(['portfolio','contractors'].includes(section)&&photos.length&&record.status!=='archived')controls+=card('Фотографии текущей ревизии',`<form id="content-media" class="stack" data-staff-read>${namedField('Причина просмотра фотографий','reason','textarea')}<button class="primary"${gate('files.content')}>Показать фотографии</button><div id="content-media-result" class="grid cols2"></div></form>`);
  return {key,id:section==='verification'?'A07':section==='privacy'?'A11':'A04',title:labels[section],subtitle:record.id,section:sections[section][1],actions:`<a class="btn" href="#${section}">К списку</a><button id="refresh-data" type="button">Обновить</button>`,body:()=>`<div class="grid cols2"><div class="stack">${subjectCard}${card('Сведения',details)}${historyCard}</div><div class="stack">${controls||note('Данные текущей ревизии записи.')}</div></div>`,bind(){
    const wire=(selector,action)=>{const form=document.querySelector(selector);if(!form)return;form.onsubmit=async event=>{event.preventDefault();const values=Object.fromEntries(new FormData(form));form.querySelectorAll('button').forEach(b=>b.disabled=true);form.querySelector('[role=alert]')?.remove();try{await action(values);}catch(error){const alert=document.createElement('p');alert.role='alert';alert.className='note danger';alert.textContent=error.message;form.append(alert);}finally{form.querySelectorAll('button').forEach(b=>b.disabled=false);}};};
    wire('#account-action',async values=>{
      const grant='POST /admin/users/{id}/'+values.action;
      if(!allowed(grant))throw Error('Действие не разрешено вашей ролью');
      if(!window.confirm(({block:'Заблокировать',unblock:'Разблокировать',delete:'Удалить'}[values.action]||'Изменить')+' аккаунт '+record.id+'?'))return;
      const result=await api(base+'/'+values.action,'POST',{expected_version:record.version,reason:values.reason,confirmation:values.confirmation});
      if(result.deletion_request_id){location.hash='record-live/privacy/'+encodeURIComponent(result.deletion_request_id);return;}
      await onRefresh();
    });
    wire('#review-decision',async values=>{
      if(values.expires_at) {const value=new Date(values.expires_at+'Z');if(!Number.isFinite(value.getTime()))throw Error('Проверьте срок действия');values.expires_at=value.toISOString();}
      await api(base+'/decision','POST',{...values,expected_version:record.version,...(section==='verification'?{document_revision:record.document_revision}:{})});await onRefresh();
    });
    wire('#content-media',async({reason})=>{
      const result=document.getElementById('content-media-result');result.replaceChildren();
      for(const id of photos){const ticket=await api('/uploads/'+encodeURIComponent(id)+'/download-url?'+new URLSearchParams({reason}));const url=new URL(ticket.url,location.origin);if(url.origin!==location.origin||!url.pathname.startsWith('/api/v1/private-files/'))throw Error('Некорректный адрес фотографии');const image=document.createElement('img');image.src=url.href;image.alt='Фотография работы';image.style.width='100%';image.style.borderRadius='12px';image.referrerPolicy='no-referrer';result.append(image);}
    });
    wire('#sensitive-read',async({reason})=>{
      const result=document.querySelector('#sensitive-result');
      const data=await api(base+'?'+new URLSearchParams({reason,...(section==='users'?{include_phone:'true'}:{include_documents:'true'})}));
      result.replaceChildren();
      if(section==='users'){result.textContent=data.phone;return;}
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
