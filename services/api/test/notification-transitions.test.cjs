const {test}=require('node:test'),assert=require('node:assert/strict'),{randomUUID}=require('node:crypto');
const{Store}=require('../dist/store'),{Marketplace}=require('../dist/marketplace'),{notifyTransition}=require('../dist/notification-transitions');
const row=(kind,status,extra={})=>({id:randomUUID(),kind,status,owner:randomUUID(),country:'KZ',version:1,created_at:new Date().toISOString(),...extra});
test('all transactional lifecycle events target their actual participants and never sealed reviews',async()=>{
 const events=[],store={db:{query:async()=>({rows:[]})},read:async()=>({country:'KZ',owner:'customer'})},notify=async(owner,country,type,target)=>events.push({owner,country,type,target});
 const scenarios=[['invite','pending','accepted','invite.accepted'],['invite','pending','declined','invite.declined'],['invite','pending','revoked','invite.revoked'],['invite','pending','expired','invite.expired'],['review','sealed','published','review.published'],['contractor','pending_review','published','contractor.approved'],['portfolio','pending_review','rejected','portfolio.rejected'],['subscription','active','expired','subscription.expired'],['subscription','active','revoked','subscription.revoked'],['refund_request','pending','confirmed','refund.confirmed'],['referral_reward','pending','available','referral.available'],['boost','active','expired','boost.expired'],['support','waiting_user','resolved','support.resolved'],['cancel_request','pending','expired','cancel_request.expired'],['amendment','pending','expired','amendment.expired']];
 for(const[kind,from,to,type]of scenarios){const before=row(kind,from,{recipient_id:randomUUID(),target_id:randomUUID(),order_id:randomUUID()});const start=events.length;await notifyTransition(store,before,{...before,status:to,version:2},notify);assert.ok(events.slice(start).some(e=>e.type===type),kind);assert.ok(events.slice(start).every(e=>e.country==='KZ'&&e.target===(kind==='invite'?before.order_id:before.id)));}
 const review=row('review','sealed');const count=events.length;await notifyTransition(store,undefined,review,notify);await notifyTransition(store,review,{...review,version:2,text:'still private'},notify);assert.equal(events.length,count);
 const draft=row('portfolio','published',{draft:{status:'pending_review'}});await notifyTransition(store,draft,{...draft,version:2,draft:{status:'rejected'}},notify);assert.equal(events.at(-1).type,'portfolio.rejected');
 await notifyTransition(store,draft,{...draft,version:2,draft:undefined},notify);assert.equal(events.at(-1).type,'portfolio.approved');
});
test('store changes atomically create an inbox notice, stream event and outbox once; rollback removes all',async()=>{
 const s=new Store('memory://'),a=new Marketplace(s);await a.initialize();
 try{
 const before=row('order','in_progress',{executor_id:randomUUID()});await s.put(before);
 const after={...before,status:'completed',version:2};await s.db.exec('BEGIN');await s.put(after);
 assert.equal((await s.all('notification')).filter(n=>n.type==='order.completed').length,2);
 await s.db.exec('ROLLBACK');assert.equal((await s.all('notification')).length,0);assert.equal((await s.all('outbox')).length,0);
 await s.put(after);await s.put(after);
 const notices=await s.all('notification'),outbox=await s.all('outbox');assert.equal(notices.length,2);assert.equal(outbox.length,2);assert.deepEqual(new Set(outbox.map(o=>o.event_id)),new Set(notices.map(n=>n.id)));
 assert.equal((await s.db.query('SELECT count(*)::int AS n FROM events')).rows[0].n,2);
 }finally{await s.close();}
});
