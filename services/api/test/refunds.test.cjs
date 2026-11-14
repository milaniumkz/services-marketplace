const {test}=require('node:test'),assert=require('node:assert/strict'),{randomUUID,randomBytes}=require('node:crypto');
const {Marketplace}=require('../dist/marketplace'),{Store}=require('../dist/store'),{Providers}=require('../dist/providers'),{totp}=require('../dist/totp');
const password='Isolated refund lifecycle password!';
async function setup(){
 const providers=new Providers(),a=new Marketplace(new Store('memory://'),providers);await a.initialize();const users=[];
 for(const phone of ['+77000000931','+77000000932','+77000000933'])users.push(await a.handle('POST','/auth/register',{country:'KZ',phone,password},undefined,randomUUID()));
 const [owner,other,staffUser]=users;await a.store.put({...await a.store.get(owner.user.id),roles:['customer','executor'],active_role:'executor'});
 const staff=[];for(const u of [owner,staffUser]){const secret=randomBytes(20).toString('hex');await a.store.put({...await a.store.get(u.user.id),staff_permissions:['billing'],totp_secret:secret});staff.push(await a.handle('POST','/auth/staff-login',{country:'KZ',phone:u.user.phone,password,mfa_code:totp(secret)},undefined,randomUUID()));}
 const call=(u,m,p,b={},key=randomUUID())=>a.handle(m,p,b,'Bearer '+u.access_token,key);
 const proof={provider:'isolated-refund',transaction_id:'paid-one',original_transaction_id:'chain-one',user_id:owner.user.id,country:'KZ',product_id:'monthly',environment:'sandbox',amount_minor:1000,currency:'KZT',valid_until:new Date(Date.now()+86400000).toISOString(),state:'active',revision:1};
 const provider={name:proof.provider,verifyPurchase:async()=>proof};providers.billing.set(proof.provider,provider);
 await a.store.put({id:randomUUID(),kind:'price_version',owner:'system',country:'KZ',version:1,created_at:new Date().toISOString(),status:'effective',payload:{provider:proof.provider,product_id:'monthly',product_type:'subscription',amount_minor:1000,currency:'KZT'}});
 const purchase=await call(owner,'POST','/billing/verify-purchase',{provider:proof.provider,transaction_reference:'verified'}),payment=(await a.store.all('payment_transaction','KZ'))[0];
 const reason='Проверка возврата подтверждённого платежа';
 const create=(amount,key)=>call(owner,'POST','/billing/refund-requests',{payment_id:payment.id,amount_minor:amount,reason},key);
 const command=(r,action,u=staff[1])=>call(u,'POST','/admin/refund-requests/'+r.id+'/'+action,{expected_version:r.version,reason});
 const evidence=(r,status='succeeded',id='bank-'+r.id)=>({environment:'sandbox',provider:proof.provider,request_id:r.id,refund_id:id,transaction_id:payment.transaction_id,user_id:owner.user.id,country:'KZ',amount_minor:r.amount_minor,currency:'KZT',status});
 return {a,provider,proof,owner,other,staff,call,purchase,payment,reason,create,command,evidence};
}
const rejects=(fn,code)=>assert.rejects(fn,e=>e.getResponse().error.code===code);
test('partial refunds reserve the remainder, require independent approval and verified evidence; full refund reverses access once',async()=>{
 const {a,provider,proof,owner,other,staff,call,purchase,payment,reason,create,command,evidence}=await setup();
 try{
  for(const n of [0,-1,1.5,'400'])await rejects(()=>create(n),'VALIDATION_ERROR');
  await rejects(()=>call(other,'POST','/billing/refund-requests',{payment_id:payment.id,amount_minor:1,reason}),'NOT_FOUND');
  const key=randomUUID();let first=await create(400,key);assert.equal((await create(400,key)).id,first.id);await rejects(()=>create(601),'REFUND_EXCEEDS_REMAINING');
  await rejects(()=>command(first,'approve',staff[0]),'SECOND_APPROVAL_REQUIRED');
  const available=await call(owner,'GET','/billing/refundable-payments');assert.equal(available.items[0].balance.available_minor,600);assert.equal(available.items[0].transaction_id,undefined);assert.equal((await call(other,'GET','/billing/refundable-payments')).items.length,0);
  const second=await create(600);await rejects(()=>create(1),'REFUND_EXCEEDS_REMAINING');
  first=await command(first,'approve');await rejects(()=>command({...first,version:1},'reject'),'STATE_CONFLICT');await rejects(()=>command(first,'submit'),'PROVIDER_UNAVAILABLE');assert.equal((await a.store.get(first.id)).status,'approved');
  await rejects(()=>call(owner,'POST','/billing/refund-requests/'+first.id+'/cancel',{expected_version:first.version,reason}),'STATE_CONFLICT');
  provider.requestRefund=async r=>({reference:'pending-'+r.request_id});provider.verifyRefund=async id=>evidence(await a.store.get(id));
  first=await command(first,'submit');assert.equal(first.status,'pending');assert.equal((await a.store.all('payment_transaction','KZ')).length,1);
  first=await command(first,'reconcile');assert.equal(first.status,'confirmed');assert.equal(first.access_action,'preserved');assert.equal((await a.store.get(purchase.subscription.id)).status,'active');
  await rejects(()=>command(first,'reconcile'),'STATE_CONFLICT');
  let last=await command(second,'approve');last=await command(last,'submit');last=await command(last,'reconcile');assert.equal(last.status,'confirmed');assert.equal(last.access_action,'revoked');
  const rows=await a.store.all('payment_transaction','KZ');assert.equal(rows.filter(x=>x.operation==='refund').length,2);assert.equal(rows.filter(x=>x.operation==='access_reversal').length,1);assert.equal(rows.reduce((s,x)=>s+x.cash_amount_minor,0),0);assert.ok(Date.parse((await a.store.all('grant','KZ'))[0].valid_until)<=Date.now());
  await rejects(()=>create(1),'REFUND_EXCEEDS_REMAINING');
  proof.revision=2;const restored=await call(owner,'POST','/billing/restore',{provider:proof.provider,transaction_reference:'verified'});assert.equal(restored.subscription.status,'revoked');assert.ok(Date.parse((await a.store.all('grant','KZ'))[0].valid_until)<=Date.now());
  const own=await call(owner,'GET','/billing/refund-requests');assert.equal(own.items.length,2);assert.ok(own.items.every(x=>x.status==='confirmed'&&x.provider_reference===undefined));assert.equal((await call(other,'GET','/billing/refund-requests')).items.length,0);
 }finally{await a.store.close();}
});
test('unknown outcomes retain reservations until reconciliation; cancellation/rejection/failure release them and older refunds preserve a newer purchase',async()=>{
 const {a,provider,proof,owner,staff,call,purchase,payment,reason,create,command,evidence}=await setup();
 try{
  let cancel=await create(1000);cancel=await call(owner,'POST','/billing/refund-requests/'+cancel.id+'/cancel',{reason,expected_version:1});assert.equal(cancel.status,'canceled');
  let rejected=await create(1000);rejected=await command(rejected,'reject');assert.equal(rejected.status,'rejected');
  let first=await create(1000);first=await command(first,'approve');const keys=[];provider.requestRefund=async r=>{keys.push(r.request_id);throw Error('uncertain network outcome');};
  first=await command(first,'submit');assert.equal(first.status,'unknown');assert.deepEqual(keys,[first.id]);await rejects(()=>command(first,'submit'),'STATE_CONFLICT');await rejects(()=>create(1),'REFUND_EXCEEDS_REMAINING');
  provider.verifyRefund=async id=>({...evidence(await a.store.get(id)),amount_minor:999});await rejects(()=>command(first,'reconcile'),'REFUND_EVIDENCE_MISMATCH');assert.equal((await a.store.get(first.id)).status,'unknown');
  provider.verifyRefund=async id=>evidence(await a.store.get(id),'failed');first=await command(first,'reconcile');assert.equal(first.status,'failed');
  let newer=await create(1000);newer=await command(newer,'approve');provider.requestRefund=async r=>({reference:'accepted-'+r.request_id});newer=await command(newer,'submit');
  proof.transaction_id='paid-two';proof.revision=2;await call(owner,'POST','/billing/verify-purchase',{provider:proof.provider,transaction_reference:'verified'});
  provider.verifyRefund=async id=>evidence(await a.store.get(id));newer=await command(newer,'reconcile');assert.equal(newer.access_action,'newer_purchase_preserved');assert.equal((await a.store.get(purchase.subscription.id)).status,'active');assert.ok(Date.parse((await a.store.all('grant','KZ'))[0].valid_until)>Date.now());
  const refunded=(await a.store.all('payment_transaction','KZ')).filter(x=>x.operation==='refund');assert.equal(refunded.length,1);assert.equal(refunded[0].original_payment_id,payment.id);
  await assert.rejects(()=>a.store.put({...refunded[0],amount_minor:1}),/append-only/);
 }finally{await a.store.close();}
});
test('refund evidence cannot cross requests or fields and full boost refunds revoke only their own placement',async()=>{
 const {a,provider,owner,staff,call,reason,create,command,evidence}=await setup();
 try{
  provider.requestRefund=async r=>({reference:'accepted-'+r.request_id});
  let first=await create(100),second=await create(100);first=await command(await command(first,'approve'),'submit');provider.verifyRefund=async id=>evidence(await a.store.get(id),'succeeded','same-bank-id');first=await command(first,'reconcile');
  second=await command(await command(second,'approve'),'submit');await rejects(()=>command(second,'reconcile'),'REFUND_ALREADY_USED');
  for(const change of [{request_id:first.id},{environment:'production'},{user_id:staff[1].user.id},{currency:'USD'},{country:'KG'},{transaction_id:'foreign'},{status:'invalid'}]){provider.verifyRefund=async id=>({...evidence(await a.store.get(id)),...change});await rejects(()=>command(second,'reconcile'),'REFUND_EVIDENCE_MISMATCH');}
  provider.verifyRefund=async id=>evidence(await a.store.get(id));second=await command(second,'reconcile');assert.equal(second.status,'confirmed');
  const row=(await a.store.all('payment_transaction','KZ')).find(x=>x.operation==='refund');await assert.rejects(()=>a.store.put({...row,id:randomUUID()}),/unique/i);
  const boost={id:randomUUID(),kind:'boost',owner:owner.user.id,country:'KZ',version:1,created_at:new Date().toISOString(),target_id:randomUUID(),placement_id:'search.orders.promoted',status:'active'};await a.store.put(boost);
  const payment={id:randomUUID(),kind:'payment_transaction',owner:owner.user.id,country:'KZ',version:1,created_at:new Date().toISOString(),provider:'isolated-refund',transaction_id:'paid-boost',environment:'sandbox',state:'active',operation:'purchase',amount_minor:500,cash_amount_minor:500,currency:'KZT',benefit:'boost',source_id:boost.id};await a.store.put(payment);
  let request=await call(owner,'POST','/billing/refund-requests',{payment_id:payment.id,amount_minor:500,reason});request=await command(await command(request,'approve'),'submit');provider.verifyRefund=async id=>({...evidence(await a.store.get(id)),transaction_id:'paid-boost'});request=await command(request,'reconcile');assert.equal(request.access_action,'revoked');assert.equal((await a.store.get(boost.id)).status,'revoked');
 }finally{await a.store.close();}
});
