const phone = window.matchMedia('(max-width: 850px)');
let expanded = false;
function setExpanded(value, restoreFocus = true) {
  const sidebar = document.querySelector('.sidebar');
  const main = document.querySelector('.main');
  const toggle = document.querySelector('[data-action="navigation"]');
  expanded = Boolean(value && phone.matches && sidebar);
  document.body.classList.toggle('mobile-menu-open', expanded);
  sidebar?.classList.toggle('open', expanded);
  if (sidebar) {
    sidebar.inert = phone.matches && !expanded;
    sidebar.setAttribute('aria-hidden', String(phone.matches && !expanded));
    if (expanded) { sidebar.setAttribute('role','dialog'); sidebar.setAttribute('aria-modal','true'); }
    else { sidebar.removeAttribute('role'); sidebar.removeAttribute('aria-modal'); }
  }
  if (main) main.inert = expanded;
  toggle?.setAttribute('aria-expanded', String(expanded));
  const backdrop = document.querySelector('.mobile-menu-backdrop');
  if (backdrop) backdrop.hidden = !expanded;
  if (expanded) sidebar.querySelector('.mobile-menu-close')?.focus();
  else if (restoreFocus && phone.matches) toggle?.focus();
}
export function toggleMobileNavigation() { setExpanded(!expanded); }
export function refreshMobileLayout() {
  const wasExpanded=expanded;
  document.querySelector('.mobile-menu-backdrop')?.remove();
  const sidebar = document.querySelector('.sidebar');
  if (sidebar) {
    sidebar.id = 'admin-navigation';
    sidebar.setAttribute('aria-label', 'Меню админки');
    const close = document.createElement('button');
    close.type='button';close.className='mobile-menu-close';close.textContent='Закрыть меню';
    close.onclick=()=>setExpanded(false);sidebar.prepend(close);
    const backdrop = document.createElement('button');
    backdrop.className='mobile-menu-backdrop';backdrop.type='button';
    backdrop.setAttribute('aria-label','Закрыть меню');backdrop.hidden=true;
    backdrop.onclick=()=>setExpanded(false);document.body.append(backdrop);
    document.querySelector('[data-action="navigation"]')?.setAttribute('aria-controls',sidebar.id);
  }
  document.querySelectorAll('.tablewrap').forEach((wrap, i)=>{
    wrap.tabIndex=0;wrap.setAttribute('role','region');
    const heading=wrap.closest('.card')?.querySelector('h2,h3')?.textContent;
    wrap.setAttribute('aria-label',(heading||'Таблица '+(i+1))+' — можно прокручивать по горизонтали');
    const hint=document.createElement('p');hint.className='mobile-table-hint';
    hint.textContent='Прокрутите таблицу в сторону, чтобы увидеть все столбцы.';
    wrap.before(hint);
  });
  setExpanded(wasExpanded,false);
}
document.addEventListener('click',event=>{if(expanded&&event.target.closest('.sidebar a[href]'))setExpanded(false);});
phone.addEventListener('change',()=>setExpanded(false,false));
window.addEventListener('hashchange',()=>setExpanded(false,false));
document.addEventListener('keydown',event=>{
  if(!expanded)return;
  if(event.key==='Escape'){event.preventDefault();setExpanded(false);}
  if(event.key==='Tab'){
    const items=[...document.querySelectorAll('.sidebar button,.sidebar a[href]')]
        .filter(item=>!item.hidden&&!item.disabled&&item.getClientRects().length);
    if(!items.length)return;
    const first=items[0],last=items.at(-1);
    if(event.shiftKey&&document.activeElement===first){event.preventDefault();last.focus();}
    else if(!event.shiftKey&&document.activeElement===last){event.preventDefault();first.focus();}
  }
});
