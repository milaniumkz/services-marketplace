const {mkdtemp,rm,readFile,mkdir,writeFile}=require('node:fs/promises');
const {tmpdir}=require('node:os');
const {join,resolve}=require('node:path');
const {randomUUID,randomBytes}=require('node:crypto');
const {hash}=require('@node-rs/argon2');
const {chromium}=require('@playwright/test');
const assert=require('node:assert/strict');
const sharp=require('sharp');
async function main(){
 const files=await mkdtemp(join(tmpdir(),'joba-admin-browser-'));
 process.env.JOBA_DATA_DIR='memory://';process.env.JOBA_UPLOAD_DIR=files;delete process.env.DATABASE_URL;
 const {NestFactory}=require('@nestjs/core');
 const {AppModule,getMarketplace}=require('../services/api/dist/app.module');
 const {totp}=require('../services/api/dist/totp');
 const app=await NestFactory.create(AppModule,{logger:false});const marketplace=await getMarketplace();
 let browser,page,vite,webVite;
 try{
  const id=randomUUID(),secret=randomBytes(20).toString('hex'),password=randomBytes(32).toString('base64url');
  await marketplace.store.put({id,kind:'user',owner:id,country:'KZ',version:1,created_at:new Date().toISOString(),display_name:'Изолированный сотрудник',phone:'staff-browser-test',roles:['customer'],staff_permissions:['administrator','verification_reviewer','support','bulk_restrict'],totp_secret:secret,status:'active',fixture:true});
  await marketplace.store.db.query('INSERT INTO credentials(country,phone,user_id,password_hash) VALUES($1,$2,$3,$4)',['KZ','staff-browser-test',id,await hash(password)]);
  const applicant=await marketplace.handle('POST','/auth/register',{country:'KZ',phone:'+77000000431',password:'Isolated browser account password',display_name:'Заявитель проверки'},undefined,undefined,{},'browser-applicant');
  const supportThread=await marketplace.handle('POST','/support/threads',{subject:'Изолированная проверка ответа поддержки'},'Bearer '+applicant.access_token,randomUUID());
  const professional=await marketplace.handle('POST','/auth/register',{country:'KZ',phone:'+77000000432',password:'Isolated professional browser password',display_name:'Изолированный исполнитель'},undefined,undefined,{},'browser-professional');
  await marketplace.store.put({...await marketplace.store.get(professional.user.id),roles:['customer','executor'],verification:'passed',fixture:true});
  await marketplace.store.put({id:randomUUID(),kind:'grant',owner:professional.user.id,country:'KZ',version:1,created_at:new Date().toISOString(),valid_until:new Date(Date.now()+86400000).toISOString(),capabilities:['publish_profile'],source:'isolated_browser_fixture'});
  const ownerCommand=(method,path,body={})=>marketplace.handle(method,path,body,'Bearer '+professional.access_token,randomUUID());
  // Isolated scan adapter exercises binary photo review; no production AV outcome is claimed.
  marketplace.providers.scanner={scan:async()=> 'clean'};
  const bytes=await sharp({create:{width:2,height:2,channels:3,background:'#245BDB'}}).png().toBuffer();
  let photo=await ownerCommand('POST','/uploads/initiate',{purpose:'portfolio',mime:'image/png',size:bytes.length});await ownerCommand('PUT','/uploads/'+photo.id+'/content',bytes);photo=await ownerCommand('POST','/uploads/'+photo.id+'/finalize');
  const category=(await ownerCommand('GET','/catalog/categories')).items[0].id;
  let profile=await ownerCommand('PUT','/me/contractor-profile',{title:'Первая версия профиля исполнителя',description:'Безопасное описание профиля для изолированной проверки',city:'Алматы',category_id:category,gallery_ids:[photo.id]});
  profile=await ownerCommand('POST','/me/contractor-profile/publish',{expected_version:profile.version});
  const verificationId=randomUUID();
  await marketplace.store.put({id:verificationId,kind:'verification',owner:applicant.user.id,country:'KZ',version:1,created_at:new Date().toISOString(),status:'pending_review',document_type:'passport',document_revision:2,document_refs:[]});
  await app.listen(0,'127.0.0.1');const origin=await app.getUrl();
  browser=await chromium.launch({executablePath:process.env.JOBA_CHROMIUM_PATH||'/usr/bin/chromium',args:['--no-sandbox']});
  page=await browser.newPage({viewport:{width:1440,height:1000}});
  // Redirect transport to an isolated real HTTP API; response data are never mocked.
  let lostDraftResponse=false,lostReplyResponse=false;
  await page.route('**/api/v1/**',async route=>{
   const request=route.request(),url=new URL(request.url());
   const response=await fetch(origin+url.pathname+url.search,{method:request.method(),headers:request.headers(),body:['GET','HEAD'].includes(request.method())?undefined:request.postDataBuffer()});
   if(request.method()==='POST'&&url.pathname==='/api/v1/admin/monetization-configs'&&response.ok&&!lostDraftResponse){lostDraftResponse=true;await response.text();await route.abort('failed');return;}
   if(request.method()==='POST'&&url.pathname==='/api/v1/admin/support-threads/'+supportThread.id+'/messages'&&response.ok&&!lostReplyResponse){lostReplyResponse=true;await response.text();await route.abort('failed');return;}
   await route.fulfill({status:response.status,headers:{'content-type':response.headers.get('content-type')||'application/json'},body:Buffer.from(await response.arrayBuffer())});
  });
  let frontend=process.env.JOBA_ADMIN_TEST_URL;
  if(!frontend){const {createServer}=await import('vite');vite=await createServer({root:resolve(__dirname,'../apps/admin'),server:{port:0,strictPort:false,host:'127.0.0.1'}});await vite.listen();frontend='http://127.0.0.1:'+vite.httpServer.address().port;}
  await page.goto(frontend+'/#login');
  assert.equal(await page.locator('.loginbrand').count(),1);
  await page.getByLabel('Рабочий идентификатор').fill('staff-browser-test');await page.getByLabel('Пароль',{exact:true}).fill(password);
  await page.getByRole('button',{name:'Продолжить',exact:true}).click();
  const firstMfaTime=Date.now();
  await page.getByLabel('Код второго фактора').fill(totp(secret,firstMfaTime));await page.getByRole('button',{name:'Продолжить',exact:true}).click();
  await page.waitForSelector('#staff-logout');assert.equal(await page.locator('.account b').textContent(),'Изолированный сотрудник');
  await page.locator('#dashboard-period').waitFor();
  await page.getByRole('button',{name:'Поиск по стране',exact:true}).click();
  await page.getByLabel('Имя, название или ID',{exact:true}).fill(applicant.user.id);
  await page.locator('#staff-global-search').getByRole('button',{name:'Найти',exact:true}).click();
  await page.locator('#staff-search-results').filter({hasText:'Заявитель проверки'}).waitFor();
  await page.getByRole('button',{name:'Закрыть',exact:true}).click();
  await page.getByRole('button',{name:'Уведомления',exact:true}).click();
  await page.locator('#staff-dialog-body').filter({hasText:'Новых уведомлений нет'}).waitFor();
  await page.getByRole('button',{name:'Закрыть',exact:true}).click();

  const capture=async name=>{if(!process.env.JOBA_SCREENSHOT_DIR)return;await mkdir(process.env.JOBA_SCREENSHOT_DIR,{recursive:true});await page.screenshot({path:join(process.env.JOBA_SCREENSHOT_DIR,name+'.png'),fullPage:true});};
  await capture('A02-dashboard');
  await page.goto(frontend+'/#branding');
  await page.locator('#brand-source').waitFor();
  const launcher=await sharp({create:{width:1200,height:1024,channels:4,background:'#245BDB'}}).png().toBuffer();
  await page.locator('#brand-file').setInputFiles({name:'isolated-launcher.png',mimeType:'image/png',buffer:launcher});
  await page.locator('#source-details').filter({hasText:'1200 × 1024'}).waitFor();
  await page.locator('#brand-source [name=reason]').fill('Проверка загрузки исходника через браузер');
  await page.locator('#brand-source').getByRole('button',{name:'Сохранить версию',exact:true}).click();
  await page.waitForURL(/#branding\?version=/);
  await page.locator('[data-brand-mask=ios]:not([hidden])').waitFor();
  await capture('A19-branding');
  const brand=(await marketplace.store.all('brand_icon','KZ'))[0];assert.equal(brand.status,'draft');assert.equal(brand.crop.left,88);
  await page.locator('#brand-command [name=reason]').fill('Проверка запрета утверждения автором');
  await page.locator('#brand-command').getByRole('button',{name:'Утвердить исходник',exact:true}).click();
  await page.locator('#brand-command [role=alert]').filter({hasText:'второе подтверждение'}).waitFor();
  assert.equal((await marketplace.store.get(brand.id)).status,'draft');
  const approverId=randomUUID();await marketplace.store.put({id:approverId,kind:'user',owner:approverId,country:'KZ',version:1,created_at:new Date().toISOString(),display_name:'Независимый утверждающий',phone:'brand-approver-fixture',roles:['customer'],staff_permissions:['brand_owner','bulk_restrict'],totp_secret:secret,status:'active',fixture:true});
  await marketplace.store.db.query('INSERT INTO credentials(country,phone,user_id,password_hash) VALUES($1,$2,$3,$4)',['KZ','brand-approver-fixture',approverId,await hash(password)]);
  const approvalSession=await marketplace.handle('POST','/auth/staff-login',{country:'KZ',phone:'brand-approver-fixture',password,mfa_code:totp(secret)},undefined,undefined,{},'isolated-brand-approval');
  await marketplace.handle('POST','/admin/brand-icons/'+brand.id+'/approve',{expected_version:brand.version,reason:'Независимая проверка исходника и масок'},'Bearer '+approvalSession.access_token,randomUUID());
  await page.locator('#brand-refresh').click();
  await page.locator('#brand-command [name=reason]').fill('Подготовить ресурсы для проверки сборки');
  await page.locator('#brand-command').getByRole('button',{name:'Сформировать пакет',exact:true}).click();
  await page.locator('#brand-command').getByRole('button',{name:'Скачать пакет',exact:true}).waitFor();
  await page.locator('#brand-command [name=reason]').fill('Скачать проверенный пакет ресурсов');
  const iconsDownload=page.waitForEvent('download');
  await page.locator('#brand-command').getByRole('button',{name:'Скачать пакет',exact:true}).click();
  const icons=await iconsDownload;assert.equal(icons.suggestedFilename(),'joba-icons.zip');assert.ok((await readFile(await icons.path())).length>1000);
  assert.equal((await marketplace.store.get(brand.id)).release_status,'not_built');
  assert.ok((await marketplace.store.all('audit','KZ')).some(row=>row.action==='brand.bundle_read'));

  await page.goto(frontend+'/#branding-build?version='+brand.id);await page.locator('#build-command').waitFor();
  await page.locator('#build-reason').fill('Скачать пакет на этапе проверки артефактов');
  const buildDownload=page.waitForEvent('download');await page.locator('#build-command').getByRole('button',{name:'Скачать пакет',exact:true}).click();
  assert.ok((await readFile(await (await buildDownload).path())).length>1000);
  assert.equal(await page.getByText('Нет подтверждённой сборки',{exact:true}).count(),1);

  const caseOrder=await ownerCommand('POST','/orders',{title:'Проверка материала для дела',description:'Изолированная задача для проверки решения модератора.',category_id:category,city:'Алматы'});
  const caseReport=await ownerCommand('POST','/cases',{target_type:'order',target_id:caseOrder.id,reason_code:'content',description:'Проверка решения модератора через браузер'});
  await page.goto(frontend+'/#case-live/'+caseReport.id);
  await page.locator('#case-decision [name=reason]').fill('Проверенный материал требует скрытия в выдаче');
  await page.locator('#case-decision [name=decision]').selectOption('content_removed');
  await page.locator('#case-decision').getByRole('button',{name:'Зафиксировать решение',exact:true}).click();
  await page.waitForFunction(()=>!document.getElementById('case-decision'));
  const moderated=await marketplace.store.get(caseOrder.id);assert.equal(moderated.moderation_status,'hidden');assert.equal(moderated.status,'draft');
  assert.equal((await marketplace.store.get(caseReport.id)).decision,'content_removed');
  let appealUpload=await ownerCommand('POST','/uploads/initiate',{purpose:'chat',mime:'image/png',size:bytes.length});
  await ownerCommand('PUT','/uploads/'+appealUpload.id+'/content',bytes);appealUpload=await ownerCommand('POST','/uploads/'+appealUpload.id+'/finalize');
  const appealCase=await marketplace.store.get(caseReport.id);
  await ownerCommand('POST','/cases/'+caseReport.id+'/appeals',{expected_version:appealCase.version,reason:'Прошу пересмотреть решение по приложенным материалам.',upload_ids:[appealUpload.id]});
  await page.goto(frontend+'/#case-live/'+caseReport.id);await page.getByRole('button',{name:'Обновить',exact:true}).click();await page.locator('#case-appeal-evidence').waitFor();
  await page.locator('#case-appeal-evidence [name=reason]').fill('Проверка материалов апелляции уполномоченным сотрудником');
  const appealDownloadEvent=page.waitForEvent('download');await page.locator('#case-appeal-evidence button').click();
  const appealDownload=await appealDownloadEvent;assert.ok((await readFile(await appealDownload.path())).length>0);
  await capture('A06-appeal-evidence');
  assert.ok((await marketplace.store.all('audit','KZ')).some(row=>row.action==='case.evidence_read'&&row.target_id===appealUpload.id));
  await page.goto(frontend+'/#dashboard');await page.locator('#dashboard-period').waitFor();

  await page.locator('#dashboard-period').selectOption('30');
  await page.waitForFunction(()=>document.querySelector('#dashboard-period')?.value==='30');
  await page.getByRole('button',{name:'Определения всех метрик',exact:true}).click();
  await page.locator('#metric-definitions-result').filter({hasText:'Активные аккаунты'}).waitFor();
  const downloadEvent=page.waitForEvent('download');await page.getByRole('button',{name:'Экспорт сводки',exact:true}).click();
  const download=await downloadEvent,report=JSON.parse(await readFile(await download.path(),'utf8'));
  assert.equal(report.country,'KZ');assert.equal(report.days,30);assert.equal(report.series.length,30);
  await page.goto(frontend+'/#analytics');await page.locator('#analytics-period').selectOption('30');
  await page.waitForFunction(()=>document.querySelector('#analytics-period')?.value==='30');
  const analyticsDownload=page.waitForEvent('download');await page.locator('#analytics-export').click();
  const analyticsReport=JSON.parse(await readFile(await (await analyticsDownload).path(),'utf8'));
  assert.equal(analyticsReport.country,'KZ');assert.equal(analyticsReport.days,30);assert.equal(analyticsReport.series.length,30);assert.equal(analyticsReport.rates.selection,null);
  await page.goto(frontend+'/#security');await page.locator('#system-filter').waitFor();
  await capture('A12-security');
  assert.ok(await page.locator('tbody tr').count());assert.equal(await page.getByText(secret,{exact:true}).count(),0);
  const operationalJob=randomUUID();await marketplace.store.put({id:operationalJob,kind:'privacy',type:'export',owner:applicant.user.id,country:'KZ',version:1,created_at:new Date().toISOString(),status:'failed',attempts:5,failure_code:'EXPORT_RETRY_REQUIRED'});
  await page.goto(frontend+'/#jobs');await page.locator('[data-job="'+operationalJob+'"]').waitFor();await capture('A15-jobs');await page.locator('[data-job="'+operationalJob+'"]').click();
  await page.getByLabel('Служебная причина',{exact:true}).fill('Повтор после проверки причины изолированного сбоя');
  await page.getByRole('button',{name:'Поставить повтор в очередь',exact:true}).click();
  await page.waitForFunction(id=>!document.querySelector('[data-job="'+id+'"]'),operationalJob);
  assert.equal((await marketplace.store.get(operationalJob)).status,'requested');
  const detailJob=randomUUID();await marketplace.store.put({id:detailJob,kind:'privacy',type:'export',owner:applicant.user.id,country:'KZ',version:1,created_at:new Date().toISOString(),status:'failed',attempts:3,failure_code:'EXPORT_RETRY_REQUIRED',private_note:'isolated hidden job metadata'});
  await page.goto(frontend+'/#job-detail?job_id='+detailJob);
  await page.getByLabel('Служебная причина',{exact:true}).fill('Повтор из карточки после проверки причины сбоя');
  assert.equal((await page.locator('body').innerText()).includes('isolated hidden job metadata'),false);
  await page.getByRole('button',{name:'Поставить повтор в очередь',exact:true}).click();
  await page.getByText('Повторная обработка для текущего состояния недоступна.',{exact:true}).waitFor();
  assert.equal((await marketplace.store.get(detailJob)).status,'requested');
  const scheduledJob=randomUUID();await marketplace.store.put({id:scheduledJob,kind:'outbox',owner:applicant.user.id,country:'KZ',version:1,created_at:new Date().toISOString(),status:'retry',next_attempt_at:new Date(Date.now()+3600000).toISOString(),attempts:1});
  await page.goto(frontend+'/#scheduled');await page.locator('a[href="#job-detail?job_id='+scheduledJob+'"]').waitFor();

  await page.locator('.nav a[href="#monetization"]').click();
  await page.getByLabel('Название',{exact:true}).fill('Проверка реального черновика');
  await page.getByLabel('Причина',{exact:true}).fill('Изолированная проверка интерфейса');
  assert.equal(await page.getByRole('switch',{name:'Показывать inline-баннеры'}).getAttribute('aria-checked'),'false');
  assert.equal(await page.getByRole('switch',{name:'Разрешить новые рекламные сессии'}).getAttribute('aria-checked'),'false');
  await page.getByRole('button',{name:'Сохранить черновик'}).click();
  await page.getByRole('alert').filter({hasText:'Нет соединения'}).waitFor();
  assert.equal(await page.getByLabel('Название',{exact:true}).inputValue(),'Проверка реального черновика');
  await page.getByRole('button',{name:'Сохранить черновик'}).click();
  await page.getByRole('button',{name:'Открыть',exact:true}).click();
  await page.getByLabel('Служебная причина').fill('Проверка двух независимых подтверждений');
  await page.getByRole('button',{name:'Проверить',exact:true}).click();
  await page.locator('.result').filter({hasText:'valid'}).waitFor();
  await page.getByRole('button',{name:'Опубликовать',exact:true}).click();
  await page.locator('.result').filter({hasText:'другого сотрудника'}).waitFor();
  const records=await marketplace.store.all('monetization_config','KZ');assert.equal(records.length,1);assert.equal(records[0].status,'draft');
  await page.getByLabel('Название',{exact:true}).fill('Баннерный черновик без интеграции');
  await page.getByLabel('Причина',{exact:true}).fill('Подготовка независимого баннерного флага');
  await page.getByRole('switch',{name:'Показывать inline-баннеры',exact:true}).click();
  assert.equal(await page.getByRole('switch',{name:'Показывать inline-баннеры',exact:true}).getAttribute('aria-checked'),'true');
  await page.getByRole('button',{name:'Сохранить черновик',exact:true}).click();
  await page.locator('.event').filter({hasText:'Баннерный черновик без интеграции'}).getByRole('button',{name:'Открыть',exact:true}).click();
  await page.getByLabel('Служебная причина').fill('Проверка закрытого подключения рекламной сети');
  await page.getByRole('button',{name:'Проверить',exact:true}).click();
  await page.locator('.result').filter({hasText:'сеть ещё не подключена'}).waitFor();
  assert.equal((await marketplace.store.all('monetization_config','KZ')).find(r=>r.title==='Баннерный черновик без интеграции').payload.banner_ads_enabled,true);
  assert.ok((await page.locator('.workspace').innerText()).includes('Заказчики пользуются сервисом бесплатно'));
  await page.getByLabel('Название',{exact:true}).fill('Несколько возможностей рекламной награды');
  await page.getByLabel('Причина',{exact:true}).fill('Сохраняем все выбранные возможности без их потери');
  await page.locator('#reward-capability').selectOption(['search_full','send_offer','publish_profile']);
  await page.getByRole('button',{name:'Сохранить черновик',exact:true}).click();
  await page.locator('.event').filter({hasText:'Несколько возможностей рекламной награды'}).waitFor();
  assert.deepEqual((await marketplace.store.all('monetization_config','KZ')).find(r=>r.title==='Несколько возможностей рекламной награды').payload.reward_policy.capabilities,['search_full','send_offer','publish_profile']);
  const promoPrice={id:randomUUID(),kind:'price_version',owner:id,country:'KZ',version:1,created_at:new Date().toISOString(),status:'effective',title:'Опубликованный тариф исполнителя',payload:{product_type:'subscription',product_id:'isolated-monthly',provider:'isolated',period:'month',currency:'KZT',amount_minor:249000}};
  await marketplace.store.put(promoPrice);
  const boostPrice={...promoPrice,id:randomUUID(),title:'Цена размещения, не подписки',payload:{...promoPrice.payload,product_type:'boost'}};await marketplace.store.put(boostPrice);
  const promoBefore=(await marketplace.store.all('promotion','KZ')).length;
  await page.goto(frontend+'/#promo');await page.locator('#promo-editor').waitFor();
  assert.equal(await page.locator('#promo-editor textarea[name=payload]').count(),0);
  assert.equal(await page.locator('#promo-next-price option[value="'+boostPrice.id+'"]').count(),0);
  await page.getByLabel('Название',{exact:true}).fill('Структурированное промо исполнителя');
  await page.getByLabel('Начало — местное время',{exact:true}).fill(new Date(Date.now()+86400000).toISOString().slice(0,16));
  await page.getByLabel('Бесплатно по дату включительно',{exact:true}).fill(new Date(Date.now()+3*86400000).toISOString().slice(0,10));
  await page.getByLabel('Часовой пояс IANA',{exact:true}).fill('Asia/Almaty');
  await page.getByLabel('Аудитория',{exact:true}).selectOption('existing');
  await page.getByLabel('Следующий тариф',{exact:true}).selectOption(promoPrice.id);
  assert.equal(await page.getByLabel('Проверенный SKU',{exact:true}).inputValue(),'isolated-monthly');
  await page.getByLabel('Условия для пользователя',{exact:true}).fill('Период без автоматического списания, с отдельным выбором подписки после завершения.');
  await page.getByLabel('Причина изменения',{exact:true}).fill('Проверка сохранения реальных полей промо');
  await page.getByRole('button',{name:'Сохранить черновик',exact:true}).click();await page.locator('#promo-command').waitFor();
  const promoId=new URLSearchParams(new URL(page.url()).hash.split('?')[1]).get('id');
  assert.equal((await marketplace.store.get(promoId)).payload.role,'executor');
  assert.equal((await marketplace.store.get(promoId)).payload.audience,'existing');
  await page.getByLabel('Название',{exact:true}).fill('Исправленное структурированное промо');
  assert.equal(await page.getByRole('button',{name:'Предпросмотр промо',exact:true}).isDisabled(),true);
  await page.getByLabel('Причина изменения',{exact:true}).fill('Изменение сохраняется в том же собственном черновике');
  await page.getByRole('button',{name:'Сохранить черновик',exact:true}).click();
  await page.getByRole('button',{name:'Предпросмотр промо',exact:true}).waitFor();
  await page.waitForFunction(()=>document.querySelector('#promo-command button[value=preview]')?.disabled===false);
  assert.equal((await marketplace.store.get(promoId)).version,2);assert.equal((await marketplace.store.all('promotion','KZ')).length,promoBefore+1);
  await page.getByLabel('Основание действия',{exact:true}).fill('Проверяем вычисленную границу до публикации');
  await page.getByRole('button',{name:'Предпросмотр промо',exact:true}).click();
  const promoBoundary=(await marketplace.configuration.validate(await marketplace.store.get(promoId))).promo_end_exclusive;
  await page.locator('#promo-boundary').filter({hasText:promoBoundary}).waitFor();
  await page.getByRole('button',{name:'Опубликовать другим сотрудником',exact:true}).click();
  await page.locator('#promo-command [role=alert]').filter({hasText:'другого сотрудника'}).waitFor();assert.equal((await marketplace.store.get(promoId)).status,'draft');
  const promoApprover=await marketplace.store.get(approvalSession.user.id);await marketplace.store.put({...promoApprover,staff_permissions:[...promoApprover.staff_permissions,'billing']});
  await marketplace.handle('POST','/admin/promotions/'+promoId+'/publish',{expected_version:2,reason:'Независимое подтверждение промо для проверки отката'},'Bearer '+approvalSession.access_token,randomUUID());
  await page.locator('#refresh-data').click();await page.getByRole('button',{name:'Черновик отката',exact:true}).waitFor();
  await page.getByLabel('Основание действия',{exact:true}).fill('Подготовка отдельной версии для отката промо');
  await page.getByRole('button',{name:'Черновик отката',exact:true}).click();
  await page.waitForFunction(previous=>new URLSearchParams(location.hash.split('?')[1]).get('id')!==previous,promoId);
  await page.locator('#promo-command').waitFor();
  const rollbackPromoId=new URLSearchParams(new URL(page.url()).hash.split('?')[1]).get('id');
  assert.equal((await marketplace.store.get(rollbackPromoId)).rollback_of,promoId);assert.equal((await marketplace.store.get(rollbackPromoId)).status,'draft');assert.equal((await marketplace.store.get(promoId)).status,'effective');

  await page.goto(frontend+'/#contractors');
  await page.getByRole('link',{name:'Открыть →',exact:true}).click();
  await page.getByLabel('Причина просмотра фотографий').fill('Проверка фотографии текущей версии профиля');
  await page.getByRole('button',{name:'Показать фотографии',exact:true}).click();
  await page.waitForFunction(()=>document.querySelector('#content-media-result img')?.naturalWidth===2);
  await page.getByLabel('Основание решения',{exact:true}).fill('Подтверждена безопасная версия профиля');
  await page.getByRole('button',{name:'Сохранить решение',exact:true}).click();
  await page.getByRole('button',{name:'Сохранить решение',exact:true}).waitFor({state:'detached'});
  profile=await marketplace.store.get(profile.id);assert.equal(profile.status,'published');
  const boostPolicy={id:randomUUID(),kind:'placement_policy',owner:id,country:'KZ',version:1,created_at:new Date().toISOString(),status:'effective',title:'Изолированное место',payload:{placement_id:'home.promoted.services',capacity:2}};
  await marketplace.store.put(boostPolicy);
  await marketplace.store.put({id:randomUUID(),kind:'grant',owner:professional.user.id,country:'KZ',version:1,created_at:new Date().toISOString(),valid_until:new Date(Date.now()+86400000).toISOString(),capabilities:['search_full'],source:'isolated_browser_fixture'});
  await page.goto(frontend+'/#boost-grant');await page.locator('#boost-target').fill(profile.id);
  await page.locator('#boost-placement').selectOption(boostPolicy.payload.placement_id);
  await page.locator('#boost-end').fill(new Date(Date.now()+3600000).toISOString().slice(0,16));
  await page.locator('#boost-reason').fill('Бесплатная выдача по изолированному обращению');
  await page.locator('#boost-grant').getByRole('button',{name:'Предпросмотр выдачи',exact:true}).click();
  await page.locator('#boost-confirm').waitFor();assert.equal((await marketplace.store.all('boost','KZ')).length,0);
  await page.locator('#boost-reason').fill('Исправленная причина изолированной выдачи');assert.equal(await page.locator('#boost-confirm').count(),0);
  await page.locator('#boost-grant').getByRole('button',{name:'Предпросмотр выдачи',exact:true}).click();await page.locator('#boost-confirm').click();
  await page.locator('#boost-preview').filter({hasText:'Выдано размещение'}).waitFor();
  const issuedBoost=(await marketplace.store.all('boost','KZ'))[0];assert.equal(issuedBoost.reason,'Исправленная причина изолированной выдачи');
  await page.goto(frontend+'/#boosts');await page.getByText(issuedBoost.id,{exact:false}).waitFor();
  assert.equal((await marketplace.store.all('boost','KZ')).length,1);
  await page.goto(frontend+'/#record-live/contractors/'+profile.id);await page.locator('#refresh-data').waitFor();

  profile=await ownerCommand('PUT','/me/contractor-profile',{expected_version:profile.version,title:'Частная новая версия профиля',description:'Черновик ожидает независимой проверки',city:'Алматы',category_id:category});
  profile=await ownerCommand('POST','/me/contractor-profile/publish',{expected_version:profile.version});
  await page.getByRole('button',{name:'Обновить',exact:true}).click();
  await page.getByLabel('Решение',{exact:true}).selectOption('reject');
  await page.getByLabel('Основание решения',{exact:true}).fill('Черновик требует исправления описания');
  await page.getByRole('button',{name:'Сохранить решение',exact:true}).click();
  await page.getByRole('button',{name:'Сохранить решение',exact:true}).waitFor({state:'detached'});
  const rejectedProfile=await marketplace.store.get(profile.id);assert.equal(rejectedProfile.status,'published');assert.equal(rejectedProfile.title,'Первая версия профиля исполнителя');assert.equal(rejectedProfile.draft.status,'rejected');
  await page.goto(frontend+'/#support-live/'+supportThread.id);
  await page.getByRole('button',{name:'Назначить себе',exact:true}).click();
  await page.getByLabel('Ответ поддержки').fill('Реальный ответ поддержки без дубликата при потере соединения');
  await page.getByRole('button',{name:'Отправить',exact:true}).click();
  await page.getByRole('alert').filter({hasText:'Нет соединения'}).waitFor();
  await page.getByRole('button',{name:'Отправить',exact:true}).click();
  await page.locator('.event').filter({hasText:'Реальный ответ поддержки без дубликата'}).waitFor();
  assert.equal((await marketplace.store.all('support_message','KZ')).filter(m=>m.thread_id===supportThread.id).length,1);
  await page.goto(frontend+'/#verification');
  await page.getByRole('link',{name:'Открыть →',exact:true}).click();
  await page.getByLabel('Основание решения').fill('Документы не соответствуют правилам проверки');
  await page.getByLabel('Решение',{exact:true}).selectOption('rejected');
  await page.getByRole('button',{name:'Сохранить решение',exact:true}).click();
  await page.getByRole('button',{name:'Сохранить решение',exact:true}).waitFor({state:'detached'});
  assert.equal((await marketplace.store.get(verificationId)).status,'rejected');
  assert.equal((await marketplace.store.get(applicant.user.id)).verification,'rejected');
  await page.goto(frontend+'/#record-live/users/'+applicant.user.id);
  await page.getByLabel('Служебная причина просмотра').fill('Проверка контакта по обращению владельца');
  await page.getByRole('button',{name:'Показать телефон',exact:true}).click();
  await page.locator('#sensitive-result').filter({hasText:'+77000000431'}).waitFor();
  assert.ok((await marketplace.store.all('audit','KZ')).some(x=>x.action==='user.phone_read'&&JSON.stringify(x).includes(applicant.user.id)));
  await page.goto(frontend+'/#user-orders');
  await page.getByLabel('Найти пользователя').fill('Изолированный исполнитель');
  await page.getByRole('button',{name:'Найти',exact:true}).click();
  await page.locator('a[href*="user_id='+professional.user.id+'"]').first().click();
  await page.getByText(caseOrder.title,{exact:true}).waitFor();
  await page.getByLabel('Состояние заказа').selectOption('completed');
  await page.getByRole('button',{name:'Найти',exact:true}).click();
  await page.waitForFunction(()=>!document.querySelector('[aria-busy=true]'));
  assert.equal(await page.getByText(caseOrder.title,{exact:true}).count(),0);
  await page.getByRole('button',{name:'Сбросить',exact:true}).click();
  await page.getByText(caseOrder.title,{exact:true}).waitFor();
  await page.locator('.tabs a[href^="#user-cases?"]').click();
  await page.locator('a[href="#case-live/'+caseReport.id+'"]').waitFor();
  await page.locator('.tabs a[href^="#user-decisions?"]').click();
  await page.locator('.timeline .event').first().waitFor();
  await page.goto(frontend+'/#user-cases?user_id='+applicant.user.id);
  await page.getByText('Изолированная проверка ответа поддержки',{exact:true}).waitFor();
  await marketplace.store.put({id:randomUUID(),kind:'security_event',owner:applicant.user.id,country:'KZ',version:1,created_at:new Date().toISOString(),event:'isolated.account-security',ip:'192.0.2.77',session_family:'isolated-private-family'});
  await page.locator('.tabs a[href^="#user-security?"]').click();
  await page.getByLabel('Служебная причина просмотра событий').fill('Проверка входов по обращению владельца');
  await page.getByRole('button',{name:'Загрузить события',exact:true}).click();
  await page.getByText('192.0.*.*',{exact:true}).waitFor();
  assert.equal((await page.locator('body').innerText()).includes('192.0.2.77'),false);
  assert.equal((await page.locator('body').innerText()).includes('isolated-private-family'),false);
  await page.goto(frontend+'/#users');
  await page.getByLabel('Поиск по ID или названию').fill(applicant.user.id);
  await page.getByRole('button',{name:'Найти',exact:true}).click();
  await page.getByRole('link',{name:'Открыть →',exact:true}).waitFor();
  assert.equal(await page.locator('tbody tr').count(),1);
  await page.goto(frontend+'/#countries');
  await page.getByLabel('Название изменения',{exact:true}).fill('Проверка управления текущей страной');
  await page.getByLabel('Служебная причина',{exact:true}).fill('Изолированная проверка формы управления страной');
  await page.getByLabel('Остановить новые бизнес-действия',{exact:true}).check();
  await capture('A14-countries');
  await page.getByRole('button',{name:'Сохранить черновик',exact:true}).click();
  await page.getByRole('button',{name:'Опубликовать версию',exact:true}).waitFor();
  await page.getByLabel('Основание публикации',{exact:true}).fill('Проверка обязательного независимого подтверждения');
  await page.getByRole('button',{name:'Опубликовать версию',exact:true}).click();
  await page.locator('[role=alert]').filter({hasText:'Нужно подтверждение другого сотрудника'}).waitFor();
  const controls=await marketplace.store.all('country_control','KZ');assert.equal(controls.length,1);assert.equal(controls[0].status,'draft');assert.equal(controls[0].payload.stop_new_business,true);
  await page.goto(frontend+'/#settings');
  await page.getByLabel('Срок заказа, дни',{exact:true}).fill('12');
  await page.getByLabel('Причина изменения',{exact:true}).fill('Проверка сохранения срока заказа текущего региона');
  const settingsResponse=page.waitForResponse(response=>response.request().method()==='POST'&&new URL(response.url()).pathname==='/api/v1/admin/runtime-settings');
  await page.getByRole('button',{name:'Сохранить настройки',exact:true}).click();await settingsResponse;
  assert.equal((await marketplace.store.all('runtime_settings','KZ'))[0].payload.order_expiry_days,12);
  await page.waitForFunction(()=>document.querySelector('#setting-order_expiry_days')?.value==='12');
  await page.goto(frontend+'/#legal');
  await page.getByLabel('Текст документа',{exact:true}).fill('Проверка настоящего правового черновика: текст сохраняется, но не публикуется без второго сотрудника.');
  await page.getByLabel('Причина создания',{exact:true}).fill('Изолированная проверка редактора документов');
  await page.getByRole('button',{name:'Создать черновик',exact:true}).click();
  await page.getByRole('button',{name:'Опубликовать версию',exact:true}).waitFor();
  const legal=(await marketplace.store.all('legal_document','KZ'))[0];assert.equal(legal.status,'draft');
  await page.getByRole('button',{name:'Редактировать новой версией',exact:true}).click();
  assert.equal(await page.getByLabel('Текст документа',{exact:true}).inputValue(),legal.content);
  await page.getByLabel('Текст документа',{exact:true}).fill(legal.content+' Дополненные реквизиты оператора.');
  const revisionResponse=page.waitForResponse(response=>response.request().method()==='POST'&&new URL(response.url()).pathname==='/api/v1/admin/legal/documents');
  await page.getByRole('button',{name:'Создать черновик',exact:true}).click();await revisionResponse;
  const revisions=await marketplace.store.all('legal_document','KZ');assert.equal(revisions.length,2);
  assert.equal((await marketplace.store.get(legal.id)).content,legal.content);
  assert.ok(revisions.some(d=>d.id!==legal.id&&d.content.endsWith('Дополненные реквизиты оператора.')));

  // Live supplementary states: no synthetic success or publication during dry-run.
  const scenarioDictionary=randomUUID();await marketplace.store.put({id:scenarioDictionary,kind:'dictionary',owner:id,country:'KZ',version:1,created_at:new Date().toISOString(),title:'Проверка правила интерфейса',status:'draft',payload:{rules:[{value:'обман',type:'exact_word'}],exceptions:[]}});
  await page.goto(frontend+'/#dictionary-dryrun?id='+scenarioDictionary);await page.locator('#dictionary-dryrun').waitFor();
  await page.getByLabel('Текст для проверки',{exact:true}).fill('ОБМАН!');await page.getByLabel('Причина проверки',{exact:true}).fill('Изолированная проверка интерфейса словаря');await page.getByRole('button',{name:'Проверить текст',exact:true}).click();await page.locator('#dictionary-dryrun [role=status]').filter({hasText:'"matched": true'}).waitFor();assert.equal((await marketplace.store.get(scenarioDictionary)).status,'draft');
  await page.goto(frontend+'/#revenue');await page.getByRole('heading',{name:'Доход рекламных сетей',exact:true}).waitFor();await page.getByText('Отсутствие отчётов не означает нулевой доход.',{exact:false}).waitFor();
  await page.goto(frontend+'/#languages');await page.getByRole('heading',{name:'Языки интерфейса',exact:true}).waitFor();assert.ok((await page.locator('.workspace').innerText()).includes('Қазақша'));
  await page.goto(frontend+'/#bulk-preview');await page.locator('#bulk-preview').waitFor();await page.getByLabel('Основание операции',{exact:true}).fill('Проверка обязательного выбора записей');await page.getByRole('button',{name:'Рассчитать влияние',exact:true}).click();await page.locator('#bulk-preview [role=alert]').filter({hasText:'Выберите'}).waitFor();
  // Complete push draft/preview/test/cancel flow against the real API; no provider success is invented.
  await page.goto(frontend+'/#push');await page.locator('#push-test-access').waitFor();
  await page.getByLabel('ID аккаунта',{exact:true}).fill(applicant.user.id);await page.getByLabel('Срок разрешения (UTC)',{exact:true}).fill(new Date(Date.now()+86400000).toISOString().slice(0,16));await page.getByLabel('Причина разрешения',{exact:true}).fill('Изолированное разрешение тестового получателя');await page.getByRole('button',{name:'Изменить разрешение теста',exact:true}).click();await page.locator('#push-test-access [role=status]').filter({hasText:'Тестовые отправки разрешены'}).waitFor();
  await page.goto(frontend+'/#push-compose');await page.locator('#push-editor').waitFor();await page.getByLabel('Название кампании',{exact:true}).fill('Изолированная проверка редактора рассылки');await page.getByLabel('Заголовок (ru)',{exact:true}).fill('Состояние сервиса');await page.getByLabel('Сообщение (ru)',{exact:true}).fill('Проверьте центр уведомлений в приложении.');await page.getByLabel('Часовой пояс IANA',{exact:true}).fill('UTC');await page.getByLabel('Отправка — местное время',{exact:true}).fill(new Date(Date.now()+600000).toISOString().slice(0,16));await page.getByLabel('Дедлайн — местное время',{exact:true}).fill(new Date(Date.now()+3600000).toISOString().slice(0,16));await page.getByLabel('Причина изменения',{exact:true}).fill('Создание изолированного push-черновика');await page.getByRole('button',{name:'Сохранить черновик',exact:true}).click();await page.locator('#push-command').waitFor();const pushDraftId=new URLSearchParams(new URL(page.url()).hash.split('?')[1]).get('id');assert.equal((await marketplace.store.get(pushDraftId)).status,'draft');
  await page.getByLabel('Основание действия',{exact:true}).fill('Проверка аудитории и тестового аккаунта');await page.getByRole('button',{name:'Предпросмотр аудитории',exact:true}).click();await page.locator('#push-preview').filter({hasText:'Получателей с разрешённым каналом'}).waitFor();await page.getByRole('button',{name:'Запланировать после проверки',exact:true}).click();await page.locator('#push-command [role=alert]').filter({hasText:'другого сотрудника'}).waitFor();assert.equal((await marketplace.store.get(pushDraftId)).status,'draft');
  await page.locator('#push-command select[name=test_ids]').selectOption(applicant.user.id);await page.getByRole('button',{name:'Создать тестовую отправку',exact:true}).click();await page.locator('#push-result a').waitFor();const testCampaignId=(await marketplace.store.all('push_campaign','KZ')).find(c=>c.test_of===pushDraftId).id;assert.equal((await marketplace.store.get(testCampaignId)).status,'scheduled');
  await page.getByRole('button',{name:'Отменить будущие отправки',exact:true}).click();await page.getByRole('heading',{name:'Результат push-кампании',exact:true}).waitFor();assert.equal((await marketplace.store.get(pushDraftId)).status,'canceled');
  let scenarioBulkId;
  for(const action of ['pause_contractors','resume_contractors']){
    await page.goto(frontend+'/#bulk-preview');await page.locator('#bulk-preview').waitFor();await page.locator('#bulk-preview select[name=action]').selectOption(action);await page.locator('#bulk-preview input[name=ids][value="'+profile.id+'"]').check();await page.getByLabel('Основание операции',{exact:true}).fill('Изолированная проверка массового изменения профиля');await page.getByRole('button',{name:'Рассчитать влияние',exact:true}).click();await page.locator('#bulk-execute').waitFor();scenarioBulkId=new URLSearchParams(new URL(page.url()).hash.split('?')[1]).get('id');assert.equal((await marketplace.store.get(scenarioBulkId)).status,'previewed');await page.locator('#bulk-execute input[name=confirm]').check();await page.getByLabel('Основание подтверждения',{exact:true}).fill('Проверил состав и подтверждаю операцию');await page.getByRole('button',{name:'Выполнить операцию',exact:true}).click();await page.getByRole('heading',{name:'Результат операции',exact:true}).waitFor();assert.equal((await marketplace.store.get(profile.id)).status,action==='pause_contractors'?'paused':'published');
  }
  const accountIncident={id:randomUUID(),kind:'case',owner:applicant.user.id,country:'KZ',version:1,created_at:new Date().toISOString(),target_type:'user',target_id:professional.user.id,subject_user_id:professional.user.id,status:'new',reporter_private:true,description:'Изолированное основание ручной проверки'};await marketplace.store.put(accountIncident);
  await page.goto(frontend+'/#bulk-preview?accounts=1');await page.locator('#account-bulk-preview').waitFor();await page.getByLabel('Аккаунт и дело: по одной паре UUID через пробел в строке',{exact:true}).fill(professional.user.id+' '+accountIncident.id);await page.getByLabel('Срок ограничения (UTC)',{exact:true}).fill(new Date(Date.now()+3600000).toISOString().slice(0,16));await page.getByLabel('Основание операции',{exact:true}).fill('Проверка отдельного массового ограничения аккаунтов');await page.getByRole('button',{name:'Рассчитать влияние на аккаунты',exact:true}).click();await page.locator('#account-bulk-execute').waitFor();const accountBulkId=new URLSearchParams(new URL(page.url()).hash.split('?')[1]).get('id');const accountBulk=await marketplace.store.get(accountBulkId);assert.equal(accountBulk.eligible_count,1);
  await page.locator('#account-bulk-execute input[name=confirm]').check();await page.getByLabel('Основание подтверждения',{exact:true}).fill('Независимая проверка выборки и последствий');await page.getByRole('button',{name:'Подтвердить ограничения',exact:true}).click();await page.locator('#account-bulk-execute [role=alert]').filter({hasText:'другой сотрудник'}).waitFor();assert.equal((await marketplace.store.get(professional.user.id)).status,'active');
  const bulkResponse=await fetch(origin+'/api/v1/admin/account-restriction-jobs/'+accountBulkId+'/execute',{method:'POST',headers:{authorization:'Bearer '+approvalSession.access_token,'content-type':'application/json','idempotency-key':randomUUID()},body:JSON.stringify({expected_version:accountBulk.version,confirm:true,reason:'Независимо подтверждаю временное ограничение'})});assert.equal(bulkResponse.status,200);await page.locator('#refresh-data').click();await page.getByText('Ограничение применено',{exact:true}).waitFor();assert.equal((await marketplace.store.get(professional.user.id)).status,'restricted');
  await page.getByRole('button',{name:'Выйти',exact:true}).click();await page.waitForSelector('#staff-login');
  const {createServer}=await import('vite');
  webVite=await createServer({root:resolve(__dirname,'../apps/web'),configFile:resolve(__dirname,'../apps/web/vite.config.ts'),server:{port:0,strictPort:false,host:'127.0.0.1'}});await webVite.listen();
  const web='http://127.0.0.1:'+webVite.httpServer.address().port;
  await marketplace.store.put({...legal,id:randomUUID(),status:'published',content:'Опубликованная политика: <script>window.untrustedLegal=true</script> Текст отображается безопасно.'});
  await page.goto(web+'/W03.html');
  await page.locator('.legal-paper').filter({hasText:'Опубликованная политика'}).waitFor();
  assert.equal(await page.evaluate(()=>window.untrustedLegal),undefined);
  await page.getByRole('link',{name:'Условия использования',exact:true}).click();
  await page.locator('.legal-paper').filter({hasText:'пока не опубликован'}).waitFor();
  await page.goto(web+'/W05.html');
  await page.locator('.status-history').filter({hasText:'Конфигурация получена'}).waitFor();
  assert.equal(await page.locator('.status-row').count(),4);
  assert.deepEqual((await page.locator('.status-row .left b').allTextContents()).sort(),['Беларусь','Казахстан','Россия','Сербия']);
  assert.equal(await page.getByText('Оплата недоступна. Поддержка и управление данными доступны.',{exact:true}).count(),4);
  await page.goto(web+'/W02.html');
  await page.locator('#message').fill('Проверка обращения и восстановления переписки при обновлении страницы');
  await page.locator('form button[type=submit]').click();
  await page.locator('#recovery-history').filter({hasText:'Проверка обращения'}).waitFor();
  await page.reload();await page.locator('#recovery-history').filter({hasText:'Проверка обращения'}).waitFor();
  assert.equal((await marketplace.store.all('recovery','KZ')).length,1);
  if(process.env.JOBA_BROWSER_INVENTORY_DIR){
    const output=process.env.JOBA_BROWSER_INVENTORY_DIR;await mkdir(output,{recursive:true});
    const captureJob=randomUUID();await marketplace.store.put({...await marketplace.store.get(detailJob),id:captureJob,version:1,status:'failed',attempts:3,failure_code:'EXPORT_RETRY_REQUIRED',fixture:true});
    const frames=JSON.parse(await readFile(resolve(__dirname,'../docs/design/screen-audit.json'),'utf8')).frames;
    const inventory=[];
    const captureFrame=async(frame,address,actualRoute=frame.design_route)=>{
      await page.setViewportSize(frame.viewport);await page.goto(address);await page.waitForLoadState('networkidle');
      await page.waitForFunction(()=>!document.querySelector('[aria-busy=true]'));
      const filename=(frame.id+'-'+frame.design_route).replace(/[^A-Za-z0-9._-]/g,'-')+'.png';
      await page.screenshot({path:join(output,filename),fullPage:false});
      const text=await page.locator('body').innerText();
      inventory.push({id:frame.id,route:frame.design_route,surface:frame.surface,capture:filename,reference_png:frame.reference_png,actual_route:actualRoute,errors:text.includes('Сценарий этого раздела ещё не подключён к API.')?['Live scenario not implemented']:[],visual_acceptance:'pending'});
    };
    const login=frames.find(frame=>frame.surface==='admin'&&frame.design_route==='login');
    await captureFrame(login,frontend+'/#login');
    await page.getByLabel('Рабочий идентификатор').fill('staff-browser-test');await page.getByLabel('Пароль',{exact:true}).fill(password);
    await page.getByRole('button',{name:'Продолжить',exact:true}).click();
    // Re-login must not reuse the first login's one-time code when this fast
    // isolated run happens to complete within the same 30-second TOTP window.
    const nextMfaWindow=(Math.floor(firstMfaTime/30000)+1)*30000;
    if(Date.now()<nextMfaWindow)await new Promise(resolve=>setTimeout(resolve,nextMfaWindow-Date.now()+50));
    await page.getByLabel('Код второго фактора').fill(totp(secret));await page.getByRole('button',{name:'Продолжить',exact:true}).click();await page.waitForSelector('#staff-logout');
    // Detail screens require a real object identifier. Bind only equivalent
    // detail views; never alias review/dialog states to a generic parent page.
    const details={
      'user-detail':'record-live/users/'+applicant.user.id,
      'order-detail':'record-live/orders/'+caseOrder.id,
      'case':'case-live/'+caseReport.id,
      'verification-detail':'record-live/verification/'+verificationId,
      'user-security':'user-security?user_id='+applicant.user.id,
      'user-orders':'user-orders?user_id='+professional.user.id,
      'user-cases':'user-cases?user_id='+applicant.user.id,
      'user-decisions':'user-decisions?user_id='+professional.user.id,
      'job-detail':'job-detail?job_id='+captureJob,
      'branding-build':'branding-build?version='+brand.id,
      'dictionary-dryrun':'dictionary-dryrun?id='+scenarioDictionary,
      'security-full':'security-full?id='+(await marketplace.store.all('security_event','KZ'))[0].id,
      'bulk-preview':'bulk-preview?accounts=1',
      'bulk-result':'bulk-result?accounts=1&id='+accountBulkId,
      'revision-conflict':'revision-conflict?id='+caseReport.id,
      'verification-review':'verification-review?id='+verificationId,
      'id-auth':'id-auth?id='+verificationId
    };
    for(const frame of frames.filter(frame=>frame.surface==='admin'&&frame.design_route!=='login')){
      const actualRoute=details[frame.design_route]??frame.design_route;
      await captureFrame(frame,frontend+'/#'+actualRoute,actualRoute);
    }
    await page.getByRole('button',{name:'Выйти',exact:true}).click();
    await page.getByLabel('Рабочий идентификатор').waitFor();
    assert.equal(await page.evaluate(()=>['user-detail','user-security','user-orders','user-cases','user-decisions','job-detail','scheduled','boosts','boost-grant','branding-build'].some(key=>window.JOBA_ADMIN.routes[key])),false);
    // Functional recovery persistence was already checked above. Baseline W02
    // is the initial support form, not the conversation from that prior test.
    await page.goto(web+'/W02.html');await page.evaluate(()=>sessionStorage.removeItem('joba.recovery'));
    for(const frame of frames.filter(frame=>frame.surface==='public'))await captureFrame(frame,web+'/'+frame.design_route+'.html');
    await writeFile(join(output,'inventory.json'),JSON.stringify({scenario:'isolated real HTTP API; unsupported routes remain pending',frames:inventory},null,2)+'\n');
  }
  console.log('Admin browser: account selection, scoped user orders/status filters/cases/decision timeline/masked security, job details and scheduled queue, logout clears private views, real MFA login, live dashboard, UTC period selection, report export, masked security events, audited job retry, identity, draft save, validation, lost-response retries without duplicate drafts or support messages, real photo download, profile approval and draft rejection, independent approval rejection, verification decision, audited phone disclosure, runtime settings, legal drafts, live availability and public support persistence, live branding upload/crop/preview/independent approval/iconset download, frozen case evidence and actual content hiding passed.');
 }catch(error){if(page){await page.screenshot({path:'/tmp/joba-admin-browser-failure.png',fullPage:true});console.error('Page diagnostics:',await page.locator('[role=alert], .note.danger').allTextContents());}throw error;}finally{await browser?.close();await vite?.close();await webVite?.close();await app.close();await marketplace.store.close();await rm(files,{recursive:true,force:true});}
}
main().catch(error=>{console.error(error.message);process.exitCode=1;});
