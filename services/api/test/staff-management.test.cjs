const {test}=require('node:test'),assert=require('node:assert/strict'),{randomUUID}=require('node:crypto');
const {Marketplace}=require('../dist/marketplace'),{Store}=require('../dist/store');
test('owner edits, blocks and deletes staff and roles; revocation is immediate, country scoped, versioned and passwords stay private',async()=>{
 const a=new Marketplace(new Store('memory://'));await a.initialize();try{
 const secret='Isolated owner password!',owner=await a.handle('POST','/auth/register',{country:'KZ',phone:'+77000000781',password:secret});
 await a.store.put({...await a.store.get(owner.user.id),staff_permissions:['platform_owner']});
 const boss=await a.handle('POST','/auth/staff-login',{country:'KZ',phone:owner.user.phone,password:secret});
 const call=(token,m,p,b={})=>a.handle(m,p,b,'Bearer '+token,randomUUID()),own=(m,p,b)=>call(boss.access_token,m,p,b);
 const role=await own('POST','/admin/access/roles',{title:'Оператор теста управления',grants:['GET /admin/users']});
 let employee=await own('POST','/admin/access/staff',{display_name:'Тест управления',login:'Test.Operator',password:'Pass12',role_ids:[role.id]});assert.equal(employee.identifier,'test.operator');
 const login=(phone='TEST.OPERATOR',password='Pass12')=>a.handle('POST','/auth/staff-login',{country:'KZ',phone,password});
 const session=await login();await call(session.access_token,'GET','/admin/users');
 await assert.rejects(()=>call(session.access_token,'DELETE','/admin/access/roles/'+role.id,{expected_version:1}),e=>e.getStatus()===403);
 await assert.rejects(()=>own('PATCH','/admin/access/staff/'+employee.id,{expected_version:0,display_name:'Ошибка версии'}),e=>e.getStatus()===409);
 await own('PATCH','/admin/access/staff/'+employee.id,{expected_version:employee.version,display_name:'Изменённый сотрудник',login:'New.Operator',password:'New456',role_ids:[role.id]});
 await assert.rejects(()=>call(session.access_token,'GET','/admin/users'),e=>e.getStatus()===401);
 await assert.rejects(()=>login(),e=>e.getStatus()===401);
 const updated=await login('NEW.OPERATOR','New456');
 let r=await own('POST','/admin/access/roles/'+role.id+'/block',{expected_version:role.version});assert.equal(r.status,'blocked');
 await assert.rejects(()=>call(updated.access_token,'GET','/admin/users'),e=>e.getStatus()===403);
 r=await own('PATCH','/admin/access/roles/'+role.id,{expected_version:r.version,title:'Новое название роли',grants:['GET /admin/users']});assert.equal(r.status,'blocked');
 r=await own('POST','/admin/access/roles/'+role.id+'/unblock',{expected_version:r.version});await call(updated.access_token,'GET','/admin/users');
 employee=(await own('GET','/admin/access/staff')).items.find(u=>u.id===employee.id);assert.equal(employee.display_name,'Изменённый сотрудник');assert.equal(employee.identifier,'new.operator');
 let changed=await own('POST','/admin/access/staff/'+employee.id+'/block',{expected_version:employee.version});assert.equal(changed.status,'blocked');
 await assert.rejects(()=>call(updated.access_token,'GET','/admin/users'),e=>[401,403].includes(e.getStatus()));
 await assert.rejects(()=>login('new.operator','New456'),e=>[401,403].includes(e.getStatus()));
 changed=await own('POST','/admin/access/staff/'+employee.id+'/unblock',{expected_version:changed.version});
 await assert.rejects(()=>call(updated.access_token,'GET','/admin/users'),e=>e.getStatus()===401);
 const resumed=await login('new.operator','New456');await call(resumed.access_token,'GET','/admin/users');
 const foreign={...r,id:randomUUID(),country:'KG'};await a.store.put(foreign);
 await assert.rejects(()=>own('DELETE','/admin/access/roles/'+foreign.id,{expected_version:foreign.version}),e=>e.getStatus()===404);
 await own('DELETE','/admin/access/roles/'+r.id,{expected_version:r.version});assert.ok(!(await own('GET','/admin/access/roles')).items.some(x=>x.id===r.id));assert.ok(!(await a.store.get(employee.id)).staff_role_ids.includes(r.id));
 await assert.rejects(()=>call(resumed.access_token,'GET','/admin/users'),e=>e.getStatus()===403);
 const current=await a.store.get(employee.id);await own('DELETE','/admin/access/staff/'+employee.id,{expected_version:current.version});assert.ok(!(await own('GET','/admin/access/staff')).items.some(x=>x.id===employee.id));assert.equal((await a.store.db.query('SELECT user_id FROM credentials WHERE user_id=$1',[employee.id])).rows.length,0);
 const ownerRow=await a.store.get(owner.user.id);for(const [m,suffix] of [['DELETE',''],['PATCH',''],['POST','/block']])await assert.rejects(()=>own(m,'/admin/access/staff/'+owner.user.id+suffix,{expected_version:ownerRow.version}),e=>e.getStatus()===403);
 const audit=JSON.stringify(await a.store.all('audit','KZ'));assert.equal(audit.includes('New456'),false);assert.equal(audit.includes('Pass12'),false);
 }finally{await a.store.close();}
});

test('case-insensitive staff sign-in shares the same account attempt limit across spelling variants and IPs',async()=>{
 const a=new Marketplace(new Store('memory://'));await a.initialize();try{
 for(let i=0;i<10;i++)await assert.rejects(()=>a.handle('POST','/auth/staff-login',{country:'KZ',phone:i%2?' TEST.Operator ':'test.OPERATOR',password:'wrong-password'},undefined,undefined,{},'staff-case-'+i),e=>e.getStatus()===401);
 await assert.rejects(()=>a.handle('POST','/auth/staff-login',{country:'KZ',phone:'Test.Operator',password:'wrong-password'},undefined,undefined,{},'another-staff-ip'),e=>e.getStatus()===429);
 }finally{await a.store.close();}
});
