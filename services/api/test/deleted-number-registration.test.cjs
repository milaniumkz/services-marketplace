const {test}=require('node:test'),assert=require('node:assert/strict'),{randomUUID}=require('node:crypto');
const {Marketplace}=require('../dist/marketplace'),{Store}=require('../dist/store');
test('deleted phone can register a fresh identity without reviving old credentials, data or entitlements; live, blocked and banned accounts stay protected',async()=>{
 const api=new Marketplace(new Store('memory://'));await api.initialize();try{
 const register=(phone,password,extra={})=>api.handle('POST','/auth/register',{country:'KZ',phone,password,...extra},undefined,undefined,{},'isolated-register-'+randomUUID());
 const old=await register('+77000000981','Original secret 981'),oldId=old.user.id;
 const owner=await register('+77000000982','Owner secret 982');await api.store.put({...await api.store.get(owner.user.id),staff_permissions:['platform_owner']});
 const staff=await api.handle('POST','/auth/staff-login',{country:'KZ',phone:owner.user.phone,password:'Owner secret 982'});
 const call=(account,m,p,b={})=>api.handle(m,p,b,'Bearer '+account.access_token,randomUUID());
 const row=(kind,fields)=>({id:randomUUID(),kind,owner:oldId,country:'KZ',version:1,created_at:new Date().toISOString(),...fields});
 await api.store.put({...await api.store.get(oldId),verification:'passed',city:'Караганда',display_name:'Прежняя анкета'});
 const grant=row('grant',{valid_until:new Date(Date.now()+86400000).toISOString(),capabilities:['view_contractors','publish_order'],plan:'customer',role:'customer'}),document=row('upload',{purpose:'verification',status:'clean'}),portfolio=row('portfolio',{status:'published',description:'Прежние работы'});
 for(const r of [grant,document,portfolio])await api.store.put(r);
 await assert.rejects(()=>register(old.user.phone,'New secret 981'),e=>e.getStatus()===409);
 const before=await api.store.get(oldId);await call(staff,'POST','/admin/users/'+oldId+'/delete',{expected_version:before.version});
 const deleted=await api.store.get(oldId),job=await api.store.get(deleted.deletion_request_id);
 assert.equal(deleted.status,'deleted');assert.equal(job.type,'delete');
 await assert.rejects(()=>register(old.user.phone,'x'),e=>e.getStatus()===400);assert.equal((await api.store.db.query('SELECT user_id FROM credentials WHERE phone=$1',[old.user.phone])).rows[0].user_id,oldId);
 await assert.rejects(()=>register(old.user.phone,'Valid new secret',{locale:'zz'}),e=>e.getStatus()===400);assert.equal((await api.store.db.query('SELECT user_id FROM credentials WHERE phone=$1',[old.user.phone])).rows[0].user_id,oldId);assert.equal((await api.store.get(oldId)).phone,old.user.phone);
 const fresh=await register(old.user.phone,'Brand new secret 981');assert.notEqual(fresh.user.id,oldId);assert.equal(fresh.user.verification,'not_started');assert.equal(fresh.user.city,'');assert.equal(fresh.user.display_name,'');assert.deepEqual(fresh.user.roles,['customer']);
 assert.equal((await api.store.get(oldId)).status,'deleted');assert.equal((await api.store.get(oldId)).phone,null);assert.equal((await api.store.get(job.id)).status,job.status);assert.equal((await api.store.get(grant.id)).owner,oldId);
 assert.equal((await call(fresh,'GET','/me/subscriptions')).items.length,0);assert.equal((await call(fresh,'GET','/me/portfolio-projects')).items.length,0);
 await assert.rejects(()=>call(fresh,'GET','/uploads/'+document.id),e=>[403,404].includes(e.getStatus()));
 await assert.rejects(()=>api.handle('POST','/auth/login',{country:'KZ',phone:old.user.phone,password:'Original secret 981'}),e=>e.getStatus()===401);
 await assert.rejects(()=>api.handle('POST','/auth/refresh',{refresh_token:old.refresh_token}),e=>e.getStatus()===401);
 // The old deletion job must not delete credentials belonging to the newly registered account.
 await api.store.put(row('retention_policy',{status:'effective',payload:{logs_days:30,security_days:30}}));
 await api.store.put(row('runtime_settings',{status:'effective',payload:{deletion_grace_hours:0}}));
 const now=new Date();await api.maintenance(now);await api.maintenance(new Date(now.getTime()+1000));
 assert.equal((await api.store.get(oldId)).phone,null);assert.equal((await api.store.get(fresh.user.id)).status,'active');
 const logged=await api.handle('POST','/auth/login',{country:'KZ',phone:old.user.phone,password:'Brand new secret 981'});assert.equal(logged.user.id,fresh.user.id);
 await assert.rejects(()=>register(old.user.phone,'Another secret 981'),e=>e.getStatus()===409);
 const current=await api.store.get(fresh.user.id);await call(staff,'POST','/admin/users/'+current.id+'/block',{expected_version:current.version});await assert.rejects(()=>register(old.user.phone,'Another secret 981'),e=>e.getStatus()===409);
 const blocked=await api.store.get(current.id);await call(staff,'POST','/admin/users/'+current.id+'/delete',{expected_version:blocked.version});
 await api.store.put({...row('blacklist',{user_id:current.id,status:'active'}),owner:current.id});
 await assert.rejects(()=>register(old.user.phone,'Ban bypass secret'),e=>e.getStatus()===409);
 assert.equal((await api.store.db.query('SELECT user_id FROM credentials WHERE phone=$1',[old.user.phone])).rows[0].user_id,current.id);
 assert.equal((await api.store.all('audit','KZ')).filter(r=>r.action==='user.deleted_number_released').length,1);
 }finally{await api.store.close();}
});
