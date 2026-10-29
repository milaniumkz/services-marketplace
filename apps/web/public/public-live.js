const legacy={terms:'terms.html',subscriptions:'payments.html',privacy:'privacy.html',community:'safety.html'};
function openLegacyDocument(){if(location.pathname.endsWith('W03.html')&&legacy[location.hash.slice(1)])location.replace('/site/'+legacy[location.hash.slice(1)]+location.search);}
window.addEventListener('hashchange',openLegacyDocument);
openLegacyDocument();
const form=document.getElementById('public-support-form');
if(form){
 form.querySelector('button').disabled=false;
 const state=document.getElementById('support-status'),history=document.getElementById('support-history');let thread;
 try{const saved=JSON.parse(sessionStorage.getItem('joba.public.support')||'null');if(saved?.expires_at>Date.now())thread=saved;}catch{}
 const pending=new Map();
 async function request(path,body){
  const key=JSON.stringify([path,body]);if(body&&!pending.has(key))pending.set(key,crypto.randomUUID());
  const response=await fetch('/api/v1'+path,{method:body?'POST':'GET',redirect:'error',signal:AbortSignal.timeout(20000),headers:{'Content-Type':'application/json',...(body?{'Idempotency-Key':pending.get(key)}:{}),...(thread?{Authorization:'Bearer '+thread.capability}:{})},body:body?JSON.stringify(body):undefined});
  const result=await response.json();if(!response.ok){if(response.status<500&&response.status!==429)pending.delete(key);throw Error(result.error?.message||'Не удалось отправить обращение.');}pending.delete(key);return result.data;
 }
 function showMessage(text,error=false){state.textContent=text;state.dataset.error=String(error);}
 async function load(){
  if(!thread)return;const data=await request('/public/recovery-threads/'+thread.id+'/messages');history.replaceChildren();
  const h=document.createElement('h2');h.textContent='Переписка по обращению';history.append(h);
  for(const m of data.items){const p=document.createElement('p');p.textContent=m.text;history.append(p);}
  form.elements.country.disabled=true;form.elements.subject.disabled=true;form.querySelector('button').textContent='Отправить сообщение';
 }
 if(thread)load().catch(error=>showMessage(error.message,true));
 form.onsubmit=async event=>{
  event.preventDefault();const button=form.querySelector('button'),values=Object.fromEntries(new FormData(form));button.disabled=true;
  try{
   if(!String(values.text||'').trim())throw Error('Введите сообщение.');
   if(!thread){thread=await request('/public/recovery-threads',{country:values.country,subject:values.subject,text:values.text});thread.expires_at=Date.now()+86400000;sessionStorage.setItem('joba.public.support',JSON.stringify(thread));}
   else await request('/public/recovery-threads/'+thread.id+'/messages',{text:values.text});
   await load();form.elements.text.value='';showMessage('Обращение сохранено. Сохраните эту вкладку для переписки; доступ к обращению действует 24 часа.');
  }catch(error){showMessage(error.message||'Нет соединения с сервером. Повторите отправку.',true);}finally{button.disabled=false;}
 };
}
