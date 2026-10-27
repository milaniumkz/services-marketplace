import {privacyProgress} from './privacy-progress.js';
// Staff review cards use the same country-scoped API as the operational lists.
export async function reviewWorkspace({key,api,esc,card,note,namedField,sections,onRefresh,staffAccess}) {
  const [,section,id]=key.split('/');
  if(!sections[section]||!id)throw Error('Карточка не найдена');
  const base='/admin/'+sections[section][0]+'/'+encodeURIComponent(id);
  const record=await api(base);
  const labels={users:'Аккаунт',orders:'Заказ',portfolio:'Проект портфолио',contractors:'Профиль исполнителя',verification:'Проверка документов',privacy:'Запрос приватности'};
  const details=Object.entries({
    'ID':record.id,'Страна':record.country,'Статус':record.status,'Ревизия':record.version,
    'Имя':record.display_name,'Название':record.title,'Описание':record.description,
    'Город':record.city,'Категория':record.category_id,'Заказчик':record.owner,
    'Исполнитель':record.executor_id,'Проверка аккаунта':record.verification,
    'Тип документа':record.document_type,'Ревизия документов':record.document_revision,
    'Причина решения':record.reason,'Создано':record.created_at,'Действует до':record.expires_at
  }).filter(([,v])=>v!==undefined&&v!==null).map(([k,v])=>`<div class="event"><b>${esc(k)}</b><p>${esc(v)}</p></div>`).join('');
  const allowed=grant=>!staffAccess?.managed||staffAccess.grants.includes(grant);
  const gate=grant=>allowed(grant)?'':' disabled title="Действие не разрешено вашей ролью"';
  let controls='';
  if(section==='users')controls=card('Доступ к персональным данным',`<form id="sensitive-read" class="stack" data-staff-read>${namedField('Служебная причина просмотра','reason','textarea')}<button class="primary">Показать телефон</button><p id="sensitive-result" role="status"></p></form>`);
  if(section==='users'&&!record.staff_permissions?.length&&record.status!=='deleted'&&['block','unblock','delete'].some(action=>allowed('POST /admin/users/{id}/'+action)))controls+=card('Управление аккаунтом',`<form id="account-action" class="stack"><label>Действие<select name="action">${[['block','Заблокировать (бан)'],['unblock','Разблокировать'],['delete','Удалить аккаунт']].filter(([action])=>allowed('POST /admin/users/{id}/'+action)).map(([action,label])=>`<option value="${action}">${label}</option>`).join('')}</select></label>${namedField('Причина — минимум 10 символов','reason','textarea')}${namedField('Для удаления введите ID аккаунта','confirmation')}<p>Блокировка закрывает вход и завершает сессии. Удаление закрывает доступ сразу; обработка данных выполняется через раздел приватности с учётом текущих заказов и сроков хранения.</p><button class="primary">Выполнить действие</button><p role="status"></p></form>`);
  if(section==='verification') {
    controls=card('Документы',`<form id="sensitive-read" class="stack" data-staff-read>${namedField('Служебная причина просмотра','reason','textarea')}<button class="primary"${gate('sensitive.identity')}>Открыть документы</button><div id="sensitive-result" role="status"></div></form>`);
    if(record.status==='pending_review')controls+=card('Решение по проверке',`<form id="review-decision" class="stack"><label for="review-decision-value">Решение</label><select id="review-decision-value" name="decision"><option value="passed">Проверка пройдена</option><option value="rejected">Отказать</option></select>${namedField('Действует до (UTC)','expires_at','datetime-local')}${namedField('Основание решения','reason','textarea')}<button class="primary"${gate('POST /admin/'+sections[section][0]+'/{id}/decision')}>Сохранить решение</button></form>`);
  }
  if(['portfolio','contractors'].includes(section)&&['pending_review','pending_moderation'].includes(record.status))controls=card('Модерация проекта',`<form id="review-decision" class="stack"><label for="review-decision-value">Решение</label><select id="review-decision-value" name="decision"><option value="approve">Опубликовать</option><option value="reject">Отклонить</option></select>${namedField('Основание решения','reason','textarea')}<button class="primary"${gate('POST /admin/'+sections[section][0]+'/{id}/decision')}>Сохранить решение</button></form>`);
  if(section==='privacy')controls+=privacyProgress({record,esc,card,note});
  if(section==='verification'&&record.retention_minimized_at)controls=card('Хранение документов',note('Персональные поля проверки минимизированы по опубликованному сроку аудита. Решение и технические идентификаторы сохранены; файлы удалены.'));
  const photos=record.photos||record.gallery_ids||[];
  if(['portfolio','contractors'].includes(section)&&photos.length&&record.status!=='archived')controls+=card('Фотографии текущей ревизии',`<form id="content-media" class="stack" data-staff-read>${namedField('Причина просмотра фотографий','reason','textarea')}<button class="primary"${gate('files.content')}>Показать фотографии</button><div id="content-media-result" class="grid cols2"></div></form>`);
  return {key,id:section==='verification'?'A07':section==='privacy'?'A11':'A04',title:labels[section],subtitle:record.id,section:sections[section][1],actions:`<a class="btn" href="#${section}">К списку</a><button id="refresh-data" type="button">Обновить</button>`,body:()=>`<div class="grid cols2">${card('Сведения',details)}<div class="stack">${controls||note('Данные текущей ревизии записи.')}</div></div>`,bind(){
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
      for(const [index,uploadId] of data.document_refs.entries()){
        const button=document.createElement('button');button.type='button';button.textContent=data.document_labels?.[index]||(index===data.selfie_index?'Селфи':'Документ '+(index+1));
        button.onclick=async()=>{button.disabled=true;try{
          const ticket=await api('/uploads/'+encodeURIComponent(uploadId)+'/download-url?'+new URLSearchParams({reason}));
          // The API issues a short-lived, one-use capability only after checking ACLs.
          const url=new URL(ticket.url,location.origin);if(url.origin!==location.origin||!url.pathname.startsWith('/api/v1/private-files/'))throw Error('Некорректный адрес документа');
          const image=document.createElement('img');image.src=url.href;image.alt=data.document_labels?.[index]||'Фотография для проверки';image.style.maxWidth='100%';image.style.maxHeight='480px';image.referrerPolicy='no-referrer';button.replaceWith(image);return;

        }catch(error){const alert=document.createElement('p');alert.role='alert';alert.textContent=error.message;result.append(alert);button.disabled=false;}};
        result.append(button);
      }
    });
  }};
}
