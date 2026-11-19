import {mountAvailability} from './availability.js';
import {mountLegal} from './legal.js';
const countryCodes={'Казахстан':'KZ','Россия':'RU','Беларусь':'BY','Кыргызстан':'KG'};
let recovery;
try {const saved=JSON.parse(sessionStorage.getItem('joba.recovery')||'null');if(saved?.expires_at>Date.now()&&typeof saved.id==='string'&&typeof saved.capability==='string')recovery=saved;else sessionStorage.removeItem('joba.recovery');}catch{sessionStorage.removeItem('joba.recovery');}
const pending=new Map();
function feedback(message) {
  let el=document.querySelector('.toast');
  if(!el){el=document.createElement('div');el.className='toast';document.body.append(el);}
  el.textContent=message;el.role='status';el.classList.add('show');
  window.setTimeout(()=>el.classList.remove('show'),6000);
}
async function request(path,method='GET',body) {
  const mutation=method!=='GET',fingerprint=path+':'+JSON.stringify(body||{}),key=mutation?(pending.get(fingerprint)||crypto.randomUUID()):undefined;
  if(key)pending.set(fingerprint,key);
  while(pending.size>100)pending.delete(pending.keys().next().value);
  const controller=new AbortController(),timer=setTimeout(()=>controller.abort(),20000);
  try {
    const r=await fetch('/api/v1'+path,{method,signal:controller.signal,redirect:'error',headers:{'Content-Type':'application/json',...(key?{'Idempotency-Key':key}:{}),...(recovery?{Authorization:'Bearer '+recovery.capability}:{})},body:body?JSON.stringify(body):undefined});
    const j=await r.json();if(!r.ok){if(r.status<500)pending.delete(fingerprint);throw Error(j.error?.message??'Сервис недоступен');}
    pending.delete(fingerprint);return j.data;
  }catch(error){if(error.name==='AbortError')throw Error('Сервис не ответил вовремя. Повторите действие.');if(error instanceof TypeError)throw Error('Нет соединения. Повторите действие.');throw error;}finally{clearTimeout(timer);}

}
document.addEventListener('click',e=>{
  const b=e.target.closest('[data-demo]');if(!b)return;
  e.preventDefault();feedback('Этот внешний сервис ещё не подключён. Действие не выполнено.');
});
const form=document.querySelector('form');
async function showHistory(){
  if(!form||!recovery)return;
  let container=document.getElementById('recovery-history');
  if(!container){container=document.createElement('div');container.id='recovery-history';container.className='card';container.setAttribute('aria-live','polite');form.before(container);}
  const history=await request('/public/recovery-threads/'+recovery.id+'/messages');
  container.replaceChildren();for(const m of history.items){const p=document.createElement('p');p.textContent=m.text;container.append(p);}
}
if(form&&recovery){document.getElementById('region').disabled=true;document.getElementById('subject').disabled=true;showHistory().catch(error=>feedback(error.message));}

if(form)form.onsubmit=async e=>{
  e.preventDefault();const button=form.querySelector('button[type=submit]');button.disabled=true;
  try {
    const text=document.getElementById('message').value;
    if(!text.trim())throw Error('Введите сообщение');
    if(!recovery) {
      recovery=await request('/public/recovery-threads','POST',{country:countryCodes[document.getElementById('region').value],subject:document.getElementById('subject').value,text});
      recovery.expires_at=Date.now()+86400000;sessionStorage.setItem('joba.recovery',JSON.stringify(recovery));
      const note=document.createElement('p');note.className='helper';note.textContent='Обращение создано. Сохраните эту вкладку: доступ к переписке действует 24 часа.';form.before(note);
      document.getElementById('region').disabled=true;document.getElementById('subject').disabled=true;
    } else await request('/public/recovery-threads/'+recovery.id+'/messages','POST',{text});
    await showHistory();
    document.getElementById('message').value='';feedback('Сообщение сохранено в обращении');
  }catch(e){feedback(e.message);}finally{button.disabled=false;}
};

mountLegal(request,feedback);

mountAvailability(request,feedback);
