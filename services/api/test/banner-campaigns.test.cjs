const {test}=require('node:test');const assert=require('node:assert/strict');const {randomUUID,randomBytes}=require('node:crypto');
const {Marketplace}=require('../dist/marketplace');const {Store}=require('../dist/store');const {totp}=require('../dist/totp');const {bannerPayload}=require('../dist/banner-campaigns');
const password='Isolated banner workflow password!';
const payload=()=>({time_zone:'Asia/Almaty',start_local:'2027-01-01T09:00',end_local:'2027-01-10T18:00',placement:'catalog.inline.end',destination:'catalog',headline:'Новая кампания',caption:'Проверяемая подпись',budget_minor:100000,daily_limit:100,screen_interval:3});
const call=(a,u,m,p,b={})=>a.handle(m,p,b,'Bearer '+u.access_token,randomUUID());
const code=c=>e=>e.getResponse().error.code===c;
test('banner payload rejects unsafe destinations, fractional money, invalid local dates and ambiguous DST',()=>{
 assert.equal(bannerPayload(payload(),'KZ').valid_from,'2027-01-01T04:00:00Z');
 for(const patch of [{destination:'https://external.invalid'},{budget_minor:1.1},{daily_limit:0},{placement:'chat.inline'},{end_local:'2026-01-01T00:00'},{time_zone:'UTC'},{start_local:'2027-02-30T09:00'}])assert.throws(()=>bannerPayload({...payload(),...patch},'KZ'));
 assert.throws(()=>bannerPayload({...payload(),time_zone:'Europe/Belgrade',start_local:'2027-10-31T02:30'},'RS'));
});
test('banner drafts are separate from subscription promos, versioned, country-scoped, reviewed independently and never fake provider activation',async()=>{
 const a=new Marketplace(new Store('memory://'));await a.initialize();
 try{
  const staff=[];for(const [i,country,permissions] of [[0,'KZ',['campaign']],[1,'KZ',['campaign']],[2,'RS',['campaign']],[3,'KZ',[]]]){
   const phone=country==='RS'?'+381601234567':'+770000008'+(10+i),u=await a.handle('POST','/auth/register',{country,phone,password},undefined,randomUUID(),{},phone),secret=randomBytes(20).toString('hex');
   await a.store.put({...await a.store.get(u.user.id),staff_permissions:permissions,totp_secret:secret});staff.push(permissions.length?await a.handle('POST','/auth/staff-login',{country,phone,password,mfa_code:totp(secret)},undefined,randomUUID(),{},phone):u);
  }
  const body={title:'Баннер каталога',payload:payload(),reason:'Проверка реального черновика'};
  await assert.rejects(()=>call(a,staff[3],'POST','/admin/banner-campaigns',body),e=>e.getStatus()===403);
  let r=await call(a,staff[0],'POST','/admin/banner-campaigns',body);assert.equal(r.kind,'banner_campaign');assert.equal(r.status,'draft');
  assert.equal((await call(a,staff[0],'GET','/admin/banner-campaigns',{})).items.length,1);
  assert.equal((await call(a,staff[0],'GET','/admin/promotions',{}).catch(()=>({items:[]}))).items.length,0);
  await assert.rejects(()=>call(a,staff[2],'GET','/admin/banner-campaigns/'+r.id),e=>e.getStatus()===404);
  await assert.rejects(()=>call(a,staff[1],'PATCH','/admin/banner-campaigns/'+r.id,{...body,expected_version:1}),code('STATE_CONFLICT'));
  const command=action=>'/admin/banner-campaigns/'+r.id+'/'+action;
  await assert.rejects(()=>call(a,staff[0],'POST',command('submit'),{expected_version:1,reason:body.reason}),code('UNSAFE_UPLOAD'));
  const asset={id:randomUUID(),kind:'upload',owner:staff[0].user.id,country:'KZ',version:1,created_at:new Date().toISOString(),purpose:'banner',status:'processing',mime:'image/jpeg'};await a.store.put(asset);
  r=await call(a,staff[0],'PATCH','/admin/banner-campaigns/'+r.id,{...body,payload:{...payload(),creative_id:asset.id},expected_version:1});assert.equal(r.version,2);
  await assert.rejects(()=>call(a,staff[0],'PATCH','/admin/banner-campaigns/'+r.id,{...body,expected_version:1}),code('STATE_CONFLICT'));
  await assert.rejects(()=>call(a,staff[0],'POST',command('submit'),{expected_version:2,reason:body.reason}),code('UNSAFE_UPLOAD'));
  await a.store.put({...asset,status:'clean',purpose:'avatar'});await assert.rejects(()=>call(a,staff[0],'POST',command('submit'),{expected_version:2,reason:body.reason}),code('UNSAFE_UPLOAD'));
  await a.store.put({...asset,status:'clean'});
  r=await call(a,staff[0],'POST',command('submit'),{expected_version:r.version,reason:body.reason});assert.equal(r.status,'pending_review');
  await assert.rejects(()=>call(a,staff[0],'POST',command('approve'),{expected_version:r.version,reason:body.reason}),code('INDEPENDENT_APPROVAL_REQUIRED'));
  r=await call(a,staff[1],'POST',command('approve'),{expected_version:r.version,reason:body.reason});assert.equal(r.status,'approved');assert.equal(r.approved_by,staff[1].user.id);
  await assert.rejects(()=>call(a,staff[0],'POST',command('publish'),{expected_version:r.version,reason:body.reason}),code('BANNER_PROVIDER_UNAVAILABLE'));
  assert.equal((await a.store.get(r.id)).status,'approved');
  r=await call(a,staff[1],'POST',command('stop'),{expected_version:r.version,reason:body.reason});assert.equal(r.status,'stopped');assert.deepEqual(r.history.map(h=>h.action),['created','updated','submit','approve','stop']);
  assert.equal((await call(a,staff[0],'GET','/admin/banner-campaigns',{},)).items.length,1);
  const upload=await call(a,staff[0],'POST','/uploads/initiate',{purpose:'banner',mime:'image/jpeg',size:100});assert.equal(upload.purpose,'banner');
  await assert.rejects(()=>call(a,staff[3],'POST','/uploads/initiate',{purpose:'banner',mime:'image/png',size:100}),e=>e.getStatus()===403);
 }finally{await a.store.close();}
});
test('banner images pass binary processing and private staff access; small or infected images never become usable',async()=>{
 const {mkdtemp,rm}=require('node:fs/promises'),{tmpdir}=require('node:os'),{join}=require('node:path'),sharp=require('sharp'),{PrivateFiles}=require('../dist/private-files'),{Providers}=require('../dist/providers');
 const dir=await mkdtemp(join(tmpdir(),'joba-banner-assets-')),providers=new Providers();providers.scanner={scan:async()=> 'clean'}; // Isolated image-policy adapter; no claim about production antivirus.
 const a=new Marketplace(new Store('memory://'),providers,new PrivateFiles(dir));await a.initialize();
 try{
  const u=await a.handle('POST','/auth/register',{country:'KZ',phone:'+77000000819',password},undefined,randomUUID()),secret=randomBytes(20).toString('hex');
  await a.store.put({...await a.store.get(u.user.id),staff_permissions:['campaign'],totp_secret:secret});
  const staff=await a.handle('POST','/auth/staff-login',{country:'KZ',phone:'+77000000819',password,mfa_code:totp(secret)},undefined,randomUUID());
  const upload=async(width,height)=>{const bytes=await sharp({create:{width,height,channels:3,background:'#245BDB'}}).png().toBuffer(),r=await call(a,staff,'POST','/uploads/initiate',{purpose:'banner',mime:'image/png',size:bytes.length});await call(a,staff,'PUT','/uploads/'+r.id+'/content',bytes);return r;};
  let r=await upload(640,160);r=await call(a,staff,'POST','/uploads/'+r.id+'/finalize');assert.equal(r.status,'clean');
  assert.equal((await sharp((await call(a,staff,'GET','/uploads/'+r.id+'/download')).download_buffer).metadata()).width,640);
  await assert.rejects(()=>call(a,u,'GET','/uploads/'+r.id+'/download'),e=>e.getStatus()===403);
  const small=await upload(10,10);await assert.rejects(()=>call(a,staff,'POST','/uploads/'+small.id+'/finalize'),e=>e.getResponse().error.code==='POLICY_REJECTED');assert.equal((await a.store.get(small.id)).status,'rejected');
  providers.scanner={scan:async()=> 'infected'};const infected=await upload(640,160);assert.equal((await call(a,staff,'POST','/uploads/'+infected.id+'/finalize')).status,'infected');assert.equal((await a.store.get(infected.id)).status,'infected');
  await assert.rejects(()=>call(a,staff,'GET','/uploads/'+infected.id+'/download'),e=>e.getStatus()===404);
 }finally{await a.store.close();await rm(dir,{recursive:true,force:true});}
});
