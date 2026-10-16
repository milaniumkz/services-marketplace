const {test}=require('node:test'),assert=require('node:assert/strict'),{randomUUID,randomBytes}=require('node:crypto');
const {Marketplace}=require('../dist/marketplace'),{Store}=require('../dist/store'),{totp}=require('../dist/totp');
const password='Isolated dictionary editor password!';
const call=(a,u,method,path,body={})=>a.handle(method,path,body,'Bearer '+u.access_token,randomUUID());
test('dictionary drafts validate exceptions and surfaces, protect versions and apply only published regional rules to new content',async()=>{
 const a=new Marketplace(new Store('memory://'));await a.initialize();
 try{
  const staff=[];for(const phone of ['+77000000891','+77000000892']){const u=await a.handle('POST','/auth/register',{country:'KZ',phone,password},undefined,randomUUID()),secret=randomBytes(20).toString('hex');await a.store.put({...await a.store.get(u.user.id),staff_permissions:['moderator_manager'],totp_secret:secret});staff.push(await a.handle('POST','/auth/staff-login',{country:'KZ',phone,password,mfa_code:totp(secret)},undefined,randomUUID()));}
  const member=await a.handle('POST','/auth/register',{country:'KZ',phone:'+77000000893',password},undefined,randomUUID());
  const title='Словарь контрольных слов',reason='Проверка правил нового словаря модерации',rule={id:'one',type:'exact_word',value:'контрольмаркер',surfaces:['order']},payload={rules:[rule],exceptions:['без контрольмаркер']};
  for(const invalid of [{rules:[null]},{rules:[{...rule,value:'   '}]},{...payload,exceptions:'oops'},{...payload,exceptions:[null]},{rules:[{...rule,surfaces:['unknown']}]},{rules:[{...rule,surfaces:[]}]},{rules:[rule,rule]}])await assert.rejects(()=>call(a,staff[0],'POST','/admin/moderation-dictionaries',{title,reason,payload:invalid}),e=>e.getStatus()===400);
  let d=await call(a,staff[0],'POST','/admin/moderation-dictionaries',{title,reason,payload:{...payload,ignored:true}});const path='/admin/moderation-dictionaries/'+d.id;assert.equal(d.payload.ignored,undefined);
  await assert.rejects(()=>call(a,member,'GET',path),e=>e.getStatus()===403);
  await assert.rejects(()=>call(a,staff[1],'PATCH',path,{title,reason,payload,expected_version:1}),e=>e.getStatus()===409);
  d=await call(a,staff[0],'PATCH',path,{title,reason,payload,expected_version:1});assert.equal(d.version,2);
  for(const action of ['validate','preview','publish'])await assert.rejects(()=>call(a,staff[1],'POST',path+'/'+action,{reason,expected_version:1}),e=>e.getStatus()===409);
  const orderData={title:'Заказ контрольмаркер',description:'Достаточно длинное описание нового заказа для проверки.',category_id:'1',city:'Алматы',budget_amount:null};
  const before=await call(a,member,'POST','/orders',orderData);assert.equal(before.status,'draft');
  const dry=await call(a,staff[0],'POST',path+'/dry-run',{text:'КОНТРОЛЬМАРКЕР!',surface:'order',reason,expected_version:2});assert.equal(dry.matched,true);assert.equal((await a.store.all('case','KZ')).length,0);
  for(const [text,surface] of [['без контрольмаркер','order'],['контрольмаркер','message'],['антиконтрольмаркер','order']])assert.equal((await call(a,staff[0],'POST',path+'/dry-run',{text,surface,reason,expected_version:2})).matched,false);
  await assert.rejects(()=>call(a,staff[0],'POST',path+'/publish',{reason,expected_version:2}),e=>e.getStatus()===403);
  d=await call(a,staff[1],'POST',path+'/publish',{reason,expected_version:2});assert.equal(d.status,'published');
  assert.equal((await a.store.get(before.id)).status,'draft');
  await assert.rejects(()=>call(a,staff[1],'POST',path+'/publish',{reason,expected_version:3}),e=>e.getStatus()===409);
  await assert.rejects(()=>call(a,staff[0],'PATCH',path,{title,reason,payload,expected_version:3}),e=>e.getStatus()===409);
  const excluded=await call(a,member,'POST','/orders',{...orderData,title:'Заказ без контрольмаркер'});assert.equal(excluded.status,'draft');
  const hit=await call(a,member,'POST','/orders',orderData);assert.equal(hit.status,'pending_moderation');assert.equal((await a.store.all('case','KZ')).length,1);
  await call(a,staff[0],'POST',path+'/stop',{reason,expected_version:3});assert.equal((await call(a,staff[0],'GET',path)).status,'stopped');
  await a.store.put({...await a.store.get(member.user.id),status:'active',version:2});
  const after=await call(a,member,'POST','/orders',orderData);assert.equal(after.status,'draft');assert.equal((await a.store.get(hit.id)).status,'pending_moderation');
 }finally{await a.store.close();}
});
