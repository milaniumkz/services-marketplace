// Real FCM delivery to this job's disposable browser, never a customer's device.
const {chromium}=require('@playwright/test'),fs=require('node:fs'),path=require('node:path'),crypto=require('node:crypto');
const root=process.env.RUNNER_TEMP,tokenFile=path.join(root,'joba-browser-smoke-token.json'),sent=path.join(root,'joba-browser-smoke-sent'),result=path.join(root,'joba-browser-smoke-result.json');
const delay=ms=>new Promise(r=>setTimeout(r,ms));let browser,token,success=false;
const watchdog=setTimeout(()=>{fs.writeFileSync(result,JSON.stringify({received_system_notification:false,phase:'timeout'})+'\n');process.exit(1);},120000);
(async()=>{
 browser=await chromium.launchPersistentContext(path.join(root,'joba-push-browser'),{channel:'chrome',headless:true,permissions:['notifications'],ignoreDefaultArgs:['--disable-background-networking'],args:['--no-sandbox']});
 const page=await browser.newPage();await page.goto('https://joba.com.kz/',{waitUntil:'domcontentloaded'});
 await page.addScriptTag({url:'https://www.gstatic.com/firebasejs/12.19.0/firebase-app-compat.js'});await page.addScriptTag({url:'https://www.gstatic.com/firebasejs/12.19.0/firebase-messaging-compat.js'});
 token=await page.evaluate(async()=>{const {data:c}=await(await fetch('/api/v1/public/push-config')).json();if(!c.enabled||Notification.permission!=='granted')throw Error('Browser permission not ready');firebase.initializeApp(c.platforms.web);const registration=await navigator.serviceWorker.register('/firebase-messaging-sw.js',{scope:'/firebase-cloud-messaging-push-scope'});if(!registration.active)await new Promise((resolve,reject)=>{const worker=registration.installing||registration.waiting;if(!worker)return resolve();worker.addEventListener('statechange',()=>{if(worker.state==='activated')resolve();if(worker.state==='redundant')reject(Error('Worker activation failed'));});});return await firebase.messaging().getToken({vapidKey:c.vapid_key,serviceWorkerRegistration:registration});});
 if(!token)throw Error('Browser token missing');
 const event='smoke-'+crypto.randomUUID();const session=await browser.newCDPSession(page);await session.send('ServiceWorker.enable');await page.goto('about:blank');await session.send('ServiceWorker.stopAllWorkers');
 fs.writeFileSync(tokenFile,JSON.stringify({token,event_id:event}),{mode:0o600});
 for(let i=0;i<90&&!fs.existsSync(sent);i++)await delay(1000);
 if(!fs.existsSync(sent))throw Error('Sender did not accept test message');
 // Keep all JOBA windows closed during receipt so that real background display is exercised.
 await delay(15000);
 for(let i=0;i<5;i++){
  await page.goto('https://joba.com.kz/',{waitUntil:'domcontentloaded'});
  const received=await page.evaluate(async tag=>{const registration=await navigator.serviceWorker.getRegistration('/firebase-cloud-messaging-push-scope');if(!registration)return false;const notifications=await registration.getNotifications({tag});const found=notifications.length>0;for(const n of notifications)n.close();return found;},event);
  if(received){success=true;break;}
  await page.goto('about:blank');await delay(5000);
 }
 if(!success)throw Error('No system notification received after cold worker restart');
 fs.writeFileSync(result,JSON.stringify({actual_fcm_message_sent:true,isolated_browser_recipient:true,received_system_notification:true,cold_worker_restart:true})+'\n');
})().catch(()=>{fs.writeFileSync(result,JSON.stringify({received_system_notification:false,phase:token?'delivery':'browser_registration'})+'\n');process.exitCode=1;}).finally(async()=>{clearTimeout(watchdog);if(browser){
 try{const cleanup=await browser.newPage();await cleanup.goto('https://joba.com.kz/',{waitUntil:'domcontentloaded',timeout:10000});await cleanup.evaluate(async()=>{const registration=await navigator.serviceWorker.getRegistration('/firebase-cloud-messaging-push-scope');const subscription=await registration?.pushManager.getSubscription();await subscription?.unsubscribe();await registration?.unregister();});}catch{}
 await browser.close();
 }fs.rmSync(tokenFile,{force:true});});
