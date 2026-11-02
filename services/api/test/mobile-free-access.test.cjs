const {test}=require('node:test');
const assert=require('node:assert/strict');
const {randomUUID}=require('node:crypto');
const {Marketplace}=require('../dist/marketplace');
const {Store}=require('../dist/store');

test('free mobile pricing preserves identity, account restrictions, web pricing and staff authorization',async()=>{
 const previous=process.env.JOBA_MOBILE_FREE_ACCESS;
 process.env.JOBA_MOBILE_FREE_ACCESS='1';
 const api=new Marketplace(new Store('memory://'));await api.initialize();
 try {
  const session=await api.handle('POST','/auth/register',{country:'KZ',phone:'+77000000990',password:'Isolated mobile channel test!'});
  const call=(path,channel='web')=>api.handle('GET',path,{},'Bearer '+session.access_token,undefined,{},'local',channel);
  await assert.rejects(()=>call('/contractors','mobile-free-v1'),e=>e.getResponse().error.code==='VERIFICATION_REQUIRED');
  const user=await api.store.get(session.user.id);await api.store.put({...user,verification:'passed'});
  const results=await Promise.allSettled([call('/contractors','mobile-free-v1'),call('/contractors')]);
  assert.equal(results[0].status,'fulfilled');assert.equal(results[1].status,'rejected');
  assert.equal(results[1].reason.getResponse().error.code,'ENTITLEMENT_REQUIRED');
  assert.equal((await api.store.all('grant','KZ')).filter(g=>g.owner===user.id).length,0);
  await assert.rejects(()=>call('/admin/users','mobile-free-v1'),e=>e.getStatus()===403);
  process.env.JOBA_MOBILE_FREE_ACCESS='0';
  await assert.rejects(()=>call('/contractors','mobile-free-v1'),e=>e.getResponse().error.code==='ENTITLEMENT_REQUIRED');
  process.env.JOBA_MOBILE_FREE_ACCESS='1';
  await api.store.put({...await api.store.get(user.id),status:'restricted'});
  await assert.rejects(()=>call('/contractors','mobile-free-v1'),e=>e.getStatus()===403);
 } finally {
  await api.store.close();
  if(previous===undefined)delete process.env.JOBA_MOBILE_FREE_ACCESS;else process.env.JOBA_MOBILE_FREE_ACCESS=previous;
 }
});
