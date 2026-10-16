const {test}=require('node:test'),assert=require('node:assert/strict'),{randomUUID,randomBytes}=require('node:crypto');
const {Marketplace}=require('../dist/marketplace'),{Store}=require('../dist/store'),{Providers}=require('../dist/providers'),{totp}=require('../dist/totp');
const password='Isolated financial journal password!';
const call=(a,u,method,path,body={},q={})=>a.handle(method,path,body,'Bearer '+u.access_token,randomUUID(),q);
test('payment identity cannot cross owners, chains or products; immutable journal separates cash from status and refund requests require ownership',async()=>{
 const providers=new Providers(),a=new Marketplace(new Store('memory://'),providers);await a.initialize();
 try{
  const accounts=[];for(const phone of ['+77000000921','+77000000922','+77000000923'])accounts.push(await a.handle('POST','/auth/register',{country:'KZ',phone,password},undefined,randomUUID()));
  const [member,other,staffAccount]=accounts;for(const u of [member,other])await a.store.put({...await a.store.get(u.user.id),roles:['customer','executor'],active_role:'executor'});
  const secret=randomBytes(20).toString('hex');await a.store.put({...await a.store.get(staffAccount.user.id),staff_permissions:['billing'],totp_secret:secret});const staff=await a.handle('POST','/auth/staff-login',{country:'KZ',phone:staffAccount.user.phone,password,mfa_code:totp(secret)},undefined,randomUUID());
  let proof={provider:'isolated',transaction_id:'one',original_transaction_id:'chain',user_id:member.user.id,country:'KZ',product_id:'subscription',environment:'sandbox',amount_minor:12345,currency:'KZT',valid_until:new Date(Date.now()+86400000).toISOString(),state:'active',revision:1};
  providers.billing.set('isolated',{name:'isolated',verifyPurchase:async()=>proof});
  await a.store.put({id:randomUUID(),kind:'price_version',owner:'system',country:'KZ',version:1,created_at:new Date().toISOString(),status:'effective',payload:{provider:'isolated',product_id:'subscription',product_type:'subscription',amount_minor:12345,currency:'KZT'}});
  const verify=u=>call(a,u,'POST','/billing/verify-purchase',{provider:'isolated',transaction_reference:'verified-reference'});
  const first=await verify(member),original={...proof};await verify(member);assert.equal((await a.store.all('payment_transaction','KZ')).length,1);
  for(const altered of [{user_id:other.user.id,original_transaction_id:'other-chain'},{original_transaction_id:'other-chain'},{product_id:'other-product'},{amount_minor:999}]){proof={...original,...altered,revision:2};await assert.rejects(()=>verify(altered.user_id?other:member),e=>e.getResponse().error.code==='TRANSACTION_ALREADY_USED');}
  proof={...original,state:'grace',revision:2};await verify(member);
  proof={...original,transaction_id:'two',revision:3};await verify(member);
  proof={...proof,state:'revoked',revision:4};await verify(member);
  const rows=await a.store.all('payment_transaction','KZ');assert.equal(rows.length,4);assert.equal(rows.filter(x=>x.operation==='purchase').length,1);assert.equal(rows.filter(x=>x.operation==='renewal').length,1);assert.equal(rows.reduce((sum,x)=>sum+x.cash_amount_minor,0),24690);assert.ok(rows.every(x=>x.source_id===first.subscription.id));assert.equal(rows.find(x=>x.state==='revoked').cash_amount_minor,0);
  const grant=(await a.store.all('grant','KZ'))[0];assert.equal(grant.source_id,first.subscription.id);assert.ok(Date.parse(grant.valid_until)<=Date.now());
  await assert.rejects(()=>a.store.put({...rows[0],amount_minor:1}),/append-only/);await assert.rejects(()=>a.store.db.query('DELETE FROM records WHERE id=$1',[rows[0].id]),/append-only/);
  await assert.rejects(()=>call(a,other,'POST','/billing/refund-requests',{subscription_id:first.subscription.id,reason:'Чужая подписка не должна приниматься'}),e=>e.getStatus()===404);
  const request=await call(a,member,'POST','/billing/refund-requests',{subscription_id:first.subscription.id,reason:'Прошу проверить возврат моей подписки'});assert.equal(request.status,'requested');assert.equal((await a.store.all('payment_transaction','KZ')).length,4);
  await assert.rejects(()=>call(a,member,'GET','/admin/payment-transactions'),e=>e.getStatus()===403);
  const foreign={...rows[0],id:randomUUID(),country:'KG'};await a.store.put(foreign);
  const legacy={...rows[0],id:randomUUID(),operation:undefined,cash_amount_minor:undefined,raw_receipt:'private-provider-evidence'};await a.store.put(legacy);
  const seen=[];let cursor;do{const page=await call(a,staff,'GET','/admin/payment-transactions',{}, {limit:'2',...(cursor?{cursor}:{})});assert.ok(page.items.length<=2);seen.push(...page.items);cursor=page.meta.next_cursor;}while(cursor);
  assert.equal(seen.length,5);assert.equal(new Set(seen.map(x=>x.id)).size,5);assert.ok(seen.every(x=>x.country==='KZ'&&x.raw_receipt===undefined));assert.equal(seen.find(x=>x.id===legacy.id).cash_amount_minor,null);assert.equal(seen.find(x=>x.id===legacy.id).legacy,true);
  await a.store.put({...rows[0],id:randomUUID(),transaction_id:'used-boost',benefit:'boost',boost_id:randomUUID()});proof={...original,transaction_id:'used-boost',revision:5};await assert.rejects(()=>verify(member),e=>e.getResponse().error.code==='TRANSACTION_ALREADY_USED');
 }finally{await a.store.close();}
});
