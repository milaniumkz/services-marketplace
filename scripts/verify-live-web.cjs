const {mkdir,writeFile}=require('node:fs/promises');
const {chromium}=require('@playwright/test');
const assert=require('node:assert/strict');
(async()=>{
 const base=process.env.JOBA_LIVE_URL||'https://188-241-217-228.sslip.io';assert.ok(base.startsWith('https://'));
 let ready=false;
 for(let n=0;n<75;n++){
  try{const r=await fetch(base+'/health',{signal:AbortSignal.timeout(10000)});const h=await r.json();if(r.ok&&h.mode==='production'&&h.database==='ready'){ready=true;break;}}catch{}
  await new Promise(resolve=>setTimeout(resolve,10000));
 }
 assert.ok(ready,'Production HTTPS did not become ready');
 for(const path of ['/api/v1/public/config?country=KZ','/assets/fonts/NotoSans-Regular.ttf','/assets/fonts/MaterialIcons-Regular.otf'])assert.equal((await fetch(base+path)).status,200,path);
 await mkdir('live-web-report',{recursive:true});
 const browser=await chromium.launch({executablePath:process.env.JOBA_CHROMIUM_PATH||'/usr/bin/google-chrome',args:['--no-sandbox']});
 const errors=[];let render;
 try{
  const page=await browser.newPage({viewport:{width:390,height:844}});page.on('pageerror',error=>errors.push(error.message));
  const start=Date.now();await page.goto(base,{waitUntil:'domcontentloaded'});await page.locator('flutter-view').waitFor({timeout:60000});
  const access=page.locator('flt-semantics-placeholder');if(await access.count())await access.evaluate(element=>element.click());
  await page.getByRole('button',{name:'Продолжить',exact:true}).waitFor({timeout:30000});render=Date.now()-start;
  await page.screenshot({path:'live-web-report/welcome.png'});
  await page.getByRole('button',{name:'Продолжить',exact:true}).click();await page.getByText('С возвращением',{exact:true}).waitFor();
  await page.screenshot({path:'live-web-report/login.png'});
  await page.goto(base+'/admin/');await page.getByLabel('Рабочий идентификатор').waitFor();await page.screenshot({path:'live-web-report/admin.png'});
  await page.goto(base+'/site/');await page.getByRole('heading').first().waitFor();assert.deepEqual(errors,[]);
 }finally{await browser.close();}
 const result={url:base,https_certificate_verified:true,production_database_ready:true,welcome_continue_opens_login:true,admin_login_available:true,public_site_available:true,first_render_ms:render,errors};
 await writeFile('live-web-report/result.json',JSON.stringify(result,null,2));console.log('Verified live HTTPS web:',JSON.stringify(result));
 if(process.env.GITHUB_TOKEN){const r=await fetch('https://api.github.com/repos/'+process.env.GITHUB_REPOSITORY+'/check-runs',{method:'POST',headers:{authorization:'Bearer '+process.env.GITHUB_TOKEN,'content-type':'application/json',accept:'application/vnd.github+json'},body:JSON.stringify({name:'live-https-web-verification',head_sha:process.env.GITHUB_SHA,status:'completed',conclusion:'success',output:{title:'Live HTTPS web verified',summary:JSON.stringify(result)}})});assert.ok(r.ok,'Could not publish live verification result');}
})().catch(error=>{console.error(error);process.exitCode=1;});
