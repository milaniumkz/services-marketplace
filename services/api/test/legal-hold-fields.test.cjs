const {test}=require('node:test'),assert=require('node:assert/strict'),{randomUUID,randomBytes}=require('node:crypto');
const {Marketplace}=require('../dist/marketplace'),{Store}=require('../dist/store'),{totp}=require('../dist/totp');
const {holdSnapshot}=require('../dist/legal-holds'),{planFileRetention}=require('../dist/retention');
const password='Isolated field hold password!';
const row=(kind,owner,data={})=>({id:randomUUID(),kind,owner,country:'KZ',version:1,created_at:new Date().toISOString(),...data});
const call=(a,u,m,p,b={})=>a.handle(m,p,b,'Bearer '+u.access_token,randomUUID());
test('field holds freeze only selected evidence, survive profile cleanup and require explicit versioned release',async()=>{
 const a=new Marketplace(new Store('memory://'));await a.initialize();try{
 const u=await a.handle('POST','/auth/register',{country:'KZ',phone:'+77000000961',password},undefined,randomUUID()),staffUser=await a.handle('POST','/auth/register',{country:'KZ',phone:'+77000000962',password},undefined,randomUUID());
 const secret=randomBytes(20).toString('hex');await a.store.put({...await a.store.get(staffUser.user.id),staff_permissions:['privacy'],totp_secret:secret});const staff=await a.handle('POST','/auth/staff-login',{country:'KZ',phone:staffUser.user.phone,password,mfa_code:totp(secret)},undefined,randomUUID());
 const profile=row('contractor',u.user.id,{status:'published',title:'Evidence title',description:'Unrelated private description',draft:{title:'Unrelated draft'},public_location:{latitude:43,longitude:76}});await a.store.put(profile);
 const body={target_id:profile.id,fields:['title','title'],basis:'Доказательство активного обращения',reason:'Сохранить конкретный заголовок для проверки',review_at:new Date(Date.now()+86400000).toISOString()};
 await assert.rejects(()=>call(a,u,'POST','/admin/legal-holds',body),e=>e.getStatus()===403);
 const hold=await call(a,staff,'POST','/admin/legal-holds',body);assert.deepEqual(hold.fields,['title']);assert.equal(hold.field_snapshot,undefined);assert.deepEqual((await a.store.get(hold.id)).field_snapshot,{title:'Evidence title'});assert.equal(hold.target_version,1);
 const cached=await a.store.db.query("SELECT result FROM idempotency WHERE result->>'id'=$1",[hold.id]);assert.ok(cached.rows.length);assert.equal(cached.rows[0].result.field_snapshot,undefined);
 const visible=await call(a,u,'GET','/me/legal-holds');assert.equal(visible.items[0].field_snapshot,undefined);assert.equal(visible.items[0].reason,undefined);assert.equal(visible.items[0].basis,body.basis);
 await a.store.put({...profile,title:'Later title',version:2});await a.store.put(row('retention_policy','system',{status:'effective',payload:{document_days:30}}));await a.store.put(row('privacy',u.user.id,{type:'delete',status:'scheduled',execute_after:new Date(Date.now()-1000).toISOString()}));await a.maintenance(new Date());
 assert.equal((await a.store.get(profile.id)).title,undefined);assert.deepEqual((await a.store.get(hold.id)).field_snapshot,{title:'Evidence title'});
 await assert.rejects(()=>call(a,staff,'POST','/admin/legal-holds/'+hold.id+'/release',{expected_version:0,reason:'Проверка завершена, удержание снимается'}),e=>e.getStatus()===409);
 const released=await call(a,staff,'POST','/admin/legal-holds/'+hold.id+'/release',{expected_version:1,reason:'Проверка завершена, удержание снимается'});assert.equal(released.status,'released');assert.equal(released.field_snapshot,undefined);assert.equal(released.released_by,staffUser.user.id);assert.ok(released.release_reason);
 await assert.rejects(()=>holdSnapshot(a.store,profile,['draft']),e=>e.getStatus()===400);await assert.rejects(()=>holdSnapshot(a.store,profile,['phone']),e=>e.getStatus()===400);
 }finally{await a.store.close();}
});
test('frozen file references stay protected after the live field changes and an overdue review does not release evidence',async()=>{
 const store=new Store('memory://');await store.initialize();try{
 const owner=randomUUID(),file=row('upload',owner,{purpose:'avatar',status:'clean'}),target=row('user',owner,{id:owner,status:'active',avatar_id:file.id});await store.put(file);await store.put(target);
 const snapshot=await holdSnapshot(store,target,['avatar_id']);const hold=row('legal_hold','staff',{target_id:target.id,subject_user_id:owner,...snapshot,status:'active',review_at:'2020-01-01T00:00:00Z'});await store.put(hold);await store.put({...target,status:'deleted',avatar_id:null,version:2});await store.put(row('retention_policy','system',{status:'effective',payload:{document_days:30}}));
 assert.deepEqual(await planFileRetention(store,new Date()),[]);await store.put({...hold,status:'released',field_snapshot:undefined,version:2});assert.ok((await planFileRetention(store,new Date())).includes(file.id));
 await assert.rejects(()=>holdSnapshot(store,{...target,avatar_id:randomUUID()},['avatar_id']),e=>e.getStatus()===400);
 }finally{await store.close();}
});
