/* Real, local browser inference smoke check using a public-domain test portrait. */
const http=require('node:http'),fs=require('node:fs'),path=require('node:path'),assert=require('node:assert/strict');
const {chromium}=require('playwright');
const root=path.resolve(__dirname,'../apps/mobile/web');
(async()=>{
 const server=http.createServer((req,res)=>{
  const pathname=new URL(req.url,'http://localhost').pathname;
  if(pathname==='/'){res.setHeader('Content-Type','text/html');res.end('<!doctype html><html><body></body></html>');return;}
  const file=pathname==='/portrait.png'?path.resolve(__dirname,'../services/face/testdata/portrait.png'):path.resolve(root,'.'+pathname);
  if(pathname!=='/portrait.png'&&!file.startsWith(root+path.sep)){res.writeHead(404).end();return;}
  try{res.setHeader('Content-Type',file.endsWith('.wasm')?'application/wasm':file.endsWith('.js')||file.endsWith('.mjs')?'text/javascript':file.endsWith('.png')?'image/png':'application/octet-stream');res.end(fs.readFileSync(file));}catch{res.writeHead(404).end();}
 });
 await new Promise(resolve=>server.listen(0,'127.0.0.1',resolve));
 const base='http://127.0.0.1:'+server.address().port;
 let browser;
 try{
  browser=await chromium.launch({executablePath:process.env.JOBA_CHROMIUM_PATH||'/usr/bin/chromium',headless:true,args:['--no-sandbox','--use-angle=swiftshader','--enable-unsafe-swiftshader']});
  const page=await browser.newPage(),external=[];
  page.on('request',r=>{if(!r.url().startsWith(base)&&!r.url().startsWith('blob:')&&!r.url().startsWith('data:'))external.push(r.url());});
  await page.goto(base);await page.addScriptTag({url:base+'/joba-face-tracker.js'});
  const metrics=await page.evaluate(async()=>{
   const tracker=await globalThis.jobaCreateFaceTracker();
   try{const image=new Image();image.src='/portrait.png';await image.decode();const canvas=document.createElement('canvas');canvas.width=480;canvas.height=640;canvas.getContext('2d').drawImage(image,160,30,150,200,0,0,480,640);return tracker.detect(canvas,performance.now());}finally{tracker.close();}
  });
  assert.equal(metrics.faces,1);for(const k of ['yaw','blinkLeft','blinkRight','smile','width','height'])assert.ok(Number.isFinite(metrics[k]),k);
  assert.deepEqual(external,[]);
  console.log(JSON.stringify({real_browser_landmark_inference:true,single_face_found:true,expression_scores_available:true,all_assets_first_party:true,metrics}));
 }finally{if(browser)await browser.close();await new Promise(resolve=>server.close(resolve));}
})().catch(error=>{console.error(error);process.exitCode=1;});
