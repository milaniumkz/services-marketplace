const {test}=require('node:test'),assert=require('node:assert/strict');
require('reflect-metadata');
process.env.JOBA_DATA_DIR='memory://';
test('JSON selfie over default 100 KB reaches private recovery handler while oversized body is rejected',async()=>{
 const {NestFactory}=require('@nestjs/core'),{AppModule,getMarketplace}=require('../dist/app.module');
 const app=await NestFactory.create(AppModule,{logger:false,rawBody:true});app.useBodyParser('json',{limit:'8mb'});
 try{await app.listen(0,'127.0.0.1');const base=await app.getUrl();
 const result=await fetch(base+'/api/v1/auth/face-recovery/verify',{method:'POST',headers:{'Content-Type':'application/json'},body:JSON.stringify({id:'11111111-1111-4111-8111-111111111111',photo:'x'.repeat(200000)})});
 assert.equal(result.status,409);assert.equal((await result.json()).error.code,'FACE_RECOVERY_ERROR');
 const large=await fetch(base+'/api/v1/auth/face-recovery/verify',{method:'POST',headers:{'Content-Type':'application/json'},body:JSON.stringify({photo:'x'.repeat(8*1024*1024+1)})});assert.equal(large.status,413);
 }finally{await app.close();await (await getMarketplace()).store.close();}
});
