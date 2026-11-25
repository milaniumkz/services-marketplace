const {test}=require('node:test'),assert=require('node:assert/strict'),{randomUUID}=require('node:crypto');
const {Marketplace}=require('../dist/marketplace'),{Store}=require('../dist/store');
const call=(a,u,method,path,body={},q={})=>a.handle(method,path,body,'Bearer '+u.access_token,randomUUID(),q);
const reason='Проверка жизненного цикла реферальной кампании';
const payload={threshold:2,budget_units:10,reward_duration_seconds:30*86400,qualifying_event:'registered',reward_kind:'subscription_days',reward_plan:'current'};
async function setup(){const a=new Marketplace(new Store('memory://'));await a.initialize();let counter=0;
 const account=async(staff=false)=>{const phone='+77000000'+String(900+counter++).padStart(3,'0'),password='Isolated lifecycle password!';let u=await a.handle('POST','/auth/register',{country:'KZ',phone,password},undefined,randomUUID());if(staff){await a.store.put({...await a.store.get(u.user.id),staff_permissions:['platform_owner']});u=await a.handle('POST','/auth/staff-login',{country:'KZ',phone,password},undefined,randomUUID());}return u;};return {a,account,owner:await account(true)};}
test('owner launches own referral draft; codes qualify once; replacing, stopping, archiving and restoring preserve history',async()=>{
 const {a,account,owner}=await setup();try{
 let campaign=await call(a,owner,'POST','/admin/referral-campaigns',{title:'Изолированная кампания',payload,reason});const path='/admin/referral-campaigns/'+campaign.id;
 const inviter=await account(),one=await account(),two=await account(),three=await account(),ref=await call(a,inviter,'GET','/me/referrals');
 await assert.rejects(()=>call(a,one,'POST','/referrals/attribute',{code:ref.code}),e=>e.getResponse().error.code==='CAMPAIGN_UNAVAILABLE');
 campaign=await call(a,owner,'POST',path+'/publish',{expected_version:campaign.version,reason});assert.equal(campaign.status,'effective');assert.equal(campaign.published_by,owner.user.id);
 await call(a,one,'POST','/referrals/attribute',{code:ref.code});await call(a,two,'POST','/referrals/attribute',{code:ref.code});
 const before=(await call(a,inviter,'GET','/me/referrals')).rewards;assert.equal(before.length,1);
 await assert.rejects(()=>call(a,two,'POST','/referrals/attribute',{code:ref.code}),e=>e.getResponse().error.code==='ATTRIBUTION_ALREADY_SET');
 await assert.rejects(()=>call(a,owner,'POST',path+'/cancel',{expected_version:campaign.version,reason}),e=>e.getResponse().error.code==='STATE_CONFLICT');
 await assert.rejects(()=>call(a,owner,'POST',path+'/stop',{expected_version:1,reason}),e=>e.getResponse().error.code==='STATE_CONFLICT');
 campaign=await call(a,owner,'POST',path+'/stop',{expected_version:campaign.version,reason});assert.equal(campaign.status,'stopped');
 await assert.rejects(()=>call(a,three,'POST','/referrals/attribute',{code:ref.code}),e=>e.getResponse().error.code==='CAMPAIGN_UNAVAILABLE');
 campaign=await call(a,owner,'POST',path+'/cancel',{expected_version:campaign.version,reason});assert.equal(campaign.status,'archived');
 assert.equal((await call(a,owner,'GET','/admin/referral-campaigns')).items.length,0);
 assert.equal((await call(a,owner,'GET','/admin/referral-campaigns',{}, {status:'archived'})).items[0].id,campaign.id);
 const history=await call(a,owner,'GET',path);assert.equal(history.metrics.attributions,2);assert.equal(history.metrics.issued,1);
 assert.deepEqual((await call(a,inviter,'GET','/me/referrals')).rewards,before);
 await assert.rejects(()=>call(a,owner,'POST',path+'/publish',{expected_version:campaign.version,reason}),e=>e.getResponse().error.code==='STATE_CONFLICT');
 const restored=await call(a,owner,'POST',path+'/rollback',{expected_version:campaign.version,reason});assert.equal(restored.status,'draft');assert.deepEqual(restored.payload,payloadWithPolicy(payload));
 const newer=await call(a,owner,'POST','/admin/referral-campaigns/'+restored.id+'/publish',{expected_version:restored.version,reason});assert.equal(newer.status,'effective');
 let replacement=await call(a,owner,'POST','/admin/referral-campaigns',{title:'Замена условий',payload:{...payload,threshold:3},reason});replacement=await call(a,owner,'POST','/admin/referral-campaigns/'+replacement.id+'/publish',{expected_version:replacement.version,reason});
 assert.equal((await a.store.get(newer.id)).status,'superseded');assert.equal((await a.store.all('referral_campaign','KZ')).filter(x=>x.status==='effective').length,1);
 await call(a,three,'POST','/referrals/attribute',{code:ref.code});assert.equal((await a.store.all('referral_attribution','KZ')).find(x=>x.owner===three.user.id).campaign_id,replacement.id);
 }finally{await a.store.close();}
});
function payloadWithPolicy(p){return {...p,capabilities:[],multilevel:false,cash_payout:false};}
test('draft archive cannot be published and accepted pending invitations still qualify after stop/archive',async()=>{
 const {a,account,owner}=await setup();try{
 const draft=await call(a,owner,'POST','/admin/referral-campaigns',{title:'Ненужный черновик',payload,reason});
 const archived=await call(a,owner,'POST','/admin/referral-campaigns/'+draft.id+'/cancel',{expected_version:draft.version,reason});assert.equal(archived.status,'archived');
 let campaign=await call(a,owner,'POST','/admin/referral-campaigns',{title:'Обещанные бонусы',payload:{...payload,threshold:1,qualifying_event:'completed_order'},reason});const path='/admin/referral-campaigns/'+campaign.id;
 campaign=await call(a,owner,'POST',path+'/publish',{expected_version:campaign.version,reason});
 const inviter=await account(),invitee=await account(),ref=await call(a,inviter,'GET','/me/referrals');await call(a,invitee,'POST','/referrals/attribute',{code:ref.code});
 campaign=await call(a,owner,'POST',path+'/stop',{expected_version:campaign.version,reason});await call(a,owner,'POST',path+'/cancel',{expected_version:campaign.version,reason});
 await a.growth.qualify(invitee.user.id,'KZ','completed_order',randomUUID());await a.growth.qualify(invitee.user.id,'KZ','completed_order',randomUUID());
 assert.equal((await a.store.all('referral_reward','KZ')).length,1);
 }finally{await a.store.close();}
});
