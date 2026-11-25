// Full owner workflow against an isolated in-memory API. Never uses production data.
const assert=require('node:assert/strict'),{randomUUID}=require('node:crypto'),{resolve}=require('node:path');
const {chromium}=require('@playwright/test');
(async()=>{
 process.env.JOBA_DATA_DIR='memory://';delete process.env.DATABASE_URL;
 const {NestFactory}=require('@nestjs/core'),{AppModule,getMarketplace}=require('../services/api/dist/app.module');
 const app=await NestFactory.create(AppModule,{logger:false});const market=await getMarketplace();let browser,vite;
 try{
  const phone='+77000000981',password='Isolated referral browser password!';let owner=await market.handle('POST','/auth/register',{country:'KZ',phone,password},undefined,randomUUID());
  await market.store.put({...await market.store.get(owner.user.id),staff_permissions:['platform_owner'],display_name:'Тестовый владелец'});
  const user=await market.handle('POST','/auth/register',{country:'KZ',phone:'+77000000982',password},undefined,randomUUID());
  const friend=await market.handle('POST','/auth/register',{country:'KZ',phone:'+77000000983',password},undefined,randomUUID());
  const userCall=(u,method,path,body={})=>market.handle(method,path,body,'Bearer '+u.access_token,randomUUID());
  const ref=await userCall(user,'GET','/me/referrals');
  await app.listen(0,'127.0.0.1');const origin=await app.getUrl();
  const {createServer}=await import('vite');vite=await createServer({root:resolve(__dirname,'../apps/admin'),server:{port:5185,strictPort:false,host:'127.0.0.1'}});await vite.listen();
  const frontend='http://127.0.0.1:'+vite.httpServer.address().port;
  browser=await chromium.launch({executablePath:process.env.JOBA_CHROMIUM_PATH||process.env.CHROME_EXECUTABLE||'/usr/bin/chromium',args:['--no-sandbox']});const page=await browser.newPage({viewport:{width:393,height:852}});
  page.on('dialog',dialog=>dialog.accept());
  let failFirstPublish=true;
  await page.route('**/api/v1/**',async route=>{const r=route.request(),u=new URL(r.url());if(failFirstPublish&&r.method()==='POST'&&/\/referral-campaigns\/[^/]+\/publish$/.test(u.pathname)){failFirstPublish=false;return route.fulfill({status:503,contentType:'application/json',body:JSON.stringify({error:{code:'TEMPORARY_FAILURE',message:'Тестовая временная ошибка. Повторите запуск.'}})});}const result=await fetch(origin+u.pathname+u.search,{method:r.method(),headers:r.headers(),body:['GET','HEAD'].includes(r.method())?undefined:r.postDataBuffer()});await route.fulfill({status:result.status,headers:{'content-type':result.headers.get('content-type')||'application/json'},body:Buffer.from(await result.arrayBuffer())});});
  await page.goto(frontend+'/#login');await page.getByLabel('Логин',{exact:true}).fill(phone);await page.getByLabel('Пароль',{exact:true}).fill(password);await page.getByRole('button',{name:'Продолжить',exact:true}).click();await page.locator('#staff-logout').waitFor();
  await page.goto(frontend+'/#referrals?new=1');await page.locator('#referral-editor').waitFor();
  await page.getByLabel('Название',{exact:true}).fill('Проверка запуска владельцем');await page.getByLabel('Приглашений для награды',{exact:true}).fill('1');await page.getByLabel('Бюджет · число наград',{exact:true}).fill('10');
  await page.getByLabel('Процент скидки',{exact:true}).fill('0');await page.getByLabel('Награда',{exact:true}).selectOption('subscription_days');await page.getByLabel('Срок награды · дней',{exact:true}).fill('30');
  // Hidden reward controls must not block the selected reward's valid form.
  await page.getByRole('button',{name:'Создать новый черновик',exact:true}).click();await page.locator('#referral-command').waitFor();
  const original=new URLSearchParams(new URL(page.url()).hash.split('?')[1]).get('id');assert.ok(original);
  await page.getByRole('button',{name:'Запустить кампанию',exact:true}).click();await page.locator('#referral-command [role=alert]').filter({hasText:'Тестовая временная ошибка'}).waitFor();assert.equal((await market.store.get(original)).status,'draft');
  await page.getByRole('button',{name:'Запустить кампанию',exact:true}).click();await page.getByRole('button',{name:'Остановить кампанию',exact:true}).waitFor();
  assert.equal((await market.store.get(original)).status,'effective');assert.ok(await page.getByText('Состояние: Опубликована.',{exact:false}).isVisible());
  await userCall(friend,'POST','/referrals/attribute',{code:ref.code});assert.equal((await market.store.all('referral_reward','KZ')).length,1);
  // Dirty form must not prevent stopping the saved campaign.
  await page.getByLabel('Название',{exact:true}).fill('Несохранённая правка');
  await page.getByRole('button',{name:'Остановить кампанию',exact:true}).click();await page.getByRole('button',{name:'Убрать в архив',exact:true}).waitFor();assert.equal((await market.store.get(original)).status,'stopped');
  await page.getByRole('button',{name:'Убрать в архив',exact:true}).click();await page.waitForFunction(()=>location.hash==='#referrals');await page.locator('#referral-editor').waitFor();
  assert.equal((await market.store.get(original)).status,'archived');assert.equal(await page.locator('a[href="#referrals?id='+original+'"]').count(),0);
  await page.getByRole('link',{name:'Архив кампаний',exact:true}).click();await page.locator('a[href="#referrals?id='+original+'&archive=1"]').click();await page.locator('#referral-command').waitFor();
  await page.getByRole('button',{name:'Создать новую версию',exact:true}).click();await page.waitForFunction(id=>new URLSearchParams(location.hash.split('?')[1]).get('id')!==id,original);await page.getByRole('button',{name:'Запустить кампанию',exact:true}).waitFor();
  const restored=new URLSearchParams(new URL(page.url()).hash.split('?')[1]).get('id');assert.notEqual(restored,original);assert.equal((await market.store.get(restored)).status,'draft');
  await page.getByRole('button',{name:'Запустить кампанию',exact:true}).click();await page.getByRole('button',{name:'Остановить кампанию',exact:true}).waitFor();assert.equal((await market.store.get(restored)).status,'effective');
  await page.goto(frontend+'/#referrals?new=1');await page.getByLabel('Название',{exact:true}).fill('Черновик для удаления');await page.getByRole('button',{name:'Создать новый черновик',exact:true}).click();await page.getByRole('button',{name:'Удалить черновик',exact:true}).waitFor();
  const unwanted=new URLSearchParams(new URL(page.url()).hash.split('?')[1]).get('id');await page.getByRole('button',{name:'Удалить черновик',exact:true}).click();await page.waitForFunction(()=>location.hash==='#referrals');assert.equal((await market.store.get(unwanted)).status,'archived');
  assert.equal((await market.store.all('referral_reward','KZ')).length,1);assert.equal((await market.store.all('referral_attribution','KZ')).length,1);
  console.log('PASS: owner draft, publish, actual referral code, one reward, stop with unsaved edits, archive, restore, republish, draft removal. Isolated memory API only.');
 }finally{await browser?.close();await vite?.close();await app.close();await market.store.close();}
})().catch(e=>{console.error(e);process.exitCode=1;});
