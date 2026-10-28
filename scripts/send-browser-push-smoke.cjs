const{createRequire}=require('node:module'),fs=require('node:fs');const load=createRequire('/app/services/api/dist/main.js');const{FirebasePushProvider}=load('/app/services/api/dist/firebase-push.js');
const file='/tmp/joba-browser-smoke-token.json';const data=JSON.parse(fs.readFileSync(file,'utf8'));
if(typeof data.token!=='string'||data.token.length<20||!/^smoke-[0-9a-f-]{36}$/.test(data.event_id))throw Error('Invalid isolated browser request');
const timer=setTimeout(()=>process.exit(1),30000);
new FirebasePushProvider('joba-832c7').send(data.token,{event_id:data.event_id,title:'JOBA',body:'Изолированная проверка доставки уведомления'}).then(()=>console.log(JSON.stringify({isolated_browser_message_accepted:true}))).catch(()=>{console.log(JSON.stringify({isolated_browser_message_accepted:false}));process.exitCode=1;}).finally(()=>{clearTimeout(timer);fs.rmSync(file,{force:true});});
