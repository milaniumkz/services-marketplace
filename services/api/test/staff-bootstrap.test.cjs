const {test}=require('node:test');
const assert=require('node:assert/strict');
const {mkdtemp,rm}=require('node:fs/promises');
const {join}=require('node:path');
const {tmpdir}=require('node:os');
const {randomUUID}=require('node:crypto');
const {Marketplace}=require('../dist/marketplace');
const {Store}=require('../dist/store');
const {PrivateFiles}=require('../dist/private-files');
const {Providers}=require('../dist/providers');
const {bootstrapStaff}=require('../dist/staff-bootstrap');
const {totp}=require('../dist/totp');
function decodeBase32(source){let bits=0,value=0;const bytes=[];for(const symbol of source){value=(value<<5)|'ABCDEFGHIJKLMNOPQRSTUVWXYZ234567'.indexOf(symbol);bits+=5;if(bits>=8){bits-=8;bytes.push((value>>>bits)&255);}}return Buffer.from(bytes);}
test('offline staff enrollment stores sealed MFA and preserves separate business identities',async()=>{
 const dir=await mkdtemp(join(tmpdir(),'joba-staff-bootstrap-'));const api=new Marketplace(new Store('memory://'),new Providers(),new PrivateFiles(dir));await api.initialize();
 try{
  const input={country:'KZ',identifier:'staff-isolated-test',display_name:'Проверка сотрудника',password:'Isolated staff bootstrap password!',permissions:['administrator','auditor'],reason:'Изолированная проверка регистрации сотрудника'};let enrollment;
  const result=await bootstrapStaff(api.store,api.files,input,async data=>{enrollment=data;});
  const user=await api.store.get(result.id);assert.ok(user.totp_secret_sealed.startsWith('v1.'));assert.equal(user.totp_secret,undefined);assert.deepEqual(user.roles,[]);
  const uri=new URL(enrollment.otpauth_uri),secret=decodeBase32(uri.searchParams.get('secret')).toString('hex');
  assert.equal(await api.files.unsealSecret(user.totp_secret_sealed,user.id),secret);
  await assert.rejects(()=>api.files.unsealSecret(user.totp_secret_sealed,randomUUID()));
  const body={country:'KZ',phone:input.identifier,password:input.password};
  await assert.rejects(()=>api.handle('POST','/auth/login',body,undefined,undefined,{},'staff-normal-login'),error=>error.getStatus()===401);
  await assert.rejects(()=>api.handle('POST','/auth/staff-login',{...body,mfa_code:'invalid'},undefined,undefined,{},'staff-bad-mfa'),error=>error.getStatus()===401);
  const session=await api.handle('POST','/auth/staff-login',{...body,mfa_code:totp(secret)},undefined,undefined,{},'staff-correct-mfa');
  const auth='Bearer '+session.access_token;
  assert.equal((await api.handle('GET','/admin/dashboard',{},auth)).users,0);
  assert.equal((await api.handle('GET','/admin/users',{},auth)).items.length,0);
  await assert.rejects(()=>api.handle('POST','/orders',{title:'Нельзя создавать рабочий заказ'},auth,randomUUID()),error=>error.getStatus()===403);
  await assert.rejects(()=>bootstrapStaff(api.store,api.files,input,async()=>{}),/already exists/);
  assert.equal((await api.store.all('audit')).filter(record=>record.action==='staff.bootstrap').length,1);
  assert.equal(JSON.stringify(await api.handle('GET','/me',{},auth)).includes('totp_secret'),false);
 }finally{await api.store.close();await rm(dir,{recursive:true,force:true});}
});
