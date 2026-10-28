const {test}=require('node:test');
const assert=require('node:assert/strict');
const {firebasePublicConfig,firebaseMessage}=require('../dist/firebase-push');
test('Firebase public config cannot publish credentials and validates project isolation',()=>{
 const env={JOBA_FIREBASE_ENABLED:'1',JOBA_FIREBASE_PROJECT_ID:'joba-832c7',JOBA_FIREBASE_VAPID_KEY:'public-vapid',JOBA_FIREBASE_WEB_CONFIG:JSON.stringify({apiKey:'public-api',appId:'app',projectId:'joba-832c7',messagingSenderId:'sender',private_key:'must-not-leak',client_email:'private-account'})};
 const config=firebasePublicConfig(env);
 assert.equal(config.enabled,true);assert.equal(config.platforms.web.projectId,'joba-832c7');assert.equal(JSON.stringify(config).includes('must-not-leak'),false);assert.equal(JSON.stringify(config).includes('client_email'),false);
 assert.throws(()=>firebasePublicConfig({...env,JOBA_FIREBASE_PROJECT_ID:'another-project'}));
 assert.equal(firebasePublicConfig({}).enabled,false);
});
test('FCM payload supports Android, Apple and HTTPS web without arbitrary redirect',()=>{
 const message=firebaseMessage('device-token',{event_id:'event-1',title:'JOBA',body:'Новое событие',deep_link:{route:'https://evil.example',id:'secret'}});
 assert.equal(message.token,'device-token');assert.equal(message.android.priority,'high');assert.equal(message.apns.payload.aps.sound,'default');assert.equal(message.data.route,'notifications');assert.equal(message.webpush.fcmOptions.link,'https://joba.com.kz/?joba_push=notifications');assert.equal(JSON.stringify(message).includes('evil.example'),false);assert.equal(JSON.stringify(message).includes('secret'),false);
});
