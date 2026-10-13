const {mkdtemp,rm}=require('node:fs/promises');
const {tmpdir}=require('node:os');
const {join,resolve}=require('node:path');
const {randomUUID,randomBytes}=require('node:crypto');
const {hash}=require('@node-rs/argon2');
const {chromium}=require('@playwright/test');
const assert=require('node:assert/strict');
async function main(){
 const files=await mkdtemp(join(tmpdir(),'joba-admin-browser-'));
 process.env.JOBA_DATA_DIR='memory://';process.env.JOBA_UPLOAD_DIR=files;delete process.env.DATABASE_URL;
 const {NestFactory}=require('@nestjs/core');
 const {AppModule,getMarketplace}=require('../services/api/dist/app.module');
 const {totp}=require('../services/api/dist/totp');
 const app=await NestFactory.create(AppModule,{logger:false});const marketplace=await getMarketplace();
 let browser,page,vite;
 try{
  const id=randomUUID(),secret=randomBytes(20).toString('hex'),password=randomBytes(32).toString('base64url');
  await marketplace.store.put({id,kind:'user',owner:id,country:'KZ',version:1,created_at:new Date().toISOString(),display_name:'Изолированный сотрудник',phone:'staff-browser-test',roles:['customer'],staff_permissions:['administrator'],totp_secret:secret,status:'active',fixture:true});
  await marketplace.store.db.query('INSERT INTO credentials(country,phone,user_id,password_hash) VALUES($1,$2,$3,$4)',['KZ','staff-browser-test',id,await hash(password)]);
  await app.listen(0,'127.0.0.1');const origin=await app.getUrl();
  browser=await chromium.launch({executablePath:process.env.JOBA_CHROMIUM_PATH||'/usr/bin/chromium',args:['--no-sandbox']});
  page=await browser.newPage({viewport:{width:1440,height:1000}});
  // Redirect transport to an isolated real HTTP API; response data are never mocked.
  await page.route('**/api/v1/**',async route=>{
   const request=route.request(),url=new URL(request.url());
   const response=await fetch(origin+url.pathname+url.search,{method:request.method(),headers:request.headers(),body:['GET','HEAD'].includes(request.method())?undefined:request.postData()});
   await route.fulfill({status:response.status,headers:{'content-type':'application/json'},body:await response.text()});
  });
  let frontend=process.env.JOBA_ADMIN_TEST_URL;
  if(!frontend){const {createServer}=await import('vite');vite=await createServer({root:resolve(__dirname,'../apps/admin'),server:{port:0,strictPort:false,host:'127.0.0.1'}});await vite.listen();frontend='http://127.0.0.1:'+vite.httpServer.address().port;}
  await page.goto(frontend+'/#login');
  assert.equal(await page.locator('.loginbrand').count(),1);
  await page.getByLabel('Рабочий идентификатор').fill('staff-browser-test');await page.getByLabel('Пароль',{exact:true}).fill(password);
  await page.getByRole('button',{name:'Продолжить',exact:true}).click();
  await page.getByLabel('Код второго фактора').fill(totp(secret));await page.getByRole('button',{name:'Продолжить',exact:true}).click();
  await page.waitForSelector('#staff-logout');assert.equal(await page.locator('.account b').textContent(),'Изолированный сотрудник');
  await page.locator('.nav a[href="#monetization"]').click();
  await page.getByLabel('Название',{exact:true}).fill('Проверка реального черновика');
  await page.getByLabel('Причина',{exact:true}).fill('Изолированная проверка интерфейса');
  await page.getByLabel('Параметры JSON').fill(JSON.stringify({subscription_enabled:true,banner_ads_enabled:false,rewarded_access_enabled:false}));
  await page.getByRole('button',{name:'Сохранить черновик'}).click();
  await page.getByRole('button',{name:'Открыть',exact:true}).click();
  await page.getByLabel('Служебная причина').fill('Проверка двух независимых подтверждений');
  await page.getByRole('button',{name:'Проверить',exact:true}).click();
  await page.locator('.result').filter({hasText:'valid'}).waitFor();
  await page.getByRole('button',{name:'Опубликовать',exact:true}).click();
  await page.locator('.result').filter({hasText:'другого сотрудника'}).waitFor();
  const records=await marketplace.store.all('monetization_config','KZ');assert.equal(records.length,1);assert.equal(records[0].status,'draft');
  await page.getByRole('button',{name:'Выйти',exact:true}).click();await page.waitForSelector('#staff-login');
  console.log('Admin browser: real MFA login, identity, draft save, validation, independent approval rejection and logout passed.');
 }catch(error){if(page){await page.screenshot({path:'/tmp/joba-admin-browser-failure.png',fullPage:true});console.error('Page diagnostics:',await page.locator('[role=alert], .note.danger').allTextContents());}throw error;}finally{await browser?.close();await vite?.close();await app.close();await marketplace.store.close();await rm(files,{recursive:true,force:true});}
}
main().catch(error=>{console.error(error.message);process.exitCode=1;});
