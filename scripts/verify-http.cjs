const assert=require('node:assert/strict');
const {readFileSync}=require('node:fs');
const {mkdtemp,rm}=require('node:fs/promises');
const {tmpdir}=require('node:os');
const {join,resolve}=require('node:path');
const {randomUUID}=require('node:crypto');
const sharp=require('sharp');
const {WebSocket}=require('ws');

async function main(){
  const variables=Object.fromEntries(readFileSync(resolve(__dirname,'../.local/postgres-test.env'),'utf8').trim().split('\n').map(l=>{const i=l.indexOf('=');return [l.slice(0,i),l.slice(i+1)];}));
  const url=new URL('postgresql://127.0.0.1:5439/'+variables.POSTGRES_DB);url.username=variables.POSTGRES_USER;url.password=variables.POSTGRES_PASSWORD;
  process.env.DATABASE_URL=url.toString();process.env.JOBA_UPLOAD_DIR=await mkdtemp(join(tmpdir(),'joba-http-'));
  const {NestFactory}=require('@nestjs/core'),{AppModule,getMarketplace}=require('../services/api/dist/app.module');
  const {startRealtime}=require('../services/api/dist/realtime'),express=require('express');
  const app=await NestFactory.create(AppModule,{logger:false,rawBody:true});app.use('/api/v1/uploads',express.raw({type:'application/octet-stream',limit:'10mb'}));
  await app.listen(0,'127.0.0.1');const api=await getMarketplace();const stop=startRealtime(app.getHttpServer(),api);const base=await app.getUrl();
  async function request(method,path,body,token,expected=200){
    const result=await fetch(base+'/api/v1'+path,{method,headers:{'Content-Type':'application/json',...(token?{Authorization:'Bearer '+token}:{}),...(method==='GET'?{}:{'Idempotency-Key':randomUUID()})},body:body===undefined?undefined:JSON.stringify(body)});assert.equal(result.status,expected,path);return result.json();
  }
  try {
    await request('GET','/me',undefined,undefined,401);
    const login=(await request('POST','/auth/login',{country:'KZ',phone:'+77000000401',password:'a long isolated validation password'})).data;
    const me=await request('GET','/me',undefined,login.access_token);assert.equal(me.data.id,login.user.id);assert.ok(me.meta.request_id);
    const cfg=await fetch(base+'/api/v1/me/monetization-config',{headers:{Authorization:'Bearer '+login.access_token}});assert.equal(cfg.status,200);const etag=cfg.headers.get('etag');assert.ok(etag);
    const cached=await fetch(base+'/api/v1/me/monetization-config',{headers:{Authorization:'Bearer '+login.access_token,'If-None-Match':etag}});assert.equal(cached.status,304);assert.ok(cached.headers.get('x-config-expires-at'));
    const image=await sharp({create:{width:2,height:2,channels:3,background:'#245BDB'}}).png().toBuffer();
    const upload=(await request('POST','/uploads/initiate',{purpose:'portfolio',mime:'image/png',size:image.length},login.access_token)).data;
    const content=await fetch(base+upload.upload_url,{method:'PUT',headers:{Authorization:'Bearer '+login.access_token,'Idempotency-Key':randomUUID(),'Content-Type':'application/octet-stream'},body:image});assert.equal(content.status,200);
    await request('POST',`/uploads/${upload.id}/finalize`,{},login.access_token,503);
    await request('POST','/billing/verify-purchase',{provider:'not-configured',transaction_reference:'invalid-proof'},login.access_token,503);
    const peer=(await request('POST','/auth/register',{country:'KZ',phone:'+77000000402',password:'another long isolated validation password',display_name:'HTTP peer fixture'})).data;
    const user=await api.store.get(peer.user.id);await api.store.put({...user,verification:'passed',roles:['customer','executor'],fixture:true});
    await api.store.put({id:randomUUID(),kind:'grant',owner:user.id,country:'KZ',version:1,created_at:new Date().toISOString(),valid_until:new Date(Date.now()+86400000).toISOString(),source:'isolated_fixture',capabilities:['search_full','send_offer']});
    const order=(await request('POST','/orders',{title:'HTTP lifecycle fixture',description:'Synthetic isolated data to verify actual transport and event authorization.',category_id:'1',city:'Алматы',budget_amount:10000},login.access_token)).data;
    const published=(await request('POST',`/orders/${order.id}/publish`,{expected_version:order.version},login.access_token)).data;
    const offer=(await request('POST',`/orders/${order.id}/offers`,{text:'HTTP offer fixture',amount:10000,acknowledged_revision:published.revision},peer.access_token)).data;
    const ws=new WebSocket(base.replace('http','ws')+'/api/v1/events/ws',['joba.v1','auth.'+peer.access_token]);
    await new Promise((resolve,reject)=>{ws.once('open',resolve);ws.once('error',reject);});
    const event=new Promise((resolve,reject)=>{const timer=setTimeout(()=>reject(Error('Event delivery timeout')),10000);ws.on('message',raw=>{const e=JSON.parse(raw.toString());if(e.type==='order.selected'){clearTimeout(timer);resolve(e);}});});
    await request('POST',`/orders/${order.id}/select-offer`,{expected_version:published.version,offer_id:offer.id,offer_version:offer.version},login.access_token);
    const delivered=await event;assert.equal(delivered.aggregate_id,order.id);assert.equal('phone' in delivered,false);
    await new Promise(resolve=>{ws.once('close',resolve);ws.close();});
    console.log('HTTP auth/envelopes, ETag/304, binary upload, closed scanner/payment gates, order selection and authorized WebSocket event: PASS');
  } finally {stop();await app.close();await api.store.close();await rm(process.env.JOBA_UPLOAD_DIR,{recursive:true,force:true});}
}
main().catch(e=>{console.error('HTTP validation failed:',e.code??e.message);process.exitCode=1;});
