const {test}=require('node:test'),assert=require('node:assert/strict'),{randomUUID}=require('node:crypto');
const {Marketplace}=require('../dist/marketplace'),{Store}=require('../dist/store'),{enabledCountries}=require('../dist/country-access'),{offerPolicy}=require('../dist/offer-terms');
test('all four enabled countries share a host while accounts, catalog and credentials remain country-scoped',async()=>{
 const previousRegion=process.env.JOBA_REGION,previousEnabled=process.env.JOBA_ENABLED_COUNTRIES;
 process.env.JOBA_REGION='KZ';process.env.JOBA_ENABLED_COUNTRIES='KZ,KG,RU,BY';
 let app;
 try{
  app=new Marketplace(new Store('memory://'));await app.initialize();
  const config=await app.handle('GET','/public/config');assert.deepEqual(config.countries.map(c=>c.code),['KZ','KG','RU','BY']);assert.ok(config.countries.every(c=>c.active&&c.registration_enabled&&!c.stop_new_business));
  const kg=config.countries.find(c=>c.code==='KG');assert.equal(kg.name,'Кыргызстан');assert.equal(kg.currency,'KGS');assert.deepEqual(kg.cities,['Бишкек','Ош']);assert.equal(kg.locales[0],'ru');
  const password='Isolated active countries password!';const sessions=[];
  for(const [country,phone] of [['KZ','+77000000851'],['KG','+996700123451'],['RU','+79991234567'],['BY','+375291234567']]){
   const u=await app.handle('POST','/auth/register',{country,phone,password},undefined,randomUUID(),{},country);sessions.push(u);assert.equal(u.user.country,country);
   const loggedIn=await app.handle('POST','/auth/login',{country,phone,password},undefined,randomUUID(),{},'login-'+country);assert.equal(loggedIn.user.country,country);
   const catalog=await app.handle('GET','/catalog/categories',{},'Bearer '+u.access_token);assert.ok(catalog.items.length>0);for(const category of catalog.items)assert.equal((await app.store.get(category.id)).country,country);
  }
  await assert.rejects(()=>app.handle('POST','/auth/login',{country:'KZ',phone:'+996700123451',password},undefined,randomUUID(),{},'wrong-country'),e=>e.getStatus()===401);
  await assert.rejects(()=>app.handle('POST','/auth/register',{country:'RS',phone:'+381601234567',password},undefined,randomUUID(),{},'obsolete-country'),e=>e.getStatus()===400);
  assert.equal(offerPolicy({country:'KG',expires_at:'2027-01-01T00:00:00Z'},72,new Date('2026-10-16T00:00:00Z')).time_zone,'Asia/Bishkek');
  delete process.env.JOBA_ENABLED_COUNTRIES;assert.deepEqual(enabledCountries(),['KZ']);
  const single=await app.handle('GET','/public/config');assert.equal(single.countries.find(c=>c.code==='KG').active,false);
  process.env.JOBA_ENABLED_COUNTRIES='KZ,KG,KG';assert.throws(()=>enabledCountries());
 }finally{await app?.store.close();if(previousRegion===undefined)delete process.env.JOBA_REGION;else process.env.JOBA_REGION=previousRegion;if(previousEnabled===undefined)delete process.env.JOBA_ENABLED_COUNTRIES;else process.env.JOBA_ENABLED_COUNTRIES=previousEnabled;}
});
