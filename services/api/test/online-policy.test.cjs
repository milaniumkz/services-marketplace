const {test}=require('node:test'),assert=require('node:assert/strict'),{randomUUID}=require('node:crypto');
const {OnlinePresence}=require('../dist/online-presence');
const {Marketplace}=require('../dist/marketplace'),{Store}=require('../dist/store');
test('online counter counts live people once, expires stale connections and excludes staff and inactive accounts',()=>{
 let now=1000;const p=new OnlinePresence(()=>now);p.connect('a',{id:'user',status:'active'});p.connect('b',{id:'user',status:'active'});p.connect('c',{id:'other',status:'active'});p.connect('staff',{id:'staff',status:'active',staff_permissions:['administrator']});p.connect('blocked',{id:'blocked',status:'blocked'});assert.equal(p.count(),2);p.disconnect('a');assert.equal(p.count(),2);p.disconnect('b');assert.equal(p.count(),1);now+=64000;p.heartbeat('c');now+=64000;assert.equal(p.count(),1);now+=2000;assert.equal(p.count(),0);
});
test('policy editing preserves original acceptance and timestamps; withdrawal remains explicit and optional processing remains versioned',async()=>{
 const api=new Marketplace(new Store('memory://'));await api.initialize();try{
 const s=await api.handle('POST','/auth/register',{country:'KZ',phone:'+77000000921',password:'Policy update fixture password'});const call=(m,p,b={})=>api.handle(m,p,b,'Bearer '+s.access_token,randomUUID());
 const row=(kind,data)=>({id:randomUUID(),kind,country:'KZ',owner:s.user.id,version:1,created_at:new Date().toISOString(),...data});
 const doc=await api.store.put(row('legal_document',{type:'terms',locale:'ru',status:'published',content:'Первоначальные условия',hash:'original-hash',minimum_age:18,published_at:'2099-01-01T00:00:00Z'}));
 const consent=await call('POST','/me/consents',{document_id:doc.id,document_hash:doc.hash,accepted:true,age_confirmed:true});
 await api.store.put({...doc,content:'Новая редакция',hash:'new-hash',version:2});
 await api.store.put(row('grant',{role:'customer',plan:'customer',valid_until:new Date(Date.now()+86400000).toISOString(),capabilities:['publish_order']}));
 const category=(await call('GET','/catalog/categories')).items[0].id;
 let order=await call('POST','/orders',{title:'Проверка принятой политики',description:'Описание заказа для проверки новой редакции документов.',city:'Астана',category_id:category});
 order=await call('POST','/orders/'+order.id+'/publish',{expected_version:order.version});assert.equal(order.status,'open');assert.deepEqual(await api.store.get(consent.id),consent);
 const next={...doc,id:randomUUID(),hash:'third-hash',published_at:'2099-02-01T00:00:00Z'};await api.store.put(next);
 let second=await call('POST','/orders',{title:'Повторный заказ',description:'Описание заказа для проверки новой редакции документов.',city:'Астана',category_id:category});second=await call('POST','/orders/'+second.id+'/publish',{expected_version:second.version});assert.equal(second.status,'open');
 await call('POST','/me/consents',{document_id:next.id,document_hash:next.hash,accepted:false});
 let third=await call('POST','/orders',{title:'Заказ после отзыва',description:'Описание заказа после явного отзыва согласия.',city:'Астана',category_id:category});await assert.rejects(()=>call('POST','/orders/'+third.id+'/publish',{expected_version:third.version}),e=>e.getResponse().error.code==='CONSENT_REQUIRED');
 const online=await api.handle('GET','/public/online');assert.equal(online.count,0);assert.equal(online.window_seconds,65);assert.equal(typeof online.server_time,'string');
 }finally{await api.store.close();}
});
test('real authenticated websocket connections update online count and deduplicate two devices',async()=>{
 const {createServer}=require('node:http'),WebSocket=require('ws'),{startRealtime}=require('../dist/realtime');const api=new Marketplace(new Store('memory://'));await api.initialize();const server=createServer((q,r)=>r.end());await new Promise(resolve=>server.listen(0,'127.0.0.1',resolve));const stop=startRealtime(server,api),clients=[];
 try{const s=await api.handle('POST','/auth/register',{country:'KZ',phone:'+77000000922',password:'Online websocket fixture password'});const connect=()=>new Promise((resolve,reject)=>{const ws=new WebSocket('ws://127.0.0.1:'+server.address().port+'/api/v1/events/ws',['joba.v1','auth.'+s.access_token]);clients.push(ws);ws.once('open',()=>resolve(ws));ws.once('error',reject);});await connect();await connect();assert.equal((await api.handle('GET','/public/online')).count,1);clients[0].close();await new Promise(resolve=>clients[0].once('close',resolve));assert.equal((await api.handle('GET','/public/online')).count,1);clients[1].close();await new Promise(resolve=>clients[1].once('close',resolve));await new Promise(resolve=>setTimeout(resolve,25));assert.equal((await api.handle('GET','/public/online')).count,0);
 }finally{for(const ws of clients)ws.terminate();stop();await new Promise(resolve=>server.close(resolve));await api.store.close();}
});
