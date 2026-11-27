export async function mountAvailability(request,feedback){
 const grid=document.querySelector('.status-grid');if(!grid)return;
 const rows=[...grid.querySelectorAll('.status-row')],history=document.querySelector('.status-history');
 rows.forEach(row=>{row.setAttribute('aria-busy','true');const text=row.querySelector('.left small');if(text)text.textContent='Загрузка данных…';const badge=row.querySelector('.badge');if(badge)badge.textContent='Загрузка';});
 if(history){history.replaceChildren();const p=document.createElement('p');p.textContent='Загрузка текущей конфигурации…';history.append(p);}
 try{
  const data=await request('/public/config');
  rows.forEach((row,index)=>{
   const country=data.countries[index];if(!country){row.remove();return;}
   const text=row.querySelector('.left div');
   if(text){text.replaceChildren();const title=document.createElement('b');title.textContent=country.name;const note=document.createElement('small');note.textContent=country.checkout_enabled?'Оплата разрешена текущей конфигурацией':'Оплата недоступна. Поддержка и управление данными доступны.';text.append(title,note);}
   const badge=row.querySelector('.badge');if(badge)badge.textContent=country.active===true?'Доступен':country.registration_enabled===false?'Отключён':country.stop_new_business===true?'Ограничен':({unverified:'Подготовка',ready:'Доступен',limited:'Ограничен',disabled:'Отключён'})[country.launch_status]||'Статус не подтверждён';
   row.removeAttribute('aria-busy');
  });
  document.querySelectorAll('main .demo-label').forEach(el=>el.textContent='Текущая конфигурация');
  if(history){history.replaceChildren();const p=document.createElement('p');p.textContent='Конфигурация получена '+new Date(data.server_time||Date.now()).toLocaleString('ru')+'. Это время получения данных, а не подтверждение проверки провайдеров.';history.append(p);}
 }catch(error){rows.forEach(row=>row.removeAttribute('aria-busy'));if(history){history.textContent=error.message;history.setAttribute('role','alert');const button=document.createElement('button');button.type='button';button.className='btn outline';button.textContent='Повторить';button.onclick=()=>mountAvailability(request,feedback);history.append(button);}feedback(error.message);}
}
