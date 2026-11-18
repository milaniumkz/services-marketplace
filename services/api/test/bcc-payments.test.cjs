// Production mode below is an injected bank mock, never real live traffic.
const {mkdtempSync,rmSync}=require('node:fs'),{join}=require('node:path'),{tmpdir}=require('node:os');
const {test}=require('node:test'),assert=require('node:assert/strict'),{randomUUID}=require('node:crypto');
const {Marketplace}=require('../dist/marketplace'),{Store}=require('../dist/store'),{Providers}=require('../dist/providers');
const {BccGateway,bccOrder,bccMac,validateBccConfig}=require('../dist/bcc-gateway');
const config={environment:'production',notify_user:'joba-audit-fixture',notify_password:'synthetic-audit-callback-only',callback_registered:true,terminal:'12345678',merchant:'12345678',mac_key:'0123456789ABCDEF0123456789ABCDEF',public_origin:'https://joba.com.kz',countries:['KZ','KG'],currencies:['KZT']};
async function setup({legacy=false}={}){const store=new Store('memory://'),providers=new Providers();let captured=false,tamper=false,refundTimeout=false;const requests=[];const journal=mkdtempSync(join(tmpdir(),'joba-bcc-refund-'));const gateway=new BccGateway({...config,refund_journal_dir:journal},store,async(url,options)=>{
 assert.equal(url,'https://3dsecure.bcc.kz/webview');assert.equal(options.redirect,'error');const f=Object.fromEntries(new URLSearchParams(options.body));requests.push(f);if(f.TRTYPE==='14'){if(refundTimeout)throw Error('timeout after bank acceptance');return Response.json({ORDER:f.ORDER,TERMINAL:f.TERMINAL,TRTYPE:'14',ACTION:'0',RC:'00',AMOUNT:f.AMOUNT,CURRENCY:f.CURRENCY,INT_REF:'REFUND-'+f.MERCH_RN_ID});}
 return Response.json({ORDER:f.ORDER,TERMINAL:config.terminal,TRTYPE:'90',TRAN_TRTYPE:'1',ACTION:captured?'0':'3',RC:captured?'00':'-24',AMOUNT:tamper?'0.01':'500.00',CURRENCY:'398',RRN:'000111222333',INT_REF:'BANK-TEST-REF'});
 });providers.billing.set('bcc',gateway);if(legacy){const {VtbGateway}=require('../dist/vtb-gateway');providers.billing.set('vtb',new VtbGateway({environment:'sandbox',user_name:'legacy-test',password:'fake-test-only',public_origin:'https://joba.com.kz'},store,async()=>{throw Error('No bank request expected')}));}const api=new Marketplace(store,providers);await api.initialize();const s=await api.handle('POST','/auth/register',{country:'KZ',phone:'+77000002801',password:'BCC test password 123'},undefined,randomUUID(),{},randomUUID());await store.put({...await store.get(s.user.id),verification:'passed'});
 const call=(method,path,body={},query={})=>api.handle(method,path,body,'Bearer '+s.access_token,randomUUID(),query,'198.51.100.25');return {api,store,gateway,requests,call,user:s.user,set capture(v){captured=v},set tamper(v){tamper=v},set refundTimeout(v){refundTimeout=v},cleanup(){rmSync(journal,{recursive:true,force:true});}};
}
test('BCC signed hosted form binds exact payment; no browser return grants access; server capture is idempotent and private',async()=>{
 const c=await setup();try{
 const offer=(await c.call('GET','/billing/offers',{}, {bank_capability:'bcc-v1'})).items.find(x=>x.plan==='customer');assert.equal(offer.provider,'bcc');assert.equal(offer.currency,'KZT');
 const body={offer_id:offer.id,amount_minor:offer.amount_minor,currency:offer.currency,accepted:true,billing_address:'Алматы, улица Тестовая, 12'};const p=await c.call('POST','/billing/bcc/checkout',body);assert.equal((await c.store.get(p.id)).billing_address,body.billing_address);assert.equal(p.billing_address,undefined);assert.equal(p.provider,'bcc');assert.equal(p.status,'pending');assert.equal((await c.call('POST','/billing/bcc/checkout',body)).id,p.id);
 const url=new URL(p.payment_url);assert.equal(url.origin,'https://joba.com.kz');assert.equal(url.pathname,'/api/v1/public/billing/bcc/form');
 await assert.rejects(()=>c.api.handle('GET',url.pathname.replace('/api/v1',''),{},undefined,undefined,{payment_id:p.id,token:'fake'}),e=>e.getStatus()===403);
 const form=await c.api.handle('GET',url.pathname.replace('/api/v1',''),{},undefined,undefined,Object.fromEntries(url.searchParams),'198.51.100.25');assert.ok(form.public_html.includes('action="https://3dsecure.bcc.kz/webview"'));assert.ok(form.public_html.includes('name="AMOUNT" value="500.00"'));assert.ok(form.public_html.includes('name="ORDER" value="'+bccOrder(p.id)+'"'));assert.equal(form.public_html.includes(config.mac_key),false);assert.equal(form.public_html.includes('id="bcc-billing-address"'),false);
 assert.equal((await c.store.select('grant','KZ',{owner:c.user.id,limit:100})).length,0);
 await c.api.handle('GET','/public/billing/bcc/return',{},undefined,undefined,{payment_id:p.id,ACTION:'0',RC:'00'});assert.equal((await c.store.all('subscription','KZ')).length,0);
 c.capture=true;c.tamper=true;assert.equal((await c.call('GET','/billing/bcc/payments/'+p.id)).status,'pending');assert.equal((await c.store.all('subscription','KZ')).length,0);
 c.tamper=false;const results=await Promise.all([c.call('GET','/billing/bcc/payments/'+p.id),c.call('GET','/billing/vtb/payments/'+p.id)]);assert.equal(results[0].status,'completed');assert.equal(results[0].subscription_id,results[1].subscription_id);
 assert.equal((await c.store.all('subscription','KZ')).length,1);const ledger=(await c.store.all('payment_transaction','KZ'))[0];assert.equal(ledger.provider,'bcc');assert.equal(ledger.is_test,false);assert.equal(ledger.cash_amount_minor,50000);
 assert.equal(new Set(c.requests.map(r=>r.NONCE)).size,c.requests.length);
 const pending=await c.call('GET','/billing/vtb/pending');assert.equal(pending.items.length,0);
 }finally{await c.store.close();c.cleanup();}
});
test('BCC refuses unapproved currency/countries and malformed captured evidence instead of making up an exchange rate',async()=>{
 assert.throws(()=>validateBccConfig({...config,countries:['RU']}));assert.throws(()=>validateBccConfig({...config,public_origin:'http://joba.com.kz'}));
 const c=await setup();try{await c.store.put({id:randomUUID(),kind:'price_version',country:'KG',owner:c.user.id,version:1,created_at:new Date().toISOString(),status:'effective',payload:{provider:'bcc',product_type:'subscription',product_id:'unsupported-kg-sku',plan:'customer',currency:'KGS',amount_minor:50000,period:'days',duration_days:30}});await assert.rejects(()=>c.gateway.validateProduct('unsupported-kg-sku','KG'));const kg=(await c.api.commerce.offers('KG','customer')).items;assert.equal(kg.some(x=>x.provider==='bcc'),false);
 const p={id:randomUUID(),amount_minor:50000,currency:'KZT'};const evidence={ORDER:bccOrder(p.id),TERMINAL:config.terminal,TRTYPE:'90',TRAN_TRTYPE:'1',ACTION:'0',RC:'00',AMOUNT:'500.00',CURRENCY:'398',RRN:'123',INT_REF:'ref'};
 assert.equal(c.gateway.validateStatus(p,evidence),2);assert.throws(()=>c.gateway.validateStatus(p,{...evidence,ACTION:'3',RC:'-2'}),e=>e.getResponse().error.code==='BCC_BANK_ERROR_2');for(const patch of [{AMOUNT:'1.00'},{CURRENCY:'417'},{ORDER:'another'},{RRN:''},{TRAN_TRTYPE:'0'},{TERMINAL:'99999999'}])assert.throws(()=>c.gateway.validateStatus(p,{...evidence,...patch}));
 }finally{await c.store.close();c.cleanup();}
});

test('BCC partial refund has server proof; a timed-out refund is never resent after a SQL rollback',async()=>{
 const c=await setup();try{
 const offer=(await c.call('GET','/billing/offers',{}, {bank_capability:'bcc-v1'})).items.find(x=>x.plan==='customer');const p=await c.call('POST','/billing/bcc/checkout',{offer_id:offer.id,amount_minor:offer.amount_minor,currency:offer.currency,accepted:true});c.capture=true;assert.equal((await c.call('GET','/billing/bcc/payments/'+p.id)).status,'completed');
 const payment=(await c.store.all('payment_transaction','KZ'))[0];let refund=await c.api.refunds.create(c.user.id,'KZ',payment.id,10000,'Test refund');refund=await c.api.refunds.command(refund,randomUUID(),'approve','Test approval');refund=await c.api.refunds.command(refund,randomUUID(),'submit','Test bank submit');assert.equal(refund.status,'pending');refund=await c.api.refunds.command(refund,randomUUID(),'reconcile','Test bank proof');assert.equal(refund.status,'confirmed');assert.equal((await c.store.all('payment_transaction','KZ')).find(x=>x.operation==='refund').cash_amount_minor,-10000);
 let ambiguous=await c.api.refunds.create(c.user.id,'KZ',payment.id,10000,'Timeout test');ambiguous=await c.api.refunds.command(ambiguous,randomUUID(),'approve','Test approval');c.refundTimeout=true;
 await c.store.db.exec('BEGIN');await c.api.refunds.command(ambiguous,randomUUID(),'submit','First attempt');await c.store.db.exec('ROLLBACK');
 const calls=c.requests.filter(r=>r.TRTYPE==='14').length;const pending=await c.api.refunds.command(ambiguous,randomUUID(),'submit','Retry after rollback');assert.equal(pending.status,'pending');assert.equal(c.requests.filter(r=>r.TRTYPE==='14').length,calls);assert.equal((await c.api.refunds.command(pending,randomUUID(),'reconcile','Ambiguous bank proof')).status,'pending');
 }finally{await c.store.close();c.cleanup();}
});

test('old clients retain VTB quotes while updated clients receive BCC without duplicate bank-price offers',async()=>{
 const c=await setup({legacy:true});try{
 for(const provider of ['vtb','bcc'])await c.store.put({id:randomUUID(),kind:'price_version',country:'KZ',owner:c.user.id,version:1,created_at:new Date().toISOString(),status:'effective',payload:{provider,product_type:'subscription',product_id:provider+'-sku',plan:'customer',currency:'KZT',amount_minor:50000,period:'days',duration_days:30}});
 const old=await c.call('GET','/billing/offers');assert.equal(old.items.length,1);assert.equal(old.items[0].provider,'vtb');
 const updated=await c.call('GET','/billing/offers',{}, {bank_capability:'bcc-v1'});assert.equal(updated.items.length,1);assert.equal(updated.items[0].provider,'bcc');assert.notEqual(old.items[0].id,updated.items[0].id);
 }finally{await c.store.close();c.cleanup();}
});
test('unconfirmed BCC payment is sent to reconciliation after the bank status window without inventing a purchase or refund',async()=>{
 const c=await setup();try{
 const offer=(await c.call('GET','/billing/offers',{}, {bank_capability:'bcc-v1'})).items[0];const p=await c.call('POST','/billing/bcc/checkout',{offer_id:offer.id,amount_minor:offer.amount_minor,currency:offer.currency,accepted:true});
 await c.store.put({...await c.store.get(p.id),created_at:new Date(Date.now()-25*3600000).toISOString()});const status=await c.call('GET','/billing/bcc/payments/'+p.id);assert.equal(status.status,'resolution_required');assert.equal(status.can_refund,false);assert.equal(status.payment_url,null);assert.equal((await c.store.all('payment_transaction','KZ')).length,0);assert.equal((await c.store.all('subscription','KZ')).length,0);
 }finally{await c.store.close();c.cleanup();}
});

test('switching BCC to live does not let a previous sandbox checkout block or reappear in live payment choices',async()=>{
 const c=await setup();try{
 const id=randomUUID(),now=new Date().toISOString();await c.store.put({id,kind:'bank_checkout',owner:c.user.id,country:'KZ',version:1,created_at:now,status:'pending',provider:'bcc',environment:'sandbox',role:'customer',source_id:'previous-sandbox-only',offer:{plan:'customer',title:'Previous sandbox fixture'},amount_minor:50000,currency:'KZT',expires_at:new Date(Date.now()+600000).toISOString()});
 const offers=await c.call('GET','/billing/offers',{}, {bank_capability:'bcc-v1'}),offer=offers.items.find(p=>p.plan==='customer');
 const current=await c.call('POST','/billing/bcc/checkout',{offer_id:offer.id,amount_minor:offer.amount_minor,currency:offer.currency,accepted:true});
 assert.notEqual(current.id,id);assert.equal(current.environment,'production');assert.equal(current.status,'pending');
 assert.ok(!(await c.call('GET','/billing/bcc/pending')).items.some(p=>p.id===id));
 assert.equal((await c.store.get(id)).environment,'sandbox');assert.equal((await c.store.get(id)).status,'pending');
 }finally{await c.store.close();c.cleanup();}
});
test('a CGI status error is unresolved rather than a fictitious card decline; the hosted form remains available',async()=>{
 const c=await setup();try{
 c.gateway.transport=async(_url,options)=>{const fields=Object.fromEntries(new URLSearchParams(options.body));return Response.json({ORDER:fields.ORDER,TERMINAL:config.terminal,ACTION:'3',RC:'-2'});};
 const offer=(await c.call('GET','/billing/offers',{}, {bank_capability:'bcc-v1'})).items.find(p=>p.plan==='customer');
 const current=await c.call('POST','/billing/bcc/checkout',{offer_id:offer.id,amount_minor:offer.amount_minor,currency:offer.currency,accepted:true});
 assert.equal(current.status,'pending');assert.ok(current.payment_url);assert.equal(c.requests.length,0);await c.call('GET','/billing/bcc/payments/'+current.id);assert.equal((await c.store.get(current.id)).last_error,'BCC_BANK_ERROR_2');
 assert.equal((await c.store.all('subscription')).length,0);assert.equal((await c.store.all('grant')).length,0);
 }finally{await c.store.close();c.cleanup();}
});

test('BCC refuses an under-minimum positive KZT quote without changing the price or creating a bank payment',async()=>{
 const c=await setup();try{
 await c.store.put({id:randomUUID(),kind:'subscription_catalog',country:'KZ',owner:c.user.id,version:1,created_at:new Date().toISOString(),prices:{customer:2000,standard:70000,premium:150000,top100:50000}});
 const offer=(await c.call('GET','/billing/offers',{}, {bank_capability:'bcc-v1'})).items.find(p=>p.plan==='customer');assert.equal(offer.amount_minor,2000);
 await assert.rejects(()=>c.call('POST','/billing/bcc/checkout',{offer_id:offer.id,amount_minor:offer.amount_minor,currency:offer.currency,accepted:true}),e=>e.getResponse().error.code==='BCC_AMOUNT_BELOW_MINIMUM');
 assert.equal(c.requests.length,0);assert.equal((await c.store.all('bank_checkout')).length,0);assert.equal((await c.store.all('subscription')).length,0);
 }finally{await c.store.close();c.cleanup();}
});

test('disabling BCC hides new checkout and saved payment URLs while independently settling an already captured payment',async()=>{
 const c=await setup();try{
 const offer=(await c.call('GET','/billing/offers',{}, {bank_capability:'bcc-v1'})).items.find(p=>p.plan==='customer');
 const body={offer_id:offer.id,amount_minor:offer.amount_minor,currency:offer.currency,accepted:true},pending=await c.call('POST','/billing/bcc/checkout',body);
 await c.store.put({id:randomUUID(),kind:'payment_controls',country:'KZ',owner:c.user.id,version:1,created_at:new Date().toISOString(),bcc_enabled:false,vtb_enabled:true,rewarded_enabled:true});
 assert.equal((await c.call('GET','/billing/offers',{}, {bank_capability:'bcc-v1'})).items.length,0);
 assert.equal((await c.call('GET','/me/monetization-config',{}, {bank_capability:'bcc-v1'})).paid_checkout_enabled,false);
 await assert.rejects(()=>c.call('POST','/billing/bcc/checkout',body),e=>e.getResponse().error.code==='PAYMENT_METHOD_DISABLED');
 assert.equal((await c.call('GET','/billing/bcc/payments/'+pending.id)).payment_url,null);
 const url=new URL(pending.payment_url),paused=await c.api.handle('GET',url.pathname.replace('/api/v1',''),{},undefined,undefined,Object.fromEntries(url.searchParams),'198.51.100.25');assert.ok(paused.public_html.includes('Оплата через банк временно недоступна'));assert.ok(paused.public_html.includes('Вернуться в JOBA'));assert.ok(!paused.public_html.includes('P_SIGN'));
 c.capture=true;assert.equal((await c.call('GET','/billing/bcc/payments/'+pending.id)).status,'completed');assert.equal((await c.store.all('subscription')).length,1);
 }finally{await c.store.close();c.cleanup();}
});

test('BCC validates checkout address without creating payments and updates only the existing pending attempt on retry',async()=>{
 const c=await setup();try{
 const offer=(await c.call('GET','/billing/offers',{}, {bank_capability:'bcc-v1'})).items.find(x=>x.plan==='customer');const body={offer_id:offer.id,amount_minor:offer.amount_minor,currency:offer.currency,accepted:true};
 for(const billing_address of ['   ','x'.repeat(51),23])await assert.rejects(()=>c.call('POST','/billing/bcc/checkout',{...body,billing_address}),e=>e.getResponse().error.code==='VALIDATION_ERROR');
 assert.equal((await c.store.all('bank_checkout','KZ')).length,0);
 const p=await c.call('POST','/billing/bcc/checkout',body);const resumed=await c.call('POST','/billing/bcc/checkout',{...body,billing_address:'  Алматы, Тестовая, 12  '});assert.equal(resumed.id,p.id);assert.equal((await c.store.get(p.id)).billing_address,'Алматы, Тестовая, 12');assert.equal((await c.store.all('bank_checkout','KZ')).length,1);
 }finally{await c.store.close();c.cleanup();}
});

test('unopened BCC checkout cancels immediately and its issued URL cannot be opened; a fresh quote can be paid again',async()=>{
 const c=await setup();try{
 const offer=(await c.call('GET','/billing/offers',{}, {bank_capability:'bcc-v1'})).items.find(x=>x.plan==='customer');const p=await c.call('POST','/billing/bcc/checkout',{offer_id:offer.id,amount_minor:offer.amount_minor,currency:offer.currency,accepted:true});const url=new URL(p.payment_url);
 const canceled=await c.call('POST','/billing/bcc/payments/'+p.id+'/cancel');assert.equal(canceled.status,'canceled');assert.equal(canceled.can_cancel,false);assert.equal(canceled.can_retry,true);assert.equal(canceled.payment_url,null);
 await assert.rejects(()=>c.api.handle('GET',url.pathname.replace('/api/v1',''),{},undefined,undefined,Object.fromEntries(url.searchParams),'198.51.100.25'),e=>e.getResponse().error.code==='PAYMENT_EXPIRED');
 const next=(await c.call('GET','/billing/offers',{}, {bank_capability:'bcc-v1'})).items.find(x=>x.plan==='customer');const again=await c.call('POST','/billing/bcc/checkout',{offer_id:next.id,amount_minor:next.amount_minor,currency:next.currency,accepted:true});assert.notEqual(again.id,p.id);assert.ok(again.payment_url);assert.equal((await c.store.all('subscription','KZ')).length,0);
 }finally{await c.store.close();c.cleanup();}
});
test('opened BCC checkout never pretends cancellation succeeded while the bank status is pending; capture still wins',async()=>{
 const c=await setup();try{
 const offer=(await c.call('GET','/billing/offers',{}, {bank_capability:'bcc-v1'})).items.find(x=>x.plan==='customer');const p=await c.call('POST','/billing/bcc/checkout',{offer_id:offer.id,amount_minor:offer.amount_minor,currency:offer.currency,accepted:true});const url=new URL(p.payment_url);
 await c.api.handle('GET',url.pathname.replace('/api/v1',''),{},undefined,undefined,Object.fromEntries(url.searchParams),'198.51.100.25');assert.ok((await c.store.get(p.id)).form_opened_at);
 const result=await c.call('POST','/billing/bcc/payments/'+p.id+'/cancel');assert.equal(result.status,'pending');assert.equal(result.cancel_requested,true);assert.equal(result.can_cancel,false);assert.equal(result.can_retry,false);assert.equal(result.payment_url,null);assert.match(result.message,/Отмена запрошена/);
 c.capture=true;assert.equal((await c.call('GET','/billing/bcc/payments/'+p.id)).status,'completed');assert.equal((await c.store.all('subscription','KZ')).length,1);
 }finally{await c.store.close();c.cleanup();}
});

test('owner removes a stuck checkout from customer flow while preserving bank reconciliation and rejecting the old URL',async()=>{
 const c=await setup();try{
 const offer=(await c.call('GET','/billing/offers',{}, {bank_capability:'bcc-v1'})).items.find(x=>x.plan==='customer'),p=await c.call('POST','/billing/bcc/checkout',{offer_id:offer.id,amount_minor:offer.amount_minor,currency:offer.currency,accepted:true});const url=new URL(p.payment_url),path='/admin/bank-checkouts/'+p.id+'/abandon';
 await assert.rejects(()=>c.call('GET',path),e=>e.getStatus()===403);
 const password='Isolated checkout administrator password!',boss=await c.api.handle('POST','/auth/register',{country:'KZ',phone:'+77000002809',password});await c.store.put({...await c.store.get(boss.user.id),staff_permissions:['platform_owner']});const owner=await c.api.handle('POST','/auth/staff-login',{country:'KZ',phone:boss.user.phone,password});
 const admin=(m,b={})=>c.api.handle(m,path,b,'Bearer '+owner.access_token,randomUUID());
 let state=await admin('GET');await assert.rejects(()=>admin('POST',{owner_id:randomUUID(),expected_version:state.version,reason:'Explicit owner request to remove stuck checkout'}),e=>e.getStatus()===404);
 await admin('POST',{owner_id:c.user.id,expected_version:state.version,reason:'Explicit owner request to remove stuck checkout'});
 assert.equal((await c.call('GET','/billing/bcc/pending')).items.length,0);assert.ok((await c.store.get(p.id)).checkout_abandoned_at);await c.store.put({...await c.store.get(p.id),last_checked_at:new Date(Date.now()-60000).toISOString()});assert.ok((await c.api.bcc.pendingIds()).includes(p.id));
 await assert.rejects(()=>c.api.handle('GET',url.pathname.replace('/api/v1',''),{},undefined,undefined,Object.fromEntries(url.searchParams),'198.51.100.25'),e=>e.getResponse().error.code==='PAYMENT_EXPIRED');
 const next=(await c.call('GET','/billing/offers',{}, {bank_capability:'bcc-v1'})).items.find(x=>x.plan==='customer'),again=await c.call('POST','/billing/bcc/checkout',{offer_id:next.id,amount_minor:next.amount_minor,currency:next.currency,accepted:true});assert.notEqual(again.id,p.id);
 c.capture=true;const late=await c.call('GET','/billing/bcc/payments/'+p.id);assert.equal(late.status,'resolution_required');assert.equal((await c.store.get(p.id)).resolution_code,'ABANDONED_CHECKOUT_CAPTURED');assert.equal((await c.store.all('subscription','KZ')).length,0);assert.equal((await c.store.all('payment_transaction','KZ')).length,1);assert.equal((await c.store.all('audit','KZ')).filter(x=>x.action==='billing.checkout_abandoned').length,1);
 }finally{await c.store.close();c.cleanup();}
});

test('a fresh checkout archives a superseded, expired or cancellation-requested BCC attempt and opens a new local bank form without a status round trip',async()=>{
 for(const mode of ['expired','cancelled','new-intent']){const cancelled=mode==='cancelled',c=await setup();try{
 const first=(await c.call('GET','/billing/offers',{}, {bank_capability:'bcc-v1'})).items.find(x=>x.plan==='customer'),old=await c.call('POST','/billing/bcc/checkout',{offer_id:first.id,amount_minor:first.amount_minor,currency:first.currency,accepted:true});assert.equal(c.requests.length,0);
 await c.store.put({...await c.store.get(old.id),cancel_requested:cancelled,expires_at:mode!=='expired'?new Date(Date.now()+600000).toISOString():new Date(Date.now()-1000).toISOString()});
 const offer=(await c.call('GET','/billing/offers',{}, {bank_capability:'bcc-v1'})).items.find(x=>x.plan==='customer'),body={offer_id:offer.id,amount_minor:offer.amount_minor,currency:offer.currency,accepted:true},payment=await c.call('POST','/billing/bcc/checkout',body);
 assert.notEqual(payment.id,old.id);assert.ok(payment.payment_url);assert.equal(c.requests.length,0);assert.ok((await c.store.get(old.id)).checkout_abandoned_at);assert.equal((await c.store.get(old.id)).status,'pending');assert.equal((await c.call('GET','/billing/bcc/pending')).items.some(p=>p.id===old.id),false);
 assert.equal((await c.call('POST','/billing/bcc/checkout',body)).id,payment.id);assert.equal((await c.store.all('bank_checkout','KZ')).length,2);assert.equal((await c.store.all('subscription','KZ')).length,0);
 }finally{await c.store.close();c.cleanup();}}
});
