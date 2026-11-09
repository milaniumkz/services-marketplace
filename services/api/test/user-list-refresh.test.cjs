const {test}=require('node:test'),assert=require('node:assert/strict'),{pathToFileURL}=require('node:url'),path=require('node:path');
test('idle user list refreshes after returning to tab, but never disrupts forms, dialogs, filters or a pending request',async()=>{
 const {watchUserList}=await import(pathToFileURL(path.resolve(__dirname,'../../../apps/admin/user-list-refresh.js')));let selected=true,dialog=false,typing=false,resolve,refreshes=0,tick;
 const win=new EventTarget();win.setInterval=f=>(tick=f,1);win.clearInterval=()=>{};const doc=new EventTarget();doc.hidden=false;doc.querySelector=()=>dialog?{}:null;doc.activeElement={closest:()=>typing?{}:null};
 const stop=watchUserList({win,doc,canRefresh:()=>selected,refresh:()=>{refreshes++;return new Promise(r=>resolve=r)}});
 doc.hidden=true;tick();assert.equal(refreshes,0);doc.hidden=false;typing=true;win.dispatchEvent(new Event('focus'));assert.equal(refreshes,0);typing=false;dialog=true;tick();assert.equal(refreshes,0);dialog=false;selected=false;tick();assert.equal(refreshes,0);selected=true;
 win.dispatchEvent(new Event('focus'));assert.equal(refreshes,1);tick();assert.equal(refreshes,1);resolve();await Promise.resolve();tick();assert.equal(refreshes,2);resolve();await Promise.resolve();stop();win.dispatchEvent(new Event('focus'));assert.equal(refreshes,2);
});
