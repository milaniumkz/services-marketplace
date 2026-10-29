const {mkdtemp,rm,mkdir,readFile}=require('node:fs/promises');
const {tmpdir}=require('node:os');
const {join,resolve}=require('node:path');
const {randomUUID}=require('node:crypto');
const {hash}=require('@node-rs/argon2');
const {chromium}=require('@playwright/test');
const assert=require('node:assert/strict');
async function main(){
 const files=await mkdtemp(join(tmpdir(),'joba-admin-mobile-'));
 process.env.JOBA_DATA_DIR='memory://';process.env.JOBA_UPLOAD_DIR=files;delete process.env.DATABASE_URL;
 const {NestFactory}=require('@nestjs/core'),{AppModule,getMarketplace}=require('../services/api/dist/app.module');
 console.log('Starting isolated API');
 process.env.JOBA_SERVER_METRICS_FILE=join(files,'metrics.json');
 const app=await NestFactory.create(AppModule,{logger:false});const api=await getMarketplace();
 await require('./publish-role-access.cjs').publishRoleAccess(api.store);
 let browser,server;
 try{
  const id=randomUUID(),password='Isolated mobile admin password!';
  await api.store.put({id,kind:'user',owner:id,country:'KZ',version:1,created_at:new Date().toISOString(),display_name:'Мобильная проверка',phone:'mobile-admin-test',roles:['customer'],staff_permissions:['platform_owner','administrator','content','billing','identity_view','verification_reviewer'],staff_auth_mode:'password',status:'active',fixture:true});
  await api.store.db.query('INSERT INTO credentials(country,phone,user_id,password_hash) VALUES($1,$2,$3,$4)',['KZ','mobile-admin-test',id,await hash(password)]);
  const subjectId=randomUUID(),verificationId=randomUUID(),photoIds=[];
  const created=new Date().toISOString();
  await api.store.put({id:subjectId,kind:'user',owner:subjectId,country:'KZ',version:1,created_at:created,display_name:'Заявитель проверки',phone:'+77000000123',roles:['customer'],active_role:'customer',locale:'ru',city:'Караганда',status:'active',verification:'not_started'});
  for(const color of ['red','blue','green']){const fileId=randomUUID(),bytes=await require('sharp')({create:{width:32,height:48,channels:3,background:color}}).jpeg().toBuffer();await api.files.write(fileId,bytes);await api.store.put({id:fileId,kind:'upload',owner:subjectId,country:'KZ',version:1,created_at:created,purpose:'identity',verification_id:verificationId,mime:'image/jpeg',size:bytes.length,status:'clean'});photoIds.push(fileId);}
  await api.store.put({id:verificationId,kind:'verification',owner:subjectId,country:'KZ',version:2,created_at:created,status:'pending_review',document_type:'id_card',document_revision:2,document_refs:photoIds,required_pages:['Лицевая сторона удостоверения','Обратная сторона удостоверения','Селфи'],selfie_index:2});
  const executorId=randomUUID(),contractorId=randomUUID(),portfolioId=randomUUID(),avatarId=randomUUID(),workId=randomUUID();
  await api.store.put({id:executorId,kind:'user',owner:executorId,country:'KZ',version:1,created_at:created,display_name:'Исполнитель подробной карточки',phone:'+77000000456',roles:['executor'],active_role:'executor',city:'Караганда',status:'active',verification:'passed',avatar_id:avatarId});
  for(const [fileId,purpose] of [[avatarId,'avatar'],[workId,'portfolio']]){const bytes=await require('sharp')({create:{width:32,height:48,channels:3,background:'purple'}}).jpeg().toBuffer();await api.files.write(fileId,bytes);await api.store.put({id:fileId,kind:'upload',owner:executorId,country:'KZ',version:1,created_at:created,purpose,mime:'image/jpeg',size:bytes.length,status:'clean'});}
  await api.store.put({id:contractorId,kind:'contractor',owner:executorId,country:'KZ',version:2,created_at:created,title:'Услуги штукатура',description:'Штукатурка стен и отделка помещений',city:'Караганда',gallery_ids:[workId],experience_years:5,service_cities:['Караганда'],travel_radius_km:20,work_modes:['onsite'],languages:['ru'],availability:'available',price:{mode:'hourly',amount_min:500000,currency:'KZT'},status:'pending_review'});
  await api.store.put({id:portfolioId,kind:'portfolio',owner:executorId,country:'KZ',version:1,created_at:created,title:'Отделка квартиры',description:'Проект отделки квартиры',photos:[workId],status:'pending_review'});
  await app.listen(0,'127.0.0.1');const origin=await app.getUrl();
  const {createServer}=require('node:http');const root=resolve(__dirname,'../apps/admin/dist');
  server=createServer(async(req,res)=>{try{
    const path=resolve(root,'.'+new URL(req.url,'http://localhost').pathname.replace(/\/$/,'/index.html'));
    if(!path.startsWith(root+'/')){res.writeHead(403).end();return;}
    const body=await readFile(path);const ext=path.split('.').at(-1);
    res.setHeader('Content-Type',({html:'text/html',js:'text/javascript',css:'text/css',ttf:'font/ttf',png:'image/png',jpeg:'image/jpeg'})[ext]||'application/octet-stream');res.end(body);
  }catch{res.writeHead(404).end();}});
  await new Promise(resolve=>server.listen(0,'127.0.0.1',resolve));
  const frontend='http://127.0.0.1:'+server.address().port;console.log('API and built frontend ready');
  browser=await chromium.launch({executablePath:process.env.JOBA_CHROMIUM_PATH||'/usr/bin/chromium',args:['--no-sandbox']});
  const page=await browser.newPage({viewport:{width:393,height:852},isMobile:true,hasTouch:true});
  const errors=[];page.on('pageerror',error=>{console.error('Browser error at',page.url(),error.stack);errors.push(error.message);});
  await page.route('**/api/v1/**',async route=>{
   const r=route.request(),u=new URL(r.url());
   if(u.pathname.endsWith('/admin/server-metrics'))require('node:child_process').execFileSync('python3',[resolve(__dirname,'collect-server-metrics.py'),'--output-dir',files]);
   const response=await fetch(origin+u.pathname+u.search,{method:r.method(),headers:r.headers(),body:['GET','HEAD'].includes(r.method())?undefined:r.postDataBuffer()});
   await route.fulfill({status:response.status,headers:{'content-type':response.headers.get('content-type')||'application/json'},body:Buffer.from(await response.arrayBuffer())});
  });
  console.log('Opening mobile login');await page.goto(frontend+'/#login');
  await page.getByLabel('Логин').fill('mobile-admin-test');await page.getByLabel('Пароль',{exact:true}).fill(password);
  await page.getByRole('button',{name:'Продолжить',exact:true}).click();await page.locator('#staff-logout').waitFor();console.log('Mobile login passed');
  const output=process.env.JOBA_ADMIN_MOBILE_SCREENSHOTS;if(output)await mkdir(output,{recursive:true});
  for(const width of [320,360,393,430,768]){
   await page.setViewportSize({width,height:852});
   for(const route of ['dashboard','users','categories','pricing','settings','countries','legal','staff-access','monetization','record-live/verification/'+verificationId,'verification','record-live/contractors/'+contractorId]){
    console.log('Checking',width,route);await page.goto(frontend+'/#'+route);await page.locator('.workspace').waitFor();
    await page.waitForLoadState('networkidle');
    assert.equal(await page.locator('form [name=reason]:visible, form [name=confirm]:visible').count(),0,'No manual audit/confirmation fields on '+route);
    if(route==='dashboard'){await page.locator('#server-metrics').getByText('Сервер — ресурсы и нагрузка',{exact:true}).waitFor();assert(await page.locator('#server-metrics').getByText('Оперативная память',{exact:true}).isVisible());await Promise.all([page.waitForResponse(r=>r.url().includes('/admin/server-metrics')&&r.status()===200),page.locator('#server-metrics [data-server-refresh]').click()]);await page.locator('#server-metrics svg').waitFor();}

    if(route==='dashboard'){assert.equal(await page.locator('#review-queues').getByRole('heading',{name:'Заказчики — проверка личности — 1',exact:true}).count(),1);assert.equal(await page.locator('#review-queues').getByRole('heading',{name:'Портфолио на проверке — 1',exact:true}).count(),1);await page.getByRole('button',{name:'Обновить очереди',exact:true}).click();await page.locator('#review-queues-status').getByText('Обновлено:',{exact:false}).waitFor();}
    if(route==='verification'){await page.locator('.tablewrap').getByText('Ожидает проверки',{exact:true}).waitFor();assert.equal(await page.locator('.tablewrap').getByText('pending_review',{exact:true}).count(),0);}
    if(route.startsWith('record-live/contractors/')){await page.getByText('Исполнитель подробной карточки',{exact:true}).waitFor();await page.getByText('Отделка квартиры',{exact:true}).waitFor();await page.waitForFunction(()=>document.querySelectorAll('#content-media-result img').length===2&&[...document.querySelectorAll('#content-media-result img')].every(image=>image.complete&&image.naturalWidth>0&&!image.hidden));assert.equal(await page.locator('#content-media-result figcaption').allTextContents().then(x=>x.join('|')),'Фото профиля|Фотография работы 1');await page.locator('#content-media-result').getByRole('button',{name:'Увеличить',exact:true}).first().click();assert.equal(await page.locator('#content-media-result .expanded').count(),1);}
    if(route==='pricing'){assert.equal(await page.locator('#subscription-catalog [name=customer]').inputValue(),'500.00');assert.equal(await page.locator('#subscription-catalog [name=standard]').inputValue(),'1000.00');assert.equal(await page.locator('#subscription-catalog [name=premium]').inputValue(),'1500.00');}
    if(route==='monetization'){await page.locator('#test-payment-mode').waitFor();assert.equal(await page.locator('#test-payment-mode [name=enabled]').isChecked(),true);}
    if(route==='legal'){await page.locator('[data-legal-revise]').first().click();assert.equal(await page.locator('#legal-type').inputValue(),'verification_consent');}
    if(route.startsWith('record-live/verification/')){
      await page.getByText('Заявитель проверки',{exact:true}).waitFor();
      assert.equal(await page.locator('#review-decision [name=expires_at]').count(),0);assert.equal(await page.locator('#review-decision option[value=passed]').textContent(),'Подтвердить личность — бессрочно');
      await page.getByText('Караганда',{exact:true}).waitFor();
      await page.getByText('Полный телефон: +77000000123',{exact:true}).waitFor();
      await page.waitForFunction(()=>document.querySelectorAll('.verification-photo img').length===3&&[...document.querySelectorAll('.verification-photo img')].every(image=>image.complete&&image.naturalWidth>0&&!image.hidden));
      assert.equal(await page.locator('.verification-photo figcaption').allTextContents().then(labels=>labels.join('|')),'Лицевая сторона удостоверения|Обратная сторона удостоверения|Селфи');
      await page.getByRole('button',{name:'Увеличить',exact:true}).first().click();assert.equal(await page.locator('.verification-photo.expanded').count(),1);
    }
    const dimensions=await page.evaluate(()=>({width:innerWidth,scroll:document.documentElement.scrollWidth}));
    assert(dimensions.scroll<=width+1,`${route} overflows ${width}: ${dimensions.scroll}`);
    const menu=page.locator('[data-action="navigation"]');await menu.click();
    await page.locator('.sidebar.open').waitFor();assert.equal(await menu.getAttribute('aria-expanded'),'true');
    assert.equal(await page.locator('.main').evaluate(e=>e.inert),true);
    await page.keyboard.press('Escape');assert.equal(await menu.getAttribute('aria-expanded'),'false');
    await menu.click();await page.locator('.mobile-menu-backdrop').click({position:{x:width-5,y:500}});
    assert.equal(await menu.getAttribute('aria-expanded'),'false');
    if(output&&width===393)await page.screenshot({path:join(output,route.replaceAll('/','-')+'.png'),fullPage:true});
   }
  }
  await page.setViewportSize({width:393,height:852});
  await page.goto(frontend+'/#dashboard');await page.locator('#review-queues').waitFor();
  const sectionRoutes=await page.locator('.nav a[href^="#"]').evaluateAll(links=>[...new Set(links.filter(a=>!a.hidden&&a.style.display!=='none').map(a=>a.hash.slice(1)))]);
  for(const route of sectionRoutes){
    console.log('Checking full section',route);await page.goto(frontend+'/#'+route);await page.locator('.workspace').waitFor();await page.waitForLoadState('networkidle');
    assert.equal(await page.locator('form [name=reason]:visible,form [name=confirm]:visible').count(),0,'No manual reason/confirmation in '+route);
    assert.equal(await page.getByRole('heading',{name:'Карточка недоступна',exact:true}).count(),0,'Section is accessible: '+route);
  }
  console.log('All navigation sections verified:',sectionRoutes.length,sectionRoutes.join(', '));
  await page.goto(frontend+'/#dashboard');await page.locator('#review-queues').waitFor();await page.locator('#review-queues a[href="#verification?status=pending_review&owner_role=customer"]').click();await page.waitForLoadState('networkidle');assert.equal(await page.locator('.workspace [name=status]').inputValue(),'pending_review');assert.equal(await page.locator('.workspace a[href="#record-live/verification/'+verificationId+'"]').count(),1);
  await page.goto(frontend+'/#monetization');await page.locator('#test-payment-mode').waitFor();
  for(const enabled of [false,true]){
    await page.locator('#test-payment-mode [name=enabled]').setChecked(enabled);
    await Promise.all([page.waitForResponse(r=>r.url().includes('/admin/test-payments')&&r.request().method()==='PUT'&&r.status()===200),page.locator('#test-payment-mode button').click()]);
    await page.waitForLoadState('networkidle');assert.equal((await api.store.all('test_payment_settings','KZ'))[0].enabled,enabled);
  }
  await page.setViewportSize({width:393,height:852});await page.goto(frontend+'/#users');await page.locator('.tablewrap').waitFor();
  assert(await page.locator('.tablewrap').first().evaluate(e=>e.scrollWidth>e.clientWidth));
  await page.locator('.tablewrap').first().evaluate(e=>e.scrollLeft=e.scrollWidth);
  assert(await page.locator('.tablewrap').first().evaluate(e=>e.scrollLeft>0));
  await page.getByRole('button',{name:'Навигация',exact:true}).click();
  await page.locator('.sidebar a[href="#categories"]').click();await page.waitForURL('**/#categories');
  assert.equal(await page.locator('.sidebar.open').count(),0);
  await page.setViewportSize({width:1440,height:1000});
  await page.waitForFunction(()=>document.querySelector('.sidebar')?.inert===false);
  assert.equal(await page.locator('.sidebar').evaluate(e=>e.inert),false);
  assert.equal(await page.getByRole('button',{name:'Навигация',exact:true}).isVisible(),false);
  const orderPhotoId=randomUUID(),orderId=randomUUID();
  const orderBytes=await require('sharp')({create:{width:32,height:48,channels:3,background:'orange'}}).jpeg().toBuffer();
  await api.files.write(orderPhotoId,orderBytes);await api.store.put({id:orderPhotoId,kind:'upload',owner:subjectId,country:'KZ',version:1,created_at:created,purpose:'order',mime:'image/jpeg',size:orderBytes.length,status:'clean'});
  await api.store.put({id:orderId,kind:'order',owner:subjectId,country:'KZ',version:1,created_at:created,title:'Проверка подробной карточки заказа',description:'Отделка стен в жилом доме',city:'Караганда',exact_address:'Тестовый адрес заказа',budget_amount:500000,currency:'KZT',status:'open',upload_ids:[orderPhotoId]});
  await page.goto(frontend+'/#record-live/orders/'+orderId);await page.getByText('Тестовый адрес заказа',{exact:true}).waitFor();
  await page.waitForFunction(()=>document.querySelectorAll('#content-media-result img').length===1&&[...document.querySelectorAll('#content-media-result img')].every(image=>image.complete&&image.naturalWidth>0&&!image.hidden));
  assert.equal(await page.locator('#content-media [name=reason]').count(),0);
  console.log('Detailed order and its private photograph open automatically');
  // Real UI -> isolated API: contact read and account commands must work without guessing a reason field.
  await page.goto(frontend+'/#record-live/users/'+subjectId);await page.locator('#sensitive-read').waitFor();
  assert.equal(await page.locator('#sensitive-read [name=reason]').count(),0);
  await page.locator('#sensitive-result').getByText('Телефон: +77000000123',{exact:true}).waitFor();
  await page.waitForFunction(()=>document.querySelectorAll('[data-user-section=identity] img').length===3&&[...document.querySelectorAll('[data-user-section=identity] img')].every(image=>image.complete&&image.naturalWidth>0));
  console.log('Phone, two document sides and selfie open automatically in complete user overview');
  page.on('dialog',dialog=>{throw Error('Account actions must not open confirmation dialogs');});
  for(const action of ['block','unblock']){
    assert.equal(await page.locator('#account-action [name=reason]').count(),0);
    assert.equal(await page.locator('#account-action [name=confirmation]').count(),0);
    await Promise.all([page.waitForResponse(r=>r.url().endsWith('/admin/users/'+subjectId+'/'+action)&&r.status()===200),page.locator('#account-action button[value='+action+']').click()]);
    await page.waitForLoadState('networkidle');await page.locator('#account-action').waitFor();
    assert.equal((await api.store.get(subjectId)).status,action==='block'?'blocked':'active');
  }
  assert.equal(await page.locator('#account-action input, #account-action textarea, #account-action select').count(),0);
  assert.equal(await page.locator('#account-action [name=confirmation]').count(),0);
  await Promise.all([page.waitForResponse(r=>r.url().endsWith('/admin/users/'+subjectId+'/delete')&&r.status()===200),page.locator('#account-action').getByRole('button',{name:'Удалить аккаунт',exact:true}).click()]);
  await page.waitForURL('**/#users');
  assert.equal((await api.store.get(subjectId)).status,'deleted');
  await page.waitForLoadState('networkidle');
  assert.equal(await page.locator('.tablewrap a[href*="'+subjectId+'"]').count(),0);
  assert.equal(await page.locator('.tablewrap').getByText('Заявитель проверки',{exact:true}).count(),0);
  const audits=await api.store.all('audit','KZ');
  for(const action of ['user.phone_read','user.block','user.unblock','user.deletion_requested'])assert(audits.some(r=>r.action===action));
  console.log('Contact, block, unblock and simple deletion verified through browser and real isolated API');
  await page.goto(frontend+'/#referrals?new=1');await page.locator('#referral-editor').waitFor();
  await page.getByLabel('Название',{exact:true}).fill('Персональная скидка за друзей');await page.getByLabel('Приглашений для награды',{exact:true}).fill('3');await page.getByLabel('Процент скидки',{exact:true}).fill('25');
  await Promise.all([page.waitForResponse(r=>r.url().endsWith('/admin/referral-campaigns')&&r.request().method()==='POST'&&r.status()===200),page.getByRole('button',{name:'Создать новый черновик',exact:true}).click()]);
  await page.waitForFunction(()=>location.hash.includes('referrals?id=')&&!!document.querySelector('#referral-command'));
  const referralId=new URLSearchParams(new URL(page.url()).hash.split('?')[1]).get('id');let campaign=await api.store.get(referralId);assert.equal(campaign.payload.threshold,3);assert.equal(campaign.payload.discount_percent,25);assert.deepEqual(campaign.payload.discount_services,['all']);
  await page.getByLabel('Награда',{exact:true}).selectOption('subscription_days');await page.getByLabel('Что продлить',{exact:true}).selectOption('top100');
  await Promise.all([page.waitForResponse(r=>r.url().endsWith('/admin/referral-campaigns/'+referralId)&&r.request().method()==='PATCH'&&r.status()===200),page.getByRole('button',{name:'Сохранить черновик',exact:true}).click()]);
  await page.waitForLoadState('networkidle');campaign=await api.store.get(referralId);assert.equal(campaign.payload.reward_kind,'subscription_days');assert.equal(campaign.payload.reward_plan,'top100');
  console.log('Referral UI saves threshold, personal discount and bonus Top-100 without manual reason fields');

  await page.setViewportSize({width:393,height:852});await page.goto(frontend+'/#staff-access');await page.locator('#add-role').waitFor();
  assert.equal(await page.locator('#staff-role-editor').count(),0);assert.equal(await page.locator('#staff-create').count(),0);
  await page.getByRole('button',{name:'Добавить роль',exact:true}).click();await page.locator('#staff-role-dialog').count();await page.locator('dialog[open] #staff-role-editor').waitFor();
  const roleEditor=page.locator('#staff-role-editor');await roleEditor.getByLabel('Название роли',{exact:true}).fill('Оператор из модального окна');
  await roleEditor.locator('[name=grants][value="POST /admin/users/{id}/block"]').check();assert.equal(await roleEditor.locator('[name=grants][value="GET /admin/users"]').isChecked(),true);assert.equal(await roleEditor.locator('[name=grants][value="GET /admin/users/{id}"]').isChecked(),true);assert.equal(await roleEditor.locator('[name=grants][value="sensitive.phone"]').isChecked(),false);
  await roleEditor.locator('[name=grants][value="GET /admin/referral-campaigns/{id}"]').check();
  await roleEditor.getByRole('button',{name:'Сохранить роль',exact:true}).click();await page.locator('dialog[open]').waitFor({state:'detached'});
  const employeeRole=(await api.store.all('staff_role','KZ')).find(r=>r.title==='Оператор из модального окна'),employeeRoleId=employeeRole.id;
  let roleRow=page.locator('#role-directory tbody tr').filter({hasText:'Оператор из модального окна'});await roleRow.waitFor();
  await roleRow.getByRole('button',{name:'Изменить роль',exact:true}).click();await page.locator('#staff-role-editor [name=title]').fill('Оператор мобильной проверки');await page.locator('#staff-role-editor button.primary').click();await page.locator('dialog[open]').waitFor({state:'detached'});
  roleRow=page.locator('#role-directory tbody tr').filter({hasText:'Оператор мобильной проверки'});
  for(const [label,status] of [['Заблокировать роль','blocked'],['Разблокировать роль','active']]){await roleRow.getByRole('button',{name:label,exact:true}).click();await page.waitForFunction(text=>document.querySelector('#staff-workspace-feedback')?.textContent===text,status==='blocked'?'Доступ заблокирован.':'Доступ разблокирован.');assert.equal((await api.store.get(employeeRoleId)).status,status);}
  await page.getByRole('button',{name:'Добавить сотрудника',exact:true}).click();const employeeForm=page.locator('#staff-create');await employeeForm.waitFor();
  await employeeForm.getByLabel('Имя сотрудника',{exact:true}).fill('Сотрудник из админки');await employeeForm.getByLabel('Логин сотрудника',{exact:true}).fill('Browser.Operator');assert.equal(await employeeForm.locator('[name=login]').evaluate(e=>e.checkValidity()),true);await employeeForm.getByLabel('Пароль сотрудника',{exact:true}).fill('Pass12');
  await employeeForm.getByRole('button',{name:'Показать пароль',exact:true}).click();assert.equal(await employeeForm.locator('[name=password]').getAttribute('type'),'text');await employeeForm.getByRole('button',{name:'Скрыть пароль',exact:true}).click();
  await employeeForm.locator('[name=role_ids][value="'+employeeRoleId+'"]').check();await employeeForm.getByRole('button',{name:'Создать сотрудника',exact:true}).click();await page.locator('dialog[open]').waitFor({state:'detached'});
  const employee=(await api.store.all('user','KZ')).find(u=>u.phone==='browser.operator');assert(employee);
  let employeeRow=page.locator('#staff-directory tbody tr').filter({hasText:'browser.operator'});assert.equal(await employeeRow.count(),1);
  await page.locator('#staff-directory-search').fill('нет такого сотрудника');await page.locator('#staff-directory').getByText('Сотрудники не найдены.',{exact:true}).waitFor();await page.locator('#staff-directory-search').fill('browser.operator');
  await employeeRow.getByRole('button',{name:'Изменить данные и роли',exact:true}).click();const edit=page.locator('#staff-edit');await edit.getByLabel('Имя сотрудника',{exact:true}).fill('Изменённый сотрудник');await edit.getByLabel('Логин сотрудника',{exact:true}).fill('Changed.Operator');await edit.getByLabel('Новый пароль (необязательно)',{exact:true}).fill('New456');await edit.getByRole('button',{name:'Сохранить сотрудника',exact:true}).click();await page.locator('dialog[open]').waitFor({state:'detached'});
  await page.locator('#staff-directory-search').fill('changed.operator');employeeRow=page.locator('#staff-directory tbody tr').filter({hasText:'changed.operator'});
  await employeeRow.getByRole('button',{name:'Изменить данные и роли',exact:true}).click();await page.locator('#staff-edit [name=role_ids][value="'+employeeRoleId+'"]').uncheck();await page.locator('#staff-edit button.primary').click();await page.locator('dialog[open]').waitFor({state:'detached'});assert.deepEqual((await api.store.get(employee.id)).staff_role_ids,[]);
  await employeeRow.getByRole('button',{name:'Изменить данные и роли',exact:true}).click();await page.locator('#staff-edit [name=role_ids][value="'+employeeRoleId+'"]').check();await page.locator('#staff-edit button.primary').click();await page.locator('dialog[open]').waitFor({state:'detached'});assert.deepEqual((await api.store.get(employee.id)).staff_role_ids,[employeeRoleId]);
  for(const [label,status] of [['Заблокировать','blocked'],['Разблокировать','active']]){await employeeRow.getByRole('button',{name:label,exact:true}).click();await page.waitForFunction(text=>document.querySelector('#staff-workspace-feedback')?.textContent===text,status==='blocked'?'Доступ заблокирован.':'Доступ разблокирован.');assert.equal((await api.store.get(employee.id)).status,status);}
  await page.locator('#staff-logout').click();await page.getByLabel('Логин',{exact:true}).fill('CHANGED.OPERATOR');assert.equal(await page.getByLabel('Логин',{exact:true}).evaluate(e=>e.checkValidity()),true);assert.equal(await page.getByLabel('Логин',{exact:true}).getAttribute('pattern'),null);await page.getByLabel('Пароль',{exact:true}).fill('New456');await page.getByRole('button',{name:'Продолжить',exact:true}).click();await page.waitForURL('**/#users');await page.locator('.tablewrap').waitFor();
  await page.getByRole('button',{name:'Навигация',exact:true}).click();await page.locator('.sidebar.open').waitFor();assert.equal(await page.locator('.nav a[href="#staff-access"]:visible').count(),0);assert.equal(await page.locator('.nav a[href="#users"]:visible').count(),1);assert.equal(await page.locator('.nav a[href="#referrals"]:visible').count(),1);await page.keyboard.press('Escape');
  await page.locator('#staff-logout').click();await page.getByLabel('Логин',{exact:true}).fill('mobile-admin-test');await page.getByLabel('Пароль',{exact:true}).fill(password);await page.getByRole('button',{name:'Продолжить',exact:true}).click();await page.locator('#staff-logout').waitFor();await page.goto(frontend+'/#staff-access');await page.locator('#staff-directory').waitFor();
  await page.locator('#staff-directory tbody tr').filter({hasText:'changed.operator'}).getByRole('button',{name:'Удалить сотрудника',exact:true}).click();await page.waitForFunction(()=>document.querySelector('#staff-workspace-feedback')?.textContent==='Запись удалена.');assert.equal(await page.locator('#staff-directory').getByText('changed.operator',{exact:true}).count(),0);assert.equal((await api.store.get(employee.id)).status,'deleted');
  await page.locator('#role-directory tbody tr').filter({hasText:'Оператор мобильной проверки'}).getByRole('button',{name:'Удалить роль',exact:true}).click();await page.waitForFunction(()=>!document.querySelector('#role-directory')?.textContent.includes('Оператор мобильной проверки'));assert.equal((await api.store.get(employeeRoleId)).status,'deleted');
  console.log('Modal role creation/edit, automatic navigation, staff edit/password/roles, blocking/unblocking and deletion verified on mobile; uppercase Latin login works without format restrictions');
  assert.ok((await api.store.all('audit','KZ')).some(r=>r.action==='content.avatar_read'));assert.ok((await api.store.all('audit','KZ')).some(r=>r.action==='content.media_read'));assert.deepEqual(errors,[]);console.log('Mobile admin verified: 60 page/viewport combinations, menu, backdrop, Escape, table scroll, navigation, desktop resize');
 }finally{if(browser)await browser.close();if(server)await new Promise(resolve=>server.close(resolve));await app.close();await api.store.close();await rm(files,{recursive:true,force:true});}
}
main().catch(error=>{console.error(error);process.exitCode=1;});
