const {test}=require('node:test'),assert=require('node:assert/strict'),{randomUUID}=require('node:crypto');
const {Store}=require('../dist/store'),{Marketplace}=require('../dist/marketplace');
const password='Isolated credential password!';
async function fixture(run){const a=new Marketplace(new Store('memory://'));await a.initialize();try{await run(a);}finally{await a.store.close();}}
const register=(a,phone)=>a.handle('POST','/auth/register',{country:'KZ',phone,password},undefined,randomUUID(),{},'credentials-register');
const login=(a,phone,secret=password)=>a.handle('POST','/auth/login',{country:'KZ',phone,password:secret},undefined,undefined,{},'credentials-login');
const call=(a,u,m,p,b={})=>a.handle(m,p,b,'Bearer '+u.access_token,randomUUID(),{},'credential-change');
test('password change rejects invalid input, preserves current session and invalidates other access/refresh and old password',()=>fixture(async a=>{
 const phone='+77000000633',u=await register(a,phone),remote=await login(a,phone),other=await register(a,'+77000000634');
 for(const body of [{current_password:'Wrong password',new_password:'New valid password!'}, {current_password:password,new_password:'short'}, {current_password:password,new_password:'x'.repeat(129)}])await assert.rejects(()=>call(a,u,'POST','/me/password/change',body),e=>[400,401].includes(e.getStatus()));
 assert.equal((await call(a,remote,'GET','/me')).id,u.user.id);
 const secret='Test6!';await call(a,u,'POST','/me/password/change',{current_password:password,new_password:secret});
 assert.equal((await call(a,u,'GET','/me')).id,u.user.id);assert.equal((await call(a,other,'GET','/me')).id,other.user.id);
 await assert.rejects(()=>call(a,remote,'GET','/me'),e=>e.getStatus()===401);
 await assert.rejects(()=>a.handle('POST','/auth/refresh',{refresh_token:remote.refresh_token}),e=>e.getStatus()===401);
 await assert.rejects(()=>login(a,phone),e=>e.getStatus()===401);
 assert.equal((await login(a,phone,secret)).user.id,u.user.id);
 const events=(await a.store.all('security_event','KZ')).filter(r=>r.event==='password.changed'&&r.owner===u.user.id);assert.equal(events.length,1);assert(!JSON.stringify(events).includes(secret));
}));
test('phone change preserves account and current session, rejects wrong region/collision and invalidates previous identifier',()=>fixture(async a=>{
 const old='+77000000635',next='+77000000637',u=await register(a,old),remote=await login(a,old),other=await register(a,'+77000000636');
 for(const new_phone of ['not-a-number','+996555123456',other.user.phone])await assert.rejects(()=>call(a,u,'POST','/me/phone-change-requests',{current_password:password,new_phone}),e=>[400,409].includes(e.getStatus()));
 const result=await call(a,u,'POST','/me/phone-change-requests',{current_password:password,new_phone:next});assert.equal(result.phone,next);assert.equal(result.phone_status,'unverified');assert.equal(result.version,(await call(a,u,'GET','/me')).version);
 assert.equal((await call(a,u,'GET','/me')).phone,next);assert.equal((await call(a,u,'GET','/me')).id,u.user.id);
 await assert.rejects(()=>call(a,remote,'GET','/me'),e=>e.getStatus()===401);
 await assert.rejects(()=>a.handle('POST','/auth/refresh',{refresh_token:remote.refresh_token}),e=>e.getStatus()===401);
 await assert.rejects(()=>login(a,old),e=>e.getStatus()===401);assert.equal((await login(a,next)).user.id,u.user.id);
 assert.equal((await call(a,other,'GET','/me')).id,other.user.id);
}));
test('regional password policy is available to the current account and enforced again after a policy change',()=>fixture(async a=>{
 const u=await register(a,'+77000000641');
 assert.deepEqual(await call(a,u,'GET','/me/security-policy'),{password_min:6,password_max:128});
 const config={id:randomUUID(),kind:'runtime_settings',country:'KZ',owner:u.user.id,status:'effective',payload:{password_min:20},version:1,created_at:new Date().toISOString()};await a.store.put(config);
 assert.deepEqual(await call(a,u,'GET','/me/security-policy'),{password_min:20,password_max:128});
 await assert.rejects(()=>call(a,u,'POST','/me/password/change',{current_password:password,new_password:'x'.repeat(19)}),e=>e.getStatus()===400&&e.getResponse().error.details.min_length===20);
 await a.store.put({...config,payload:{password_min:25},version:2});
 await assert.rejects(()=>call(a,u,'POST','/me/password/change',{current_password:password,new_password:'x'.repeat(20)}),e=>e.getResponse().error.message.includes('25'));
 await call(a,u,'POST','/me/password/change',{current_password:password,new_password:'x'.repeat(25)});
 assert.equal((await call(a,u,'GET','/me')).id,u.user.id);
}));

test('owner password migration applies six once and preserves later admin policy changes',()=>fixture(async a=>{
 const {readFileSync}=require('node:fs'),{resolve}=require('node:path');
 const {readSettings,validateSettings}=require('../dist/settings');
 validateSettings({password_min:6});assert.throws(()=>validateSettings({password_min:5}));
 const config={id:randomUUID(),kind:'runtime_settings',country:'KZ',owner:randomUUID(),status:'effective',payload:{password_min:15,access_seconds:900},version:1,created_at:new Date().toISOString()};await a.store.put(config);
 await a.store.db.query("DELETE FROM joba_data_migrations WHERE name=$1",['owner-password-minimum-6-2026-10-20']);
 const sql=readFileSync(resolve(__dirname,'../migrations/0012_password_minimum.up.sql'),'utf8');
 await a.store.db.exec(sql);assert.equal((await readSettings(a.store,'KZ')).password_min,6);
 const updated=await a.store.get(config.id);assert.equal(updated.version,2);assert.equal(updated.payload.access_seconds,900);
 await a.store.put({...updated,payload:{...updated.payload,password_min:10},version:3});await a.store.db.exec(sql);
 assert.equal((await readSettings(a.store,'KZ')).password_min,10);
}));
