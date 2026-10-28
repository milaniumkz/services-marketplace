const{test}=require('node:test'),assert=require('node:assert/strict'),{randomUUID}=require('node:crypto');
const{Marketplace}=require('../dist/marketplace'),{Store}=require('../dist/store');
test('owner creates a password employee with regional dynamic roles, safe audit, retries and exact access',async()=>{
 const a=new Marketplace(new Store('memory://'));await a.initialize();try{
  const pwd='Owner isolated password',reg=phone=>a.handle('POST','/auth/register',{country:'KZ',phone,password:pwd},undefined,undefined,{},phone);
  const owner=await reg('+77000000961'),customer=await reg('+77000000962');
  await a.store.put({...await a.store.get(owner.user.id),staff_permissions:['platform_owner','administrator']});
  const boss=await a.handle('POST','/auth/staff-login',{country:'KZ',phone:owner.user.phone,password:pwd});
  const call=(token,method,path,body={},key=randomUUID())=>a.handle(method,path,body,'Bearer '+token,key);
  const role=await call(boss.access_token,'POST','/admin/access/roles',{title:'Наблюдатель аккаунтов',grants:['GET /admin/users','GET /admin/users/{id}']});
  const body={display_name:'Новый сотрудник',login:'observer.test',password:'Pass12',role_ids:[role.id]},key=randomUUID();
  const created=await call(boss.access_token,'POST','/admin/access/staff',body,key);
  assert.equal(created.identifier,'observer.test');assert.deepEqual(await call(boss.access_token,'POST','/admin/access/staff',body,key),created);
  assert.equal(JSON.stringify(created).includes('Pass12'),false);assert.equal(created.managed,true);
  assert.equal((await a.store.db.query('SELECT count(*)::int n FROM credentials WHERE country=$1 AND phone=$2',['KZ','observer.test'])).rows[0].n,1);
  assert.equal(JSON.stringify(await a.store.all('audit','KZ')).includes('Pass12'),false);
  await assert.rejects(()=>call(boss.access_token,'POST','/admin/access/staff',body),e=>e.getStatus()===409);
  await assert.rejects(()=>call(customer.access_token,'POST','/admin/access/staff',{...body,login:'forbidden'}),e=>e.getStatus()===403);
  const employee=await a.handle('POST','/auth/staff-login',{country:'KZ',phone:'observer.test',password:'Pass12'});
  assert.ok((await call(employee.access_token,'GET','/admin/users')).items.some(u=>u.id===customer.user.id));
  await assert.rejects(()=>a.handle('GET','/admin/users/'+customer.user.id,{},'Bearer '+employee.access_token,undefined,{include_phone:'true'}),e=>[403,404].includes(e.getStatus()));
  await assert.rejects(()=>call(employee.access_token,'POST','/admin/access/staff',{...body,login:'escalation'}),e=>e.getStatus()===403);
  await assert.rejects(()=>call(employee.access_token,'GET','/admin/access/roles'),e=>e.getStatus()===403);
  for(const bad of [{password:'short'},{role_ids:[]},{role_ids:[randomUUID()]},{login:'Наблюдатель'}])await assert.rejects(()=>call(boss.access_token,'POST','/admin/access/staff',{...body,login:'another.valid',...bad}),e=>e.getStatus()===422);
  await call(boss.access_token,'PUT','/admin/access/staff/'+created.id+'/roles',{expected_version:created.version,role_ids:[]});
  await assert.rejects(()=>call(employee.access_token,'GET','/admin/users'),e=>e.getStatus()===403);
 }finally{await a.store.close();}
});
