// Staff review cards use the same country-scoped API as the operational lists.
export async function reviewWorkspace({key,api,esc,card,note,namedField,sections,onRefresh}) {
  const [,section,id]=key.split('/');
  if(!sections[section]||!id)throw Error('Карточка не найдена');
  const base='/admin/'+sections[section][0]+'/'+encodeURIComponent(id);
  const record=await api(base);
  const labels={users:'Аккаунт',orders:'Заказ',portfolio:'Проект портфолио',verification:'Проверка документов',privacy:'Запрос приватности'};
  const details=Object.entries({
    'ID':record.id,'Страна':record.country,'Статус':record.status,'Ревизия':record.version,
    'Имя':record.display_name,'Название':record.title,'Описание':record.description,
    'Город':record.city,'Категория':record.category_id,'Заказчик':record.owner,
    'Исполнитель':record.executor_id,'Проверка аккаунта':record.verification,
    'Тип документа':record.document_type,'Ревизия документов':record.document_revision,
    'Причина решения':record.reason,'Создано':record.created_at,'Действует до':record.expires_at
  }).filter(([,v])=>v!==undefined&&v!==null).map(([k,v])=>`<div class="event"><b>${esc(k)}</b><p>${esc(v)}</p></div>`).join('');
  let controls='';
  if(section==='users')controls=card('Доступ к персональным данным',`<form id="sensitive-read" class="stack">${namedField('Служебная причина просмотра','reason','textarea')}<button class="primary">Показать телефон</button><p id="sensitive-result" role="status"></p></form>`);
  if(section==='verification') {
    controls=card('Документы',`<form id="sensitive-read" class="stack">${namedField('Служебная причина просмотра','reason','textarea')}<button class="primary">Открыть документы</button><div id="sensitive-result" role="status"></div></form>`);
    if(record.status==='pending_review')controls+=card('Решение по проверке',`<form id="review-decision" class="stack"><label for="review-decision-value">Решение</label><select id="review-decision-value" name="decision"><option value="passed">Проверка пройдена</option><option value="rejected">Отказать</option></select>${namedField('Действует до (UTC)','expires_at','datetime-local')}${namedField('Основание решения','reason','textarea')}<button class="primary">Сохранить решение</button></form>`);
  }
  if(section==='portfolio'&&['pending_review','pending_moderation'].includes(record.status))controls=card('Модерация проекта',`<form id="review-decision" class="stack"><label for="review-decision-value">Решение</label><select id="review-decision-value" name="decision"><option value="approve">Опубликовать</option><option value="reject">Отклонить</option></select>${namedField('Основание решения','reason','textarea')}<button class="primary">Сохранить решение</button></form>`);
  return {key,id:section==='verification'?'A15':'A04',title:labels[section],subtitle:record.id,section:sections[section][1],actions:`<a class="btn" href="#${section}">К списку</a>`,body:()=>`<div class="grid cols2">${card('Сведения',details)}<div class="stack">${controls||note('Данные текущей ревизии записи.')}</div></div>`,bind(){
    const wire=(selector,action)=>{const form=document.querySelector(selector);if(!form)return;form.onsubmit=async event=>{event.preventDefault();const values=Object.fromEntries(new FormData(form));form.querySelectorAll('button').forEach(b=>b.disabled=true);form.querySelector('[role=alert]')?.remove();try{await action(values);}catch(error){const alert=document.createElement('p');alert.role='alert';alert.className='note danger';alert.textContent=error.message;form.append(alert);}finally{form.querySelectorAll('button').forEach(b=>b.disabled=false);}};};
    wire('#review-decision',async values=>{
      if(values.expires_at) {const value=new Date(values.expires_at+'Z');if(!Number.isFinite(value.getTime()))throw Error('Проверьте срок действия');values.expires_at=value.toISOString();}
      await api(base+'/decision','POST',{...values,expected_version:record.version,...(section==='verification'?{document_revision:record.document_revision}:{})});await onRefresh();
    });
    wire('#sensitive-read',async({reason})=>{
      const result=document.querySelector('#sensitive-result');
      const data=await api(base+'?'+new URLSearchParams({reason,...(section==='users'?{include_phone:'true'}:{include_documents:'true'})}));
      result.replaceChildren();
      if(section==='users'){result.textContent=data.phone;return;}
      if(!data.document_refs?.length){result.textContent='Документы отсутствуют';return;}
      for(const uploadId of data.document_refs){
        const button=document.createElement('button');button.type='button';button.textContent='Просмотреть документ';
        button.onclick=async()=>{button.disabled=true;try{
          const ticket=await api('/uploads/'+encodeURIComponent(uploadId)+'/download-url?'+new URLSearchParams({reason}));
          // The API issues a short-lived, one-use capability only after checking ACLs.
          const url=new URL(ticket.url,location.origin);if(url.origin!==location.origin||!url.pathname.startsWith('/api/v1/private-files/'))throw Error('Некорректный адрес документа');
          const link=document.createElement('a');link.href=url.href;link.target='_blank';link.rel='noopener noreferrer';link.textContent='Открыть защищённый файл';button.replaceWith(link);
        }catch(error){const alert=document.createElement('p');alert.role='alert';alert.textContent=error.message;result.append(alert);button.disabled=false;}};
        result.append(button);
      }
    });
  }};
}
