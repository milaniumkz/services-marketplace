/** Refresh an idle first page, never close a form/dialog or reset chosen filters. */
export function watchUserList({canRefresh,refresh,win=window,doc=document,interval=30000}) {
 let busy=false;
 async function update(){
  if(busy||doc.hidden||!canRefresh()||doc.querySelector('[role="dialog"],dialog[open],.modal,.workspace[aria-busy="true"]')||doc.activeElement?.closest('.workspace input,.workspace textarea,.workspace select'))return;
  busy=true;try{await refresh();}finally{busy=false;}
 }
 const timer=win.setInterval(()=>void update(),interval);
 win.addEventListener('focus',update);doc.addEventListener('visibilitychange',update);
 return ()=>{win.clearInterval(timer);win.removeEventListener('focus',update);doc.removeEventListener('visibilitychange',update);};
}
