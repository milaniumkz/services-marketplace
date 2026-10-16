export function mountLegal(request,feedback){
 const paper=document.querySelector('.legal-paper');if(!paper)return;
 const country=document.querySelector('[aria-label="Страна"]'),locale=document.querySelector('[aria-label="Язык"]');
 const countries={'Казахстан':'KZ','Россия':'RU','Беларусь':'BY','Кыргызстан':'KG'},locales={'Русский':'ru','Қазақша':'kk','Беларуская':'be','Српски':'sr'};
 const names={privacy:'Конфиденциальность',terms:'Условия использования',subscriptions:'Подписка и платежи',community:'Правила сообщества'};
 const aliases={privacy:['privacy','privacy_policy'],terms:['terms','terms_of_use'],subscriptions:['subscriptions','subscription','payments'],community:['community','community_rules']};
 let generation=0;
 const select=async()=>{
  const run=++generation,type=names[location.hash.slice(1)]?location.hash.slice(1):'privacy';
  document.querySelectorAll('.legal-menu a[href^="#"]').forEach(a=>{a.removeAttribute('data-demo');a.classList.toggle('selected',a.hash==='#'+type);});
  paper.replaceChildren();paper.setAttribute('aria-busy','true');
  const heading=document.createElement('h2');heading.textContent=names[type];paper.append(heading);
  try{
   const query=new URLSearchParams({country:countries[country.value],locale:locales[locale.value]});
   const data=await request('/legal/documents?'+query);
   if(run!==generation)return;
   const documentVersion=data.items.filter(d=>aliases[type].includes(d.type)).sort((a,b)=>b.created_at.localeCompare(a.created_at))[0];
   const state=document.querySelector('.legal-filter .badge');
   if(state)state.textContent=documentVersion?'Опубликованная версия':'Версия не опубликована';
   const meta=document.createElement('p');meta.className='caption muted';
   if(!documentVersion){meta.textContent='Утверждённый документ для выбранной страны и языка пока не опубликован.';paper.append(meta);return;}
   meta.textContent=country.value+' · '+locale.value+' · версия '+documentVersion.version+' · '+new Date(documentVersion.published_at||documentVersion.created_at).toLocaleDateString('ru');paper.append(meta);
   const content=document.createElement('div');content.style.whiteSpace='pre-wrap';content.textContent=documentVersion.content;paper.append(content);
   const button=document.createElement('button');button.className='btn outline small';button.textContent='Скачать документ';
   button.onclick=()=>{const blob=new Blob([documentVersion.content],{type:'text/plain;charset=utf-8'}),url=URL.createObjectURL(blob),link=document.createElement('a');link.href=url;link.download='JOBA-'+type+'-'+query.get('country')+'-'+query.get('locale')+'-v'+documentVersion.version+'.txt';link.click();setTimeout(()=>URL.revokeObjectURL(url),1000);};paper.append(button);
  }catch(error){if(run!==generation)return;const alert=document.createElement('p');alert.role='alert';alert.textContent=error.message;paper.append(alert);feedback(error.message);}finally{if(run===generation)paper.removeAttribute('aria-busy');}
 };
 country.onchange=select;locale.onchange=select;window.addEventListener('hashchange',select);select();
}
