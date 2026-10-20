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
 let browser,server;
 try{
  const id=randomUUID(),password='Isolated mobile admin password!';
  await api.store.put({id,kind:'user',owner:id,country:'KZ',version:1,created_at:new Date().toISOString(),display_name:'Мобильная проверка',phone:'mobile-admin-test',roles:['customer'],staff_permissions:['platform_owner','administrator','content','billing'],staff_auth_mode:'password',status:'active',fixture:true});
  await api.store.db.query('INSERT INTO credentials(country,phone,user_id,password_hash) VALUES($1,$2,$3,$4)',['KZ','mobile-admin-test',id,await hash(password)]);
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
  const errors=[];page.on('pageerror',error=>errors.push(error.message));
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
   for(const route of ['dashboard','users','categories','prices','settings','countries','legal','staff-access']){
    console.log('Checking',width,route);await page.goto(frontend+'/#'+route);await page.locator('.workspace').waitFor();
    await page.waitForLoadState('networkidle');
    if(route==='dashboard'){await page.locator('#server-metrics').getByText('Сервер — ресурсы и нагрузка',{exact:true}).waitFor();assert(await page.locator('#server-metrics').getByText('Оперативная память',{exact:true}).isVisible());await Promise.all([page.waitForResponse(r=>r.url().includes('/admin/server-metrics')&&r.status()===200),page.locator('#server-metrics [data-server-refresh]').click()]);await page.locator('#server-metrics svg').waitFor();}

    const dimensions=await page.evaluate(()=>({width:innerWidth,scroll:document.documentElement.scrollWidth}));
    assert(dimensions.scroll<=width+1,`${route} overflows ${width}: ${dimensions.scroll}`);
    const menu=page.locator('[data-action="navigation"]');await menu.click();
    await page.locator('.sidebar.open').waitFor();assert.equal(await menu.getAttribute('aria-expanded'),'true');
    assert.equal(await page.locator('.main').evaluate(e=>e.inert),true);
    await page.keyboard.press('Escape');assert.equal(await menu.getAttribute('aria-expanded'),'false');
    await menu.click();await page.locator('.mobile-menu-backdrop').click({position:{x:width-5,y:500}});
    assert.equal(await menu.getAttribute('aria-expanded'),'false');
    if(output&&width===393)await page.screenshot({path:join(output,route+'.png'),fullPage:true});
   }
  }
  await page.setViewportSize({width:393,height:852});await page.goto(frontend+'/#users');await page.locator('.tablewrap').waitFor();
  assert(await page.locator('.tablewrap').first().evaluate(e=>e.scrollWidth>e.clientWidth));
  await page.locator('.tablewrap').first().evaluate(e=>e.scrollLeft=e.scrollWidth);
  assert(await page.locator('.tablewrap').first().evaluate(e=>e.scrollLeft>0));
  await page.getByRole('button',{name:'Навигация',exact:true}).click();
  await page.locator('.sidebar a[href="#categories"]').click();await page.waitForURL('**/#categories');
  assert.equal(await page.locator('.sidebar.open').count(),0);
  await page.setViewportSize({width:1440,height:1000});
  assert.equal(await page.locator('.sidebar').evaluate(e=>e.inert),false);
  assert.equal(await page.getByRole('button',{name:'Навигация',exact:true}).isVisible(),false);
  assert.deepEqual(errors,[]);console.log('Mobile admin verified: 40 page/viewport combinations, menu, backdrop, Escape, table scroll, navigation, desktop resize');
 }finally{if(browser)await browser.close();if(server)await new Promise(resolve=>server.close(resolve));await app.close();await api.store.close();await rm(files,{recursive:true,force:true});}
}
main().catch(error=>{console.error(error);process.exitCode=1;});
