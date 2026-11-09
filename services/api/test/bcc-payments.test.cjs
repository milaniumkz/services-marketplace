const {mkdtempSync,rmSync}=require('node:fs'),{join}=require('node:path'),{tmpdir}=require('node:os');
const {test}=require('node:test'),assert=require('node:assert/strict'),{randomUUID}=require('node:crypto');
const {Marketplace}=require('../dist/marketplace'),{Store}=require('../dist/store'),{Providers}=require('../dist/providers');
const {BccGateway,bccOrder,bccMac,validateBccConfig}=require('../dist/bcc-gateway');
const config={environment:'sandbox',terminal:'12345678',merchant:'12345678',mac_key:'0123456789ABCDEF0123456789ABCDEF',public_origin:'https://joba.com.kz',countries:['KZ','KG'],currencies:['KZT']};
async function setup(){const store=new Store('memory://'),providers=new Providers();let captured=false,tamper=false,refundTimeout=false;const requests=[];const journal=mkdtempSync(join(tmpdir(),'joba-bcc-refund-'));const gateway=new BccGateway({...config,refund_journal_dir:journal},store,async(url,options)=>{
 assert.equal(url,'https://test3ds.bcc.kz:5445/cgi-bin/cgi_link');assert.equal(options.redirect,'error');const f=Object.fromEntries(new URLSearchParams(options.body));requests.push(f);if(f.TRTYPE==='14'){if(refundTimeout)throw Error('timeout after bank acceptance');return Response.json({ORDER:f.ORDER,TERMINAL:f.TERMINAL,TRTYPE:'14',ACTION:'0',RC:'00',AMOUNT:f.AMOUNT,CURRENCY:f.CURRENCY,INT_REF:'REFUND-'+f.MERCH_RN_ID});}
 return Response.json({ORDER:f.ORDER,TERMINAL:config.terminal,TRTYPE:'90',TRAN_TRTYPE:'1',ACTION:captured?'0':'3',RC:captured?'00':'-24',AMOUNT:tamper?'0.01':'500.00',CURRENCY:'398',RRN:'000111222333',INT_REF:'BANK-TEST-REF'});
 });providers.billing.set('bcc',gateway);const api=new Marketplace(store,providers);await api.initialize();const s=await api.handle('POST','/auth/register',{country:'KZ',phone:'+77000002801',password:'BCC test password 123'},undefined,randomUUID(),{},randomUUID());await store.put({...await store.get(s.user.id),verification:'passed'});
 const call=(method,path,body={},query={})=>api.handle(method,path,body,'Bearer '+s.access_token,randomUUID(),query,randomUUID());return {api,store,gateway,requests,call,user:s.user,set capture(v){captured=v},set tamper(v){tamper=v},set refundTimeout(v){refundTimeout=v},cleanup(){rmSync(journal,{recursive:true,force:true});}};
}
test('BCC signed hosted form binds exact payment; no browser return grants access; server capture is idempotent and private',async()=>{
 const c=await setup();try{
 const offer=(await c.call('GET','/billing/offers',{}, {bank_capability:'bcc-v1'})).items.find(x=>x.plan==='customer');assert.equal(offer.provider,'bcc');assert.equal(offer.currency,'KZT');
 const body={offer_id:offer.id,amount_minor:offer.amount_minor,currency:offer.currency,accepted:true};const p=await c.call('POST','/billing/bcc/checkout',body);assert.equal(p.provider,'bcc');assert.equal(p.status,'pending');assert.equal((await c.call('POST','/billing/bcc/checkout',body)).id,p.id);
 const url=new URL(p.payment_url);assert.equal(url.origin,'https://joba.com.kz');assert.equal(url.pathname,'/api/v1/public/billing/bcc/form');
 await assert.rejects(()=>c.api.handle('GET',url.pathname.replace('/api/v1',''),{},undefined,undefined,{payment_id:p.id,token:'fake'}),e=>e.getStatus()===403);
 const form=await c.api.handle('GET',url.pathname.replace('/api/v1',''),{},undefined,undefined,Object.fromEntries(url.searchParams));assert.ok(form.public_html.includes('action="https://test3ds.bcc.kz:5445/cgi-bin/cgi_link"'));assert.ok(form.public_html.includes('name="AMOUNT" value="500.00"'));assert.ok(form.public_html.includes('name="ORDER" value="'+bccOrder(p.id)+'"'));assert.equal(form.public_html.includes(config.mac_key),false);
 assert.equal((await c.store.select('grant','KZ',{owner:c.user.id,limit:100})).length,0);
 await c.api.handle('GET','/public/billing/bcc/return',{},undefined,undefined,{payment_id:p.id,ACTION:'0',RC:'00'});assert.equal((await c.store.all('subscription','KZ')).length,0);
 c.capture=true;c.tamper=true;assert.equal((await c.call('GET','/billing/bcc/payments/'+p.id)).status,'pending');assert.equal((await c.store.all('subscription','KZ')).length,0);
 c.tamper=false;const results=await Promise.all([c.call('GET','/billing/bcc/payments/'+p.id),c.call('GET','/billing/vtb/payments/'+p.id)]);assert.equal(results[0].status,'completed');assert.equal(results[0].subscription_id,results[1].subscription_id);
 assert.equal((await c.store.all('subscription','KZ')).length,1);const ledger=(await c.store.all('payment_transaction','KZ'))[0];assert.equal(ledger.provider,'bcc');assert.equal(ledger.is_test,true);assert.equal(ledger.cash_amount_minor,0);
 assert.equal(new Set(c.requests.map(r=>r.NONCE)).size,c.requests.length);
 const pending=await c.call('GET','/billing/vtb/pending');assert.equal(pending.items.length,0);
 }finally{await c.store.close();c.cleanup();}
});
test('BCC refuses unapproved currency/countries and malformed captured evidence instead of making up an exchange rate',async()=>{
 assert.throws(()=>validateBccConfig({...config,countries:['RU']}));assert.throws(()=>validateBccConfig({...config,public_origin:'http://joba.com.kz'}));
 const c=await setup();try{const kg=(await c.api.commerce.offers('KG','customer')).items;assert.equal(kg.some(x=>x.provider==='bcc'),false);
 const p={id:randomUUID(),amount_minor:50000,currency:'KZT'};const evidence={ORDER:bccOrder(p.id),TERMINAL:config.terminal,TRTYPE:'90',TRAN_TRTYPE:'1',ACTION:'0',RC:'00',AMOUNT:'500.00',CURRENCY:'398',RRN:'123',INT_REF:'ref'};
 assert.equal(c.gateway.validateStatus(p,evidence),2);for(const patch of [{AMOUNT:'1.00'},{CURRENCY:'417'},{ORDER:'another'},{RRN:''},{TRAN_TRTYPE:'0'},{TERMINAL:'99999999'}])assert.throws(()=>c.gateway.validateStatus(p,{...evidence,...patch}));
 }finally{await c.store.close();c.cleanup();}
});

test('BCC partial refund has server proof; a timed-out refund is never resent after a SQL rollback',async()=>{
 const c=await setup();try{
 const offer=(await c.call('GET','/billing/offers',{}, {bank_capability:'bcc-v1'})).items.find(x=>x.plan==='customer');const p=await c.call('POST','/billing/bcc/checkout',{offer_id:offer.id,amount_minor:offer.amount_minor,currency:offer.currency,accepted:true});c.capture=true;assert.equal((await c.call('GET','/billing/bcc/payments/'+p.id)).status,'completed');
 const payment=(await c.store.all('payment_transaction','KZ'))[0];let refund=await c.api.refunds.create(c.user.id,'KZ',payment.id,10000,'Test refund');refund=await c.api.refunds.command(refund,randomUUID(),'approve','Test approval');refund=await c.api.refunds.command(refund,randomUUID(),'submit','Test bank submit');assert.equal(refund.status,'pending');refund=await c.api.refunds.command(refund,randomUUID(),'reconcile','Test bank proof');assert.equal(refund.status,'confirmed');assert.equal((await c.store.all('payment_transaction','KZ')).find(x=>x.operation==='refund').cash_amount_minor,0);
 let ambiguous=await c.api.refunds.create(c.user.id,'KZ',payment.id,10000,'Timeout test');ambiguous=await c.api.refunds.command(ambiguous,randomUUID(),'approve','Test approval');c.refundTimeout=true;
 await c.store.db.exec('BEGIN');await c.api.refunds.command(ambiguous,randomUUID(),'submit','First attempt');await c.store.db.exec('ROLLBACK');
 const calls=c.requests.filter(r=>r.TRTYPE==='14').length;const pending=await c.api.refunds.command(ambiguous,randomUUID(),'submit','Retry after rollback');assert.equal(pending.status,'pending');assert.equal(c.requests.filter(r=>r.TRTYPE==='14').length,calls);assert.equal((await c.api.refunds.command(pending,randomUUID(),'reconcile','Ambiguous bank proof')).status,'pending');
 }finally{await c.store.close();c.cleanup();}
});
