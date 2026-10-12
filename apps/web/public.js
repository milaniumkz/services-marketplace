const countryCodes={'Казахстан':'KZ','Россия':'RU','Беларусь':'BY','Сербия':'RS'};
let recovery;
function feedback(message) {
  let el=document.querySelector('.toast');
  if(!el){el=document.createElement('div');el.className='toast';document.body.append(el);}
  el.textContent=message;el.role='status';el.classList.add('show');
  window.setTimeout(()=>el.classList.remove('show'),6000);
}
async function request(path,method='GET',body) {
  const r=await fetch('/api/v1'+path,{method,headers:{'Content-Type':'application/json',...(recovery?{Authorization:'Bearer '+recovery.capability}:{})},body:body?JSON.stringify(body):undefined});
  const j=await r.json();if(!r.ok)throw Error(j.error?.message??'Сервис недоступен');return j.data;
}
document.addEventListener('click',e=>{
  const b=e.target.closest('[data-demo]');if(!b)return;
  e.preventDefault();feedback('Этот внешний сервис ещё не подключён. Действие не выполнено.');
});
const form=document.querySelector('form');
if(form)form.onsubmit=async e=>{
  e.preventDefault();const button=form.querySelector('button[type=submit]');button.disabled=true;
  try {
    const text=document.getElementById('message').value;
    if(!text.trim())throw Error('Введите сообщение');
    if(!recovery) {
      recovery=await request('/public/recovery-threads','POST',{country:countryCodes[document.getElementById('region').value],subject:document.getElementById('subject').value,text});
      const history=document.createElement('div');history.id='recovery-history';history.className='card';form.before(history);
      const note=document.createElement('p');note.className='helper';note.textContent='Обращение создано. Сохраните эту вкладку: доступ к переписке действует 24 часа.';form.before(note);
      document.getElementById('region').disabled=true;document.getElementById('subject').disabled=true;
    } else await request('/public/recovery-threads/'+recovery.id+'/messages','POST',{text});
    const history=await request('/public/recovery-threads/'+recovery.id+'/messages');
    const container=document.getElementById('recovery-history');container.replaceChildren();
    for(const m of history.items){const p=document.createElement('p');p.textContent=m.text;container.append(p);}
    document.getElementById('message').value='';feedback('Сообщение сохранено в обращении');
  }catch(e){feedback(e.message);}finally{button.disabled=false;}
};
