const {createServer}=require('node:http'),{readFile,stat}=require('node:fs/promises'),{resolve,extname,sep}=require('node:path');
const {chromium}=require('@playwright/test');const assert=require('node:assert/strict');
async function main(){
 const root=resolve(__dirname,'../apps/mobile/build/web'),errors=[];
 const mime={'.html':'text/html','.js':'text/javascript','.json':'application/json','.wasm':'application/wasm','.ttf':'font/ttf','.otf':'font/otf','.png':'image/png','.jpeg':'image/jpeg'};
 const server=createServer(async(req,res)=>{try{const pathname=decodeURIComponent(new URL(req.url,'http://localhost').pathname),file=resolve(root,'.'+(pathname==='/'?'/index.html':pathname));if(!file.startsWith(root+sep))throw Error('Invalid path');await stat(file);res.setHeader('Content-Type',mime[extname(file)]||'application/octet-stream');res.end(await readFile(file));}catch{res.statusCode=404;res.end();}});
 await new Promise(resolve=>server.listen(0,'127.0.0.1',resolve));let browser;
 try{
  browser=await chromium.launch({executablePath:process.env.JOBA_CHROMIUM_PATH||'/usr/bin/chromium',args:['--no-sandbox']});
  for(const country of ['Казахстан','Кыргызстан','Россия','Беларусь']){
   const context=await browser.newContext({viewport:{width:390,height:844}}),page=await context.newPage();
   try{
    page.on('pageerror',error=>errors.push(error.message));await page.goto('http://127.0.0.1:'+server.address().port);
    await page.locator('flutter-view').waitFor({timeout:60000});const semantics=page.locator('flt-semantics-placeholder');if(await semantics.count())await semantics.evaluate(el=>el.click());
    await page.getByRole('button',{name:'Продолжить',exact:true}).waitFor({timeout:30000});await page.getByText(new RegExp('^'+country)).click();
    await page.getByRole('button',{name:'Продолжить',exact:true}).click();await page.getByRole('button',{name:'Войти',exact:true}).waitFor({timeout:15000});
    assert.equal(await page.getByText('Регион пока недоступен',{exact:false}).count(),0);
   }catch(error){await page.screenshot({path:'/tmp/joba-release-country-failure.png'});throw error;}finally{await context.close();}
  }
  assert.deepEqual(errors,[]);console.log('Release Flutter: KZ/KG/RU/BY select their configured API and reach login without region errors.');
 }finally{await browser?.close();await new Promise(resolve=>server.close(resolve));}
}
main().catch(error=>{console.error(error.stack||error.message);process.exitCode=1;});
