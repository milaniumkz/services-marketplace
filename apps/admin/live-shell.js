let searchHotkey;
const labels={user:'Пользователь',order:'Заказ',case:'Дело',support:'Поддержка',verification:'Проверка'};
const links={user:'record-live/users',order:'record-live/orders',case:'case-live',support:'support-live',verification:'record-live/verification'};
export function clearStaffDialogs(){if(searchHotkey){document.removeEventListener('keydown',searchHotkey);searchHotkey=undefined;}document.querySelectorAll('[data-staff-dialog]').forEach(dialog=>{dialog.close();dialog.remove();});}
export function wireLiveShell({api,esc,card,onRefresh}){
 // The static prototype's page numbers are replaced by actual cursor controls.
 document.querySelectorAll('.cardfoot>span:last-child').forEach(span=>{if(span.textContent.includes('›'))span.remove();});
 const createDialog=title=>{
  clearStaffDialogs();const dialog=document.createElement('dialog');dialog.dataset.staffDialog='true';
  dialog.style.cssText='width:min(680px,calc(100vw - 32px));max-height:85vh;border:1px solid #E5EAF2;border-radius:16px;padding:24px;color:#172B4D';
  dialog.innerHTML=`<div class="cardhead"><h2>${esc(title)}</h2><button type="button" id="close-staff-dialog">Закрыть</button></div><div id="staff-dialog-body"></div>`;
  document.body.append(dialog);dialog.querySelector('#close-staff-dialog').onclick=()=>{dialog.close();dialog.remove();};
  dialog.addEventListener('cancel',()=>dialog.remove());dialog.showModal();return dialog;
 };
 const search=document.querySelector('.topbar .search');
 if(search){
  const openSearch=async()=>{
   const dialog=createDialog('Поиск по стране'),body=dialog.querySelector('#staff-dialog-body');
   body.innerHTML='<p role="status">Загрузка…</p>';
   try{
    const scope=await api('/admin/search');if(!dialog.isConnected)return;
    body.innerHTML=`<form id="staff-global-search" class="stack"><label for="staff-search-query">Имя, название или ID</label><input id="staff-search-query" name="q" minlength="2" maxlength="120" required autocomplete="off"><label for="staff-search-kind">Тип записи</label><select id="staff-search-kind" name="kind"><option value="">Все доступные</option>${scope.kinds.map(kind=>`<option value="${esc(kind)}">${esc(labels[kind])}</option>`).join('')}</select><button class="primary">Найти</button><div id="staff-search-results" role="status"></div></form>`;
    body.querySelector('input').focus();let generation=0;
    body.querySelector('form').onsubmit=async event=>{event.preventDefault();const run=++generation,form=event.currentTarget,results=form.querySelector('#staff-search-results');
      form.querySelector('button').disabled=true;
      try{const values=Object.fromEntries(new FormData(form));if(!values.kind)delete values.kind;
       const data=await api('/admin/search?'+new URLSearchParams(values));if(!dialog.isConnected||run!==generation)return;
       results.innerHTML=data.items.length?data.items.map(item=>`<div class="event"><a href="#${links[item.kind]}/${item.id}"><b>${esc(item.title)}</b></a><p>${esc(labels[item.kind])} · ${esc(item.id)}</p></div>`).join(''):'Нет результатов';
      }catch(error){if(dialog.isConnected)results.textContent=error.message;}
      finally{if(dialog.isConnected)form.querySelector('button').disabled=false;}
    };
   }catch(error){if(dialog.isConnected)body.textContent=error.message;}
  };
  search.tabIndex=0;search.setAttribute('role','button');search.setAttribute('aria-label','Поиск по стране');search.onclick=openSearch;
  searchHotkey=event=>{if((event.ctrlKey||event.metaKey)&&event.key.toLowerCase()==='k'){event.preventDefault();search.click();}};document.addEventListener('keydown',searchHotkey);
  search.onkeydown=event=>{if(['Enter',' '].includes(event.key)){event.preventDefault();openSearch();}};
 }
 const notifications=document.querySelector('.dotmenu');if(notifications){
  notifications.removeAttribute('data-action');notifications.onclick=async()=>{
   const dialog=createDialog('Уведомления сотрудника'),body=dialog.querySelector('#staff-dialog-body');body.textContent='Загрузка…';
   try{
    const data=await api('/me/notifications?limit=20');if(!dialog.isConnected)return;
    body.innerHTML=data.items.length?data.items.map(item=>`<div class="event"><b>${esc(item.type)}</b><p>${esc(item.created_at)}</p>${item.read?'Прочитано':`<button data-notification="${item.id}">Отметить прочитанным</button>`}</div>`).join(''):'Новых уведомлений нет';
    body.querySelectorAll('[data-notification]').forEach(button=>button.onclick=async()=>{button.disabled=true;try{await api('/me/notifications/'+button.dataset.notification+'/read','POST');button.replaceWith(document.createTextNode('Прочитано'));}catch(error){button.disabled=false;const alert=document.createElement('p');alert.role='alert';alert.textContent=error.message;body.append(alert);}});
   }catch(error){if(dialog.isConnected)body.textContent=error.message;}
  };
 }
}
