const {test}=require('node:test'),assert=require('node:assert/strict'),{readFileSync}=require('node:fs'),{randomUUID,randomBytes,createHash}=require('node:crypto');
const {Marketplace}=require('../dist/marketplace'),{Store}=require('../dist/store'),{totp}=require('../dist/totp');
const {publishCommerceLegal}=require('../../../scripts/publish-kz-commerce-legal.cjs');
test('commerce legal publication is regional, idempotent, audited and admin revisions override only after independent publication',async()=>{
 const api=new Marketplace(new Store('memory://'));await api.initialize();
 try{
  const docs=['payments','refunds','public_offer','contacts'].map(type=>({type,locale:'ru',content:readFileSync('docs/legal/kz/'+type+'.ru.txt','utf8')}));
  await assert.rejects(()=>publishCommerceLegal(api.store,docs.slice(1)),/Expected four/);
  assert.equal((await publishCommerceLegal(api.store,docs)).filter(x=>x.status==='published').length,4);
  const get=country=>api.handle('GET','/legal/documents',{},undefined,undefined,{country,locale:'ru'});
  const original=(await get('KZ')).items;assert.equal(original.length,4);assert.equal((await get('KG')).items.length,0);
  for(const d of original)assert.equal(d.hash,createHash('sha256').update(d.content).digest('hex'));
  const staff=[];for(const phone of ['+77000000871','+77000000872']){const u=await api.handle('POST','/auth/register',{country:'KZ',phone,password:'Commerce legal test password'},undefined,randomUUID()),secret=randomBytes(20).toString('hex');await api.store.put({...await api.store.get(u.user.id),staff_permissions:['administrator'],totp_secret:secret});staff.push(await api.handle('POST','/auth/staff-login',{country:'KZ',phone,password:'Commerce legal test password',mfa_code:totp(secret)},undefined,randomUUID()));}
  const call=(u,path,body)=>api.handle('POST',path,body,'Bearer '+u.access_token,randomUUID());
  const content='Изменённые реквизиты оператора и условия оплаты после проверки администратором.';
  const draft=await call(staff[0],'/admin/legal/documents',{type:'payments',locale:'ru',content,reason:'Уточнение условий оплаты и реквизитов оператора'});
  assert.notEqual((await get('KZ')).items.find(x=>x.type==='payments').content,content);
  await assert.rejects(()=>call(staff[0],'/admin/legal/documents/'+draft.id+'/publish',{expected_version:1,reason:'Попытка самостоятельного утверждения'}),e=>e.getStatus()===403);
  await call(staff[1],'/admin/legal/documents/'+draft.id+'/publish',{expected_version:1,reason:'Независимое утверждение новой редакции'});
  assert.equal((await get('KZ')).items.find(x=>x.type==='payments').content,content);
  assert.equal((await publishCommerceLegal(api.store,docs)).every(x=>x.status==='preserved_existing'),true);
  assert.equal((await get('KZ')).items.find(x=>x.type==='payments').content,content);
  assert.equal((await api.store.all('audit','KZ')).filter(x=>x.action==='legal.commerce_initial_publication').length,4);
 }finally{await api.store.close();}
});

test('commerce import preserves an existing legacy payment document',async()=>{
 const store=new Store('memory://');await store.initialize();
 try{
  const docs=['payments','refunds','public_offer','contacts'].map(type=>({type,locale:'ru',content:readFileSync('docs/legal/kz/'+type+'.ru.txt','utf8')}));
  const id=randomUUID();await store.put({id,kind:'legal_document',country:'KZ',owner:'administrator',version:2,status:'published',type:'subscriptions',locale:'ru',content:'Previously approved payment conditions',created_at:new Date().toISOString()});
  const result=await publishCommerceLegal(store,docs);assert.equal(result.find(x=>x.type==='payments').status,'preserved_existing');assert.equal((await store.get(id)).content,'Previously approved payment conditions');assert.equal((await store.all('legal_document','KZ')).filter(x=>x.type==='payments').length,0);
 }finally{await store.close();}
});
