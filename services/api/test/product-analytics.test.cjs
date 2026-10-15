const {test}=require('node:test');
const assert=require('node:assert/strict');
const {randomUUID}=require('node:crypto');
const {Store}=require('../dist/store');
const {productAnalytics}=require('../dist/product-analytics');
test('product funnel uses the regional publication cohort, distinct participant feedback and honest empty rates',async()=>{
 const store=new Store('memory://');await store.initialize();
 const now=new Date('2026-10-15T12:00:00Z'),owner=randomUUID(),executor=randomUUID();
 const put=(kind,extra={})=>store.put({id:randomUUID(),kind,owner,country:'KZ',version:1,created_at:'2026-10-13T10:00:00Z',...extra},{skipContentCheck:true});
 try{
  const first=await put('order',{published_at:'2026-10-13T10:00:00Z',status:'completed',executor_id:executor,completed_at:'2026-10-14T10:00:00Z'});
  await put('order',{published_at:'2026-10-15T10:00:00Z',status:'open'});
  await put('order',{published_at:'2026-08-01T10:00:00Z',status:'completed'});
  await put('order',{country:'BY',published_at:'2026-10-13T10:00:00Z',status:'open'});
  await put('order',{published_at:'2026-10-16T10:00:00Z',status:'open'});
  await put('offer',{order_id:first.id,status:'withdrawn'});await put('offer',{owner:randomUUID(),order_id:first.id,status:'active'});
  await put('case',{target_type:'order',target_id:first.id,status:'resolved'});
  await put('review',{order_id:first.id,status:'published',rating:5});
  const other=await put('review',{order_id:first.id,owner:executor,status:'sealed',rating:4});
  const before=await productAnalytics(store,'KZ',7,now);assert.equal(before.funnel.mutual_review,0);
  await store.put({...other,status:'published'});
  const result=await productAnalytics(store,'KZ',7,now);
  assert.deepEqual(result.funnel,{published:2,with_offer:1,selected:1,completed:1,with_case:1,mutual_review:1});assert.equal(result.rates.selection,.5);assert.equal(result.series.length,7);
  assert.equal(JSON.stringify(result).includes(owner),false);
  const empty=await productAnalytics(store,'RS',7,now);assert.equal(empty.rates.completion,null);assert.equal(empty.funnel.published,0);
 }finally{await store.close();}
});
