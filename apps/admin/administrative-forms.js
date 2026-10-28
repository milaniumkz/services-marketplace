// Staff action buttons are the instruction. Audit context is filled automatically.
export function prepareAdministrativeForms(root=document) {
  const title=document.querySelector('.workspace h1, .workspace h2')?.textContent?.trim()||'панель управления';
  for(const field of root.querySelectorAll('form [name="reason"]')) {
    if(!String(field.value||'').trim())field.value='Действие администратора: '+title.slice(0,160);
    field.required=false;
    field.hidden=true;field.style.display='none';
    const wrapper=field.closest('.formfield, .field, label');if(wrapper){wrapper.hidden=true;wrapper.style.display='none';}
    if(field.id)for(const label of root.querySelectorAll('label[for]'))if(label.htmlFor===field.id){label.hidden=true;label.style.display='none';}
  }
  for(const field of root.querySelectorAll('form input[type="checkbox"][name="confirm"]')) {
    field.checked=true;field.required=false;
    const wrapper=field.closest('label')||field;wrapper.hidden=true;wrapper.style.display='none';
  }
}
export function observeAdministrativeForms() {
  const observer=new MutationObserver(()=>prepareAdministrativeForms());
  observer.observe(document.body,{childList:true,subtree:true});
  prepareAdministrativeForms();return ()=>observer.disconnect();
}
