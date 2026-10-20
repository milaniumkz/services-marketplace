const {test}=require('node:test');
const assert=require('node:assert/strict');
const {randomUUID}=require('node:crypto');
const {Store}=require('../dist/store');
const {Providers}=require('../dist/providers');
const {Configuration}=require('../dist/configuration');
test('banner switches preserve the subscription and cannot enable an unconnected or unapproved placement',async()=>{
 const store=new Store('memory://');await store.initialize();const providers=new Providers(),configuration=new Configuration(store,providers);
 const record={id:randomUUID(),kind:'monetization_config',owner:'isolated-author',country:'KZ',version:1,created_at:new Date().toISOString(),status:'draft',payload:{subscription_enabled:true,banner_ads_enabled:false,rewarded_access_enabled:false}};
 const reject=(fn,code)=>assert.rejects(fn,error=>error.getResponse().error.code===code);
 try{
  assert.equal((await configuration.validate(record)).valid,true);
  const enabled={...record,payload:{...record.payload,banner_ads_enabled:true,banner_provider:'isolated-banner',banner_placements:['catalog.inline']}};
  await reject(()=>configuration.validate(enabled),'BANNER_PROVIDER_UNAVAILABLE');
  providers.banners.set('isolated-banner',{name:'isolated-banner',validatePlacement:async()=>({allowed:false})});
  await reject(()=>configuration.validate(enabled),'BANNER_PLACEMENT_UNAPPROVED');
  providers.banners.set('isolated-banner',{name:'isolated-banner',validatePlacement:async(id,country)=>({allowed:id==='catalog.inline'&&country==='KZ'})});
  assert.equal((await configuration.validate(enabled)).valid,true);
  await reject(()=>configuration.validate({...enabled,payload:{...enabled.payload,subscription_enabled:false}}),'SUBSCRIPTION_REQUIRED');
  await reject(()=>configuration.validate({...enabled,payload:{...enabled.payload,rewarded_access_enabled:true}}),'REWARD_POLICY_UNAPPROVED');
 }finally{await store.close();}
});
