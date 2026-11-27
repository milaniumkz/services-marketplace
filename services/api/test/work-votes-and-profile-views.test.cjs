const {test}=require('node:test'),assert=require('node:assert/strict'),{randomUUID}=require('node:crypto');
const {Marketplace}=require('../dist/marketplace'),{Store}=require('../dist/store');
const {recordProfileView,eraseProfileViews}=require('../dist/listing-reactions');
const {exportSnapshot}=require('../dist/privacy-export');
const call=(a,u,method,path,body={},q={})=>a.handle(method,path,body,u?'Bearer '+u.access_token:undefined,randomUUID(),q);
async function fixture(){
 const a=new Marketplace(new Store('memory://'));await a.initialize();let n=0;
 const register=country=>a.handle('POST','/auth/register',{country:country||'KZ',phone:'+77000000'+String(700+n++).padStart(3,'0'),password:'Isolated reaction account password!'},undefined,randomUUID());
 const customer=await register(),worker=await register(),stranger=await register();
 await a.store.put({...await a.store.get(worker.user.id),roles:['executor'],active_role:'executor'});
 const now=new Date().toISOString(),profile={id:randomUUID(),kind:'contractor',owner:worker.user.id,country:'KZ',version:1,created_at:now,published_at:now,status:'published',title:'Ремонт квартиры',city:'Алматы'};
 const job={id:randomUUID(),kind:'order',owner:customer.user.id,country:'KZ',version:1,created_at:now,published_at:now,status:'open',expires_at:new Date(Date.now()+86400000).toISOString(),title:'Работа заказчика',city:'Алматы'};
 await a.store.put(profile,{skipContentCheck:true});await a.store.put(job,{skipContentCheck:true});
 const work=(status='completed',country='KZ')=>({id:randomUUID(),kind:'order',owner:customer.user.id,country,version:1,created_at:now,status,completed_at:now,executor_id:worker.user.id});
 return {a,customer,worker,stranger,profile,job,work,register};
}
test('only finished real counterparties can react; one current vote, old stranger votes ignored and withdrawal stays free',async()=>{
 const {a,customer,worker,stranger,profile,job,work}=await fixture();try{
 const path='/listing-votes/services/'+profile.id;
 const reject=u=>assert.rejects(()=>call(a,u,'PUT',path,{value:-1}),e=>e.getResponse().error.code==='COMPLETED_WORK_REQUIRED');
 await reject(customer);await reject(stranger);
 for(const status of ['assigned','completion_requested','canceled']){await a.store.put(work(status),{skipContentCheck:true});await reject(customer);}
 await a.store.put(work('completed','RU'),{skipContentCheck:true});await reject(customer);
 // An unrelated finished order also cannot unlock reactions to this specialist.
 await a.store.put({...work(),owner:stranger.user.id,executor_id:customer.user.id},{skipContentCheck:true});await reject(customer);
 await a.store.put(work(),{skipContentCheck:true});
 await call(a,customer,'PUT',path,{value:1});await call(a,customer,'PUT',path,{value:1});
 assert.equal((await a.store.db.query('SELECT * FROM votes WHERE voter=$1 AND target=$2',[customer.user.id,profile.id])).rows.length,1);
 await call(a,customer,'PUT',path,{value:-1});assert.equal((await a.store.db.query('SELECT value FROM votes WHERE voter=$1 AND target=$2',[customer.user.id,profile.id])).rows[0].value,-1);
 await call(a,customer,'PUT',path,{value:1});
 // Simulate historical votes created before the eligibility rule.
 await a.store.db.query('INSERT INTO votes(voter,target,value) VALUES($1,$2,-1)',[stranger.user.id,profile.id]);
 let top=await call(a,customer,'GET','/top-listings');const row=top.items.find(x=>x.id===profile.id);assert.equal(row.likes,1);assert.equal(row.dislikes,0);assert.equal(row.can_vote,true);assert.equal(row.my_vote,1);
 const strangerTop=await call(a,stranger,'GET','/top-listings');const other=strangerTop.items.find(x=>x.id===profile.id);assert.equal(other.can_vote,false);assert.equal(other.my_vote,null);assert.equal(other.dislikes,0);
 await assert.rejects(()=>call(a,worker,'PUT',path,{value:1}),e=>e.getStatus()===403);
 await call(a,worker,'PUT','/listing-votes/orders/'+job.id,{value:1});
 assert.equal((await a.store.get(profile.id)).status,'published');assert.equal((await a.store.get(profile.id)).version,1);
 await a.store.put({...profile,status:'paused',version:2});await call(a,customer,'DELETE',path);assert.equal((await a.store.db.query('SELECT * FROM votes WHERE voter=$1 AND target=$2',[customer.user.id,profile.id])).rows.length,0);
 }finally{await a.store.close();}
});
test('profile views count only unique allowed people, never self, staff, catalog loads or blocked visits; no editable version churn',async()=>{
 const {a,customer,worker,stranger,profile}=await fixture();try{
 const path='/contractors/'+profile.id;
 await call(a,customer,'GET','/contractors');await call(a,undefined,'GET','/public/contractors',{}, {country:'KZ'});assert.equal((await a.store.all('profile_view','KZ')).length,0);
 await assert.rejects(()=>call(a,undefined,'GET',path),e=>e.getStatus()===401);
 const one=await call(a,customer,'GET',path);assert.equal(one.profile_views,1);assert.equal(JSON.stringify(one).includes(customer.user.id),false);
 const twice=await Promise.all([call(a,customer,'GET',path),call(a,customer,'GET',path)]);assert.ok(twice.every(r=>r.profile_views===1));
 assert.equal((await call(a,worker,'GET',path)).profile_views,1);
 const staff={...await a.store.get(stranger.user.id),staff_permissions:['platform_owner']};await recordProfileView(a.store,staff,profile);assert.equal((await a.store.all('profile_view','KZ')).length,1);
 await a.store.put({id:randomUUID(),kind:'pair_block',owner:worker.user.id,country:'KZ',version:1,created_at:new Date().toISOString(),status:'active',target_id:stranger.user.id});await assert.rejects(()=>call(a,stranger,'GET',path),e=>e.getStatus()===404);
 const overview=await call(a,worker,'GET','/me/overview');assert.equal(overview.contractor.profile_views,1);assert.equal((await a.store.get(profile.id)).version,1);
 const exported=await exportSnapshot(a.store,customer.user.id,'KZ');assert.equal(exported.data.profile_view.length,1);assert.equal(exported.data.profile_view[0].target_id,profile.id);assert.equal((await exportSnapshot(a.store,worker.user.id,'KZ')).data.profile_view.length,0);
 await eraseProfileViews(a.store,customer.user.id,'KZ');assert.equal((await call(a,worker,'GET',path)).profile_views,0);
 }finally{await a.store.close();}
});
