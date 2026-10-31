const {test}=require('node:test'),assert=require('node:assert/strict'),{randomUUID}=require('node:crypto');
const {Store}=require('../dist/store'),{minimizeClosedWork}=require('../dist/work-retention');
const row=(kind,owner,data={})=>({id:randomUUID(),kind,owner,country:'KZ',version:1,created_at:'2025-01-01T00:00:00.000Z',...data});
const now=new Date('2026-01-01T00:00:00Z'),policy=row('retention_policy','system',{payload:{chat_days:30}});
test('closed work minimizes only own expired content and revisions, keeping financial basis and shared relations',async()=>{
 const s=new Store('memory://');await s.initialize();try{
 const owner=randomUUID(),other=randomUUID(),job=row('privacy',owner),order=row('order',owner,{status:'completed',completed_at:'2025-02-01T00:00:00.000Z',executor_id:other,title:'Private title',description:'Private description',attributes:{phone:'private'},completion_note:'Private result',upload_ids:[randomUUID()],agreed_amount:12345,currency:'KZT'});await s.put(order);
 const chat=row('conversation',owner,{order_id:order.id,status:'working',members:[owner,other]}),message=row('message',owner,{thread_id:chat.id,text:'Private message',upload_ids:[randomUUID()],sequence:2}),revision=row('message_revision',owner,{message_id:message.id,text:'Private original'}),review=row('review',owner,{order_id:order.id,text:'Private review',rating:5,status:'published'}),reviewRevision=row('review_revision',owner,{review_id:review.id,text:'Original review'}),assignment=row('assignment',owner,{order_id:order.id,order_snapshot:order,offer_snapshot:{text:'Private offer'},executor_id:other}),foreignMessage=row('message',other,{thread_id:chat.id,text:'Other participant text',sequence:3}),recent=row('message',owner,{thread_id:chat.id,text:'Recent text',created_at:'2025-12-31T00:00:00.000Z'}),edited=row('message',owner,{thread_id:chat.id,text:'Recently edited',edited_at:'2025-12-31T00:00:00.000Z'});
 for(const r of [chat,message,revision,review,reviewRevision,assignment,foreignMessage,recent,edited])await s.put(r);
 const p=await minimizeClosedWork(s,job,policy,now);assert.equal(p.processed,7);assert.equal(p.remaining,2);assert.equal((await s.get(order.id)).description,undefined);assert.equal((await s.get(order.id)).agreed_amount,12345);assert.equal((await s.get(order.id)).status,'completed');assert.equal((await s.get(order.id)).executor_id,other);assert.equal((await s.get(message.id)).text,'');assert.equal((await s.get(message.id)).tombstone,true);assert.equal((await s.get(message.id)).sequence,2);assert.equal((await s.get(message.id)).thread_id,chat.id);assert.equal((await s.get(revision.id)).text,'');assert.equal((await s.get(review.id)).rating,5);assert.equal((await s.get(assignment.id)).order_snapshot,undefined);assert.deepEqual((await s.get(chat.id)).members,[owner,other]);
 for(const r of [foreignMessage,recent,edited])assert.deepEqual(await s.get(r.id),r);
 const repeat=await minimizeClosedWork(s,{...job,category_progress:{work:p}},policy,now);assert.equal(repeat.processed,7);
 }finally{await s.close();}
});
test('active work, holds, open cases, missing dates and foreign countries are retained; batches continue past protected records',async()=>{
 const s=new Store('memory://');await s.initialize();try{
 const owner=randomUUID(),job=row('privacy',owner),base={status:'completed',completed_at:'2025-02-01T00:00:00.000Z',title:'Keep evidence'};
 const held=row('order',owner,base),incident=row('order',owner,base),active=row('order',owner,{...base,status:'in_progress'}),legacy=row('order',owner,{status:'cancelled',title:'No closure time'}),foreign=row('order',owner,{...base,country:'KG'}),recent=row('order',owner,{...base,completed_at:'2025-12-31T00:00:00.000Z'});for(const r of [held,incident,active,legacy,foreign,recent])await s.put(r);
 await s.put(row('legal_hold','staff',{target_id:held.id,status:'active',fields:['title']}));await s.put(row('case','staff',{target_id:incident.id,status:'new'}));const child=row('offer',owner,{order_id:held.id,text:'Held linked offer'});await s.put(child);
 const linkedOrder=row('order',owner,base),linkedChat=row('conversation',owner,{order_id:linkedOrder.id,members:[owner]}),linkedMessage=row('message',owner,{thread_id:linkedChat.id,text:'Case message'});for(const r of [linkedOrder,linkedChat,linkedMessage])await s.put(r);await s.put(row('case','staff',{target_id:linkedMessage.id,status:'new'}));
 const safe=[];for(let i=0;i<51;i++){const r=row('order',owner,{...base,title:'Erase batch text'});await s.put(r);safe.push(r);}
 const first=await minimizeClosedWork(s,job,policy,now);assert.equal(first.processed,50);const second=await minimizeClosedWork(s,{...job,category_progress:{work:first}},policy,now);assert.equal(second.processed,51);
 for(const r of [held,incident,active,legacy,foreign,recent,child,linkedOrder,linkedChat,linkedMessage])assert.deepEqual(await s.get(r.id),r);for(const r of safe)assert.equal((await s.get(r.id)).title,undefined);
 const missing=await minimizeClosedWork(s,job,{...policy,payload:{}},now);assert.equal(missing.state,'awaiting_policy');
 }finally{await s.close();}
});
test('recent revision protects the current text and minimized records retain a technical attachment trail',async()=>{
 const s=new Store('memory://');await s.initialize();try{
 const owner=randomUUID(),job=row('privacy',owner),order=row('order',owner,{status:'completed',completed_at:'2025-02-01T00:00:00.000Z'});await s.put(order);
 const review=row('review',owner,{order_id:order.id,text:'Recently corrected',rating:5,status:'published'}),revision=row('review_revision',owner,{review_id:review.id,text:'Previous text',created_at:'2025-12-31T00:00:00.000Z'}),fileId=randomUUID(),snapshotFile=randomUUID(),assignment=row('assignment',owner,{order_id:order.id,order_snapshot:{upload_ids:[fileId],completion_upload_ids:[snapshotFile]},offer_snapshot:{text:'Private conditions'}});for(const r of [review,revision,assignment])await s.put(r);
 await minimizeClosedWork(s,job,policy,now);assert.equal((await s.get(review.id)).text,'Recently corrected');assert.equal((await s.get(revision.id)).text,'Previous text');assert.deepEqual(new Set((await s.get(assignment.id)).retention_file_ids),new Set([fileId,snapshotFile]));assert.equal((await s.get(assignment.id)).order_snapshot,undefined);
 }finally{await s.close();}
});
