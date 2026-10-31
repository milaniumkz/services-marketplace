// Execute inside the API container. Validates FCM without delivering a message.
const {createRequire}=require('node:module');
const load=createRequire('/app/services/api/dist/main.js');
const {applicationDefault,initializeApp}=load('firebase-admin/app');
const {getMessaging}=load('firebase-admin/messaging');
const {firebasePublicConfig}=load('/app/services/api/dist/firebase-push.js');
const timer=setTimeout(()=>{console.log(JSON.stringify({firebase_server_verified:false,timeout:true}));process.exit(1);},45000);
(async()=>{
 const {Pool}=load('pg');const pool=new Pool({connectionString:process.env.DATABASE_URL});
 try {
  const devices=await pool.query("SELECT data->>'platform' AS platform,data->>'status' AS status,count(*)::int AS count FROM records WHERE kind='push_token' GROUP BY 1,2");
  const eligible=await pool.query("SELECT count(*)::int AS count FROM records p WHERE p.kind='push_token' AND p.data->>'status'='active' AND EXISTS(SELECT 1 FROM tokens t WHERE t.family::text=p.data->>'session_family' AND t.user_id::text=p.owner AND t.country=p.country AND t.kind='refresh' AND NOT t.revoked AND NOT t.used AND t.expires_at>CURRENT_TIMESTAMP)");
  const queue=await pool.query("SELECT data->>'type' AS type,data->>'status' AS status,data->>'failure_code' AS failure_code,count(*)::int AS count FROM records WHERE kind='outbox' GROUP BY 1,2,3 ORDER BY 1,2");
  const missing=await pool.query("SELECT n.data->>'type' AS type,count(*)::int AS count FROM records n WHERE n.kind='notification' AND NOT EXISTS(SELECT 1 FROM records o WHERE o.kind='outbox' AND o.data->>'event_id'=n.id::text) GROUP BY 1");
  console.log(JSON.stringify({push_delivery_diagnostics:true,devices:devices.rows,eligible_devices:eligible.rows[0].count,queue:queue.rows,notifications_without_outbox:missing.rows}));
 }finally{await pool.end();}
 const config=firebasePublicConfig();
 if(!config.enabled||config.project_id!=='joba-832c7'||!config.platforms.web||!config.platforms.android||!config.vapid_key)throw Error('Configuration incomplete');
 const credential=applicationDefault();await credential.getAccessToken();
 const app=initializeApp({projectId:config.project_id,credential},'joba-runtime-validation');
 await getMessaging(app).send({topic:'joba-integration-validation',notification:{title:'JOBA',body:'Configuration validation'}},true);
 console.log(JSON.stringify({firebase_server_verified:true,project_id:config.project_id,web_configured:true,android_configured:true,vapid_configured:true,fcm_validate_only:true,actual_message_sent:false}));
})().catch(()=>{console.log(JSON.stringify({firebase_server_verified:false}));process.exitCode=1;}).finally(()=>clearTimeout(timer));
