import privacy from '../../docs/legal/kz/privacy.ru.txt?raw';
import terms from '../../docs/legal/kz/terms.ru.txt?raw';
import payments from '../../docs/legal/kz/payments.ru.txt?raw';
import refunds from '../../docs/legal/kz/refunds.ru.txt?raw';
import public_offer from '../../docs/legal/kz/public_offer.ru.txt?raw';
import contacts from '../../docs/legal/kz/contacts.ru.txt?raw';
const initial={privacy,terms,payments,refunds,public_offer,contacts};
export function mountLegal(request,feedback){
 const paper=document.querySelector('.legal-paper');if(!paper)return;
 const country=document.querySelector('[aria-label="Страна"]'),locale=document.querySelector('[aria-label="Язык"]');
 const countries={'Казахстан':'KZ','Россия':'RU','Беларусь':'BY','Кыргызстан':'KG'},locales={'Русский':'ru','Қазақша':'kk','Беларуская':'be','Српски':'sr'};
 const names={privacy:'Политика конфиденциальности',terms:'Условия использования',payments:'Условия оплаты',refunds:'Возврат и отмена',public_offer:'Публичная оферта',contacts:'Реквизиты и контакты',community:'Правила сообщества'};
 const aliases={privacy:['privacy','privacy_policy'],terms:['terms','terms_of_use'],payments:['payments','subscriptions','subscription'],refunds:['refunds'],public_offer:['public_offer'],contacts:['contacts'],community:['community','community_rules']};
 let generation=0;
 const render=(type,content,meta)=>{paper.replaceChildren();const heading=document.createElement('h2');heading.textContent=names[type];paper.append(heading);const info=document.createElement('p');info.className='caption muted';info.textContent=meta;paper.append(info);const body=document.createElement('div');body.className='legal-content';body.textContent=content;paper.append(body);};
 const download=(type,content,version)=>{const button=document.createElement('button');button.className='btn outline small';button.textContent='Скачать документ';button.onclick=()=>{const blob=new Blob([content],{type:'text/plain;charset=utf-8'}),url=URL.createObjectURL(blob),link=document.createElement('a');link.href=url;link.download='JOBA-'+type+'-'+countries[country.value]+'-'+locales[locale.value]+'-'+version+'.txt';link.click();setTimeout(()=>URL.revokeObjectURL(url),1000);};paper.append(button);};
 const select=async()=>{
  const run=++generation,hash=location.hash.slice(1),requested=hash==='subscriptions'?'payments':hash,type=names[requested]?requested:document.body.dataset.legalType||'privacy';
  document.querySelectorAll('.legal-menu a').forEach(a=>{a.removeAttribute('data-demo');a.classList.toggle('selected',a.hash==='#'+type||!hash&&new URL(a.href).pathname===location.pathname&&!a.hash);});
  const local=countries[country.value]==='KZ'&&locales[locale.value]==='ru'?initial[type]:undefined;
  const state=document.querySelector('.legal-filter .badge');
  if(local){render(type,local,'Казахстан · Русский · редакция сайта от 16.10.2026. Реквизиты заполняются до начала приёма платежей.');download(type,local,'site-2026-10-16');if(state)state.textContent='Редакция сайта';}
  else {render(type,'','Загрузка опубликованной версии…');if(state)state.textContent='Проверка версии';}
  paper.setAttribute('aria-busy','true');
  try{
   const data=await request('/legal/documents?'+new URLSearchParams({country:countries[country.value],locale:locales[locale.value]}));if(run!==generation)return;
   const version=data.items.filter(d=>aliases[type].includes(d.type)).sort((a,b)=>String(b.published_at||b.created_at).localeCompare(String(a.published_at||a.created_at)))[0];
   if(version){render(type,version.content,country.value+' · '+locale.value+' · версия '+version.version+' · '+new Date(version.published_at||version.created_at).toLocaleDateString('ru'));download(type,version.content,'v'+version.version);if(state)state.textContent='Опубликованная версия';}
   else if(!local){render(type,'','Утверждённый документ для выбранной страны и языка пока не опубликован.');if(state)state.textContent='Версия не опубликована';}
  }catch(error){if(run!==generation)return;const alert=document.createElement('p');alert.role='alert';alert.textContent=local?'Не удалось проверить обновления документа. Показана редакция сайта.':error.message;paper.append(alert);if(!local)feedback(error.message);}finally{if(run===generation)paper.removeAttribute('aria-busy');}
 };
 country.onchange=select;locale.onchange=select;window.addEventListener('hashchange',select);select();
}
