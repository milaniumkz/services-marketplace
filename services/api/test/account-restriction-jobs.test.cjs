const {test}=require('node:test'),assert=require('node:assert/strict'),{randomUUID,randomBytes}=require('node:crypto');
const {Marketplace}=require('../dist/marketplace'),{Store}=require('../dist/store'),{totp}=require('../dist/totp');
const password='Isolated bulk test password';
const register=(a,n,country='KZ')=>a.handle('POST','/auth/register',{country,phone:country==='KZ'?'+77000000'+n:'+38160123'+n,password},undefined,randomUUID(),{},'bulk-register-'+n);
const call=(a,u,m,p,b={},key=randomUUID())=>a.handle(m,p,b,'Bearer '+u.access_token,key,{},'bulk-tests');
async function staff(a,n,permissions=['bulk_restrict'],country='KZ'){const u=await register(a,n,country),r=await a.store.get(u.user.id),secret=randomBytes(20).toString('hex');await a.store.put({...r,totp_secret:secret,staff_permissions:permissions});return a.handle('POST','/auth/staff-login',{country,phone:r.phone,password,mfa_code:totp(secret)},undefined,undefined,{},'bulk-staff-'+n);}
const row=(kind,owner,extra={})=>({id:randomUUID(),kind,owner,country:'KZ',version:1,created_at:new Date().toISOString(),...extra});
async function fixture(fn){const a=new Marketplace(new Store('memory://'));await a.initialize();try{await fn(a);}finally{await a.store.close();}}
async function incident(a,u){const r=row('case',randomUUID(),{subject_user_id:u.user.id,target_type:'user',target_id:u.user.id,status:'new',reporter_private:true,description:'Изолированное дело другого автора'});await a.store.put(r);return r;}
const request=selection=>({selection,ends_at:new Date(Date.now()+3600000).toISOString(),reason:'Внутреннее основание ручной проверки группы аккаунтов'});
test('bulk account restrictions require an explicit permission, regional MFA and independent approval; stale records are skipped and accepted work remains available',()=>fixture(async a=>{
 const author=await staff(a,'871'),reviewer=await staff(a,'872'),admin=await staff(a,'873',['administrator']),foreign=await staff(a,'874',['bulk_restrict'],'RS'),u=await register(a,'875'),v=await register(a,'876');
 const c=await incident(a,u),d=await incident(a,v),body=request([{user_id:u.user.id,case_id:c.id},{user_id:v.user.id,case_id:d.id}]);
 await assert.rejects(()=>call(a,admin,'POST','/admin/account-restriction-jobs/preview',body),e=>e.getStatus()===403);
 await assert.rejects(()=>call(a,u,'POST','/admin/account-restriction-jobs/preview',body),e=>e.getStatus()===403);
 const job=await call(a,author,'POST','/admin/account-restriction-jobs/preview',body);assert.equal(job.eligible_count,2);assert.equal((await a.store.get(u.user.id)).status,'active');
 await assert.rejects(()=>call(a,foreign,'GET','/admin/account-restriction-jobs/'+job.id),e=>e.getStatus()===404);
 const command={expected_version:job.version,confirm:true,reason:'Независимая проверка последствий ограничения'};
 await assert.rejects(()=>call(a,author,'POST','/admin/account-restriction-jobs/'+job.id+'/execute',command),e=>e.getStatus()===403);
 const changed=await a.store.get(v.user.id);await a.store.put({...changed,display_name:'Изменённая версия',version:changed.version+1});
 const key=randomUUID(),result=await call(a,reviewer,'POST','/admin/account-restriction-jobs/'+job.id+'/execute',command,key);assert.equal(result.results[0].status,'applied');assert.equal(result.results[1].code,'STATE_CONFLICT');
 await call(a,reviewer,'POST','/admin/account-restriction-jobs/'+job.id+'/execute',command,key);assert.equal((await a.store.all('blacklist','KZ')).length,1);assert.equal((await a.store.get(v.user.id)).status,'active');
 const restrictions=await call(a,u,'GET','/me/restrictions');assert.equal(restrictions.items[0].can_appeal,true);assert.notEqual(restrictions.items[0].case_id,c.id);
 const notice=await call(a,u,'GET','/cases/'+restrictions.items[0].case_id);assert.equal(notice.owner,u.user.id);assert.equal(JSON.stringify(notice).includes(body.reason),false);assert.equal(JSON.stringify(notice).includes(c.id),false);
 const work=row('order',v.user.id,{executor_id:u.user.id,status:'assigned',title:'Текущая работа'});await a.store.put(work);assert.equal((await call(a,u,'POST','/orders/'+work.id+'/start',{expected_version:1})).status,'in_progress');
 assert.equal((await call(a,u,'POST','/support/threads',{subject:'Объяснение ограничения',topic:'account'})).status,'new');
 assert.equal((await call(a,u,'GET','/me/privacy-requests')).items.length,0);
 await a.maintenance(new Date(Date.now()+2*3600000));assert.equal((await a.store.get(u.user.id)).status,'active');
}));
test('bulk restriction preview rejects unrelated cases, protects staff and expired snapshots, and cancellation creates no sanctions',()=>fixture(async a=>{
 const author=await staff(a,'877'),reviewer=await staff(a,'878'),u=await register(a,'879'),v=await register(a,'880');const c=await incident(a,u);
 const mismatch=await call(a,author,'POST','/admin/account-restriction-jobs/preview',request([{user_id:v.user.id,case_id:c.id},{user_id:author.user.id,case_id:c.id}]));assert.equal(mismatch.eligible_count,0);assert.equal(mismatch.snapshot[0].code,'CASE_NOT_ELIGIBLE');
 const j=await call(a,author,'POST','/admin/account-restriction-jobs/preview',request([{user_id:u.user.id,case_id:c.id}]));await a.store.put({...j,expires_at:new Date(Date.now()-1000).toISOString()});await assert.rejects(()=>call(a,reviewer,'POST','/admin/account-restriction-jobs/'+j.id+'/execute',{expected_version:j.version,confirm:true,reason:'Истёкший снимок не должен применяться'}),e=>e.getStatus()===409);
 const fresh=await call(a,author,'POST','/admin/account-restriction-jobs/preview',request([{user_id:u.user.id,case_id:c.id}]));assert.equal((await call(a,reviewer,'POST','/admin/account-restriction-jobs/'+fresh.id+'/cancel',{expected_version:fresh.version,reason:'Отменяю выборку после отдельной проверки'})).status,'canceled');assert.equal((await a.store.all('blacklist')).length,0);
}));
