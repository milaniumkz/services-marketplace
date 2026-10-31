const{test}=require('node:test'),assert=require('node:assert/strict'),vm=require('node:vm'),fs=require('node:fs');
const source=fs.readFileSync('apps/mobile/web/firebase-messaging-sw.js','utf8');
test('terminated service worker installs Firebase push handlers synchronously before a cold push',()=>{
 for(let restart=0;restart<2;restart++){
  const handlers=new Map(),shown=[];let initialized=false;
  const context={self:{clients:{claim:async()=>{},openWindow:async()=>{}},addEventListener:(type,cb)=>handlers.set(type,cb)},firebase:{initializeApp:config=>{assert.equal(config.projectId,'isolated-project');initialized=true;},messaging:()=>{assert.ok(initialized);handlers.set('push',event=>shown.push(event));}},importScripts:url=>{if(url.endsWith('push-worker-config.js'))context.self.JOBA_FIREBASE_CONFIG={projectId:'isolated-project'};},fetch:()=>{throw Error('Asynchronous fetch loses a cold push event');}};
  vm.runInNewContext(source,context);assert.ok(handlers.has('push'));handlers.get('push')({id:'cold-push'});assert.equal(shown.length,1);
 }
});
test('foreground notification click opens the protected notifications route',async()=>{
 const handlers=new Map(),opened=[];let closed=false,stopped=false,pending;
 const context={self:{clients:{claim:async()=>{},openWindow:async url=>opened.push(url)},addEventListener:(type,cb)=>handlers.set(type,cb)},firebase:{initializeApp:()=>{},messaging:()=>{}},importScripts:()=>{}};
 vm.runInNewContext(source,context);handlers.get('notificationclick')({notification:{data:{joba:true},close:()=>closed=true},stopImmediatePropagation:()=>stopped=true,waitUntil:p=>pending=p});await pending;
 assert.ok(closed&&stopped);assert.deepEqual(opened,['/?joba_push=notifications']);
});
