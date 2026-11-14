const {test}=require('node:test'),assert=require('node:assert/strict');
const {randomUUID}=require('node:crypto');
const {Marketplace}=require('../dist/marketplace'),{Store}=require('../dist/store');
test('all four active countries accept registration at password bounds, preserve secrets, and reject foreign country numbers',async()=>{
 const api=new Marketplace(new Store('memory://'));await api.initialize();
 try {
  const phones={KZ:'+77000000771',KG:'+996700123771',RU:'+79160000771',BY:'+375291000771'};
  for(const [country,phone] of Object.entries(phones)) {
   const request=(body,ip)=>api.handle('POST','/auth/register',body,undefined,randomUUID(),{},ip);
   const base={country,phone,locale:'ru'};
   for(const size of [5,129])await assert.rejects(()=>request({...base,password:'x'.repeat(size)},`${country}-bound-${size}`),e=>e.getStatus()===400&&e.getResponse().error.code==='VALIDATION_ERROR');
   await assert.rejects(()=>request({...base,phone:country==='KZ'?phones.KG:phones.KZ,password:'Valid isolated password'},`${country}-foreign`),e=>e.getStatus()===400&&e.getResponse().error.code==='VALIDATION_ERROR');
   const password=country==='KZ'?' '+'x'.repeat(4)+' ':'x'.repeat(6);
   const session=await request({...base,password},`${country}-valid`);
   assert.ok(session.access_token);assert.deepEqual(session.user.roles,['customer']);assert.equal(session.user.country,country);
   const profile=await api.handle('GET','/me',{},'Bearer '+session.access_token);
   assert.equal(profile.country,country);assert.equal(profile.phone,phone);assert.equal(profile.phone_status,'unverified');
   const login=await api.handle('POST','/auth/login',{country,phone,password},undefined,randomUUID(),{},`${country}-login`);
   assert.equal(login.user.id,session.user.id);
   if(country==='KZ')await assert.rejects(()=>api.handle('POST','/auth/login',{country,phone,password:password.trim()},undefined,randomUUID(),{},'trimmed-login'),e=>e.getStatus()===401);
   await assert.rejects(()=>request({...base,password},`${country}-duplicate`),e=>e.getStatus()===409&&e.getResponse().error.code==='REGISTRATION_UNAVAILABLE'&&!e.getResponse().error.message.includes(phone));
  }
 } finally {await api.store.close();}
});
