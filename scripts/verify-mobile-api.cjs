const {mkdtemp,rm}=require('node:fs/promises');
const {tmpdir}=require('node:os');
const {join,resolve}=require('node:path');
const {spawn}=require('node:child_process');
async function main(){
  const files=await mkdtemp(join(tmpdir(),'joba-mobile-api-'));
  process.env.JOBA_DATA_DIR='memory://';process.env.JOBA_UPLOAD_DIR=files;
  delete process.env.DATABASE_URL;
  const {NestFactory}=require('@nestjs/core');
  const {AppModule,getMarketplace}=require('../services/api/dist/app.module');
  const {startRealtime}=require('../services/api/dist/realtime');
  const express=require('express');
  const app=await NestFactory.create(AppModule,{logger:false,rawBody:true});
  app.use('/api/v1/uploads',express.raw({type:'application/octet-stream',limit:'10mb'}));
  const marketplace=await getMarketplace();
  // Explicit isolated test adapter; this does not validate production antivirus signatures.
  marketplace.providers.scanner={scan:async()=> 'clean'};
  await app.listen(0,'127.0.0.1');
  const stop=startRealtime(app.getHttpServer(),marketplace);
  let work,workerError;const maintenance=setInterval(()=>{if(work)return;work=marketplace.maintenance().catch(error=>{workerError=error;}).finally(()=>{work=undefined;});},250);
  try{
    const sdk=process.env.FLUTTER_ROOT||'/workspace/flutter-sdk';
    const child=spawn(sdk+'/bin/flutter',['test','--reporter','expanded','--dart-define=JOBA_TEST_API_URL='+await app.getUrl(),'test/api_integration_test.dart'],{
      cwd:resolve(__dirname,'../apps/mobile'),stdio:'inherit',env:{...process.env,PUB_CACHE:process.env.PUB_CACHE||'/workspace/.pub-cache',XDG_CONFIG_HOME:process.env.XDG_CONFIG_HOME||'/workspace/.config'}});
    process.exitCode=await new Promise((done,reject)=>{child.on('error',reject);child.on('exit',code=>done(code??1));});
    if(workerError)throw Error('Isolated maintenance failed');
  }finally{clearInterval(maintenance);await work;stop();await app.close();await marketplace.store.close();await rm(files,{recursive:true,force:true});}
}
main().catch(e=>{console.error(e.message);process.exitCode=1;});
