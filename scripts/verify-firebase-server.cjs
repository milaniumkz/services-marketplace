// Execute inside the API container. Validates FCM without delivering a message.
const {createRequire}=require('node:module');
const load=createRequire('/app/services/api/dist/main.js');
const {applicationDefault,initializeApp}=load('firebase-admin/app');
const {getMessaging}=load('firebase-admin/messaging');
const {firebasePublicConfig}=load('/app/services/api/dist/firebase-push.js');
const timer=setTimeout(()=>{console.log(JSON.stringify({firebase_server_verified:false,timeout:true}));process.exit(1);},45000);
(async()=>{
 const config=firebasePublicConfig();
 if(!config.enabled||config.project_id!=='joba-832c7'||!config.platforms.web||!config.platforms.android||!config.vapid_key)throw Error('Configuration incomplete');
 const credential=applicationDefault();await credential.getAccessToken();
 const app=initializeApp({projectId:config.project_id,credential},'joba-runtime-validation');
 await getMessaging(app).send({topic:'joba-integration-validation',notification:{title:'JOBA',body:'Configuration validation'}},true);
 console.log(JSON.stringify({firebase_server_verified:true,project_id:config.project_id,web_configured:true,android_configured:true,vapid_configured:true,fcm_validate_only:true,actual_message_sent:false}));
})().catch(()=>{console.log(JSON.stringify({firebase_server_verified:false}));process.exitCode=1;}).finally(()=>clearTimeout(timer));
