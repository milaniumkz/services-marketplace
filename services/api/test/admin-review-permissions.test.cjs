const {test}=require('node:test'),assert=require('node:assert/strict');
test('read-only identity reviewer can open authorized documents without acquiring decision rights',async()=>{
 const {reviewWorkspace}=await import('../../../apps/admin/review-workspace.js');
 const {assertStaffOperation}=require('../dist/staff-access');
 const employee={staff_access_mode:'managed',status:'active',staff_grants:['GET /admin/verifications/{id}','sensitive.identity']};
 assert.throws(()=>assertStaffOperation(employee,true,'GET','/admin/verifications/owned',{}, {include_phone:'true'}),e=>e.getStatus()===403);
 assert.doesNotThrow(()=>assertStaffOperation({...employee,staff_grants:[...employee.staff_grants,'sensitive.phone']},true,'GET','/admin/verifications/owned',{}, {include_phone:'true'}));
 const render=async grants=>(await reviewWorkspace({key:'record-live/verification/owned',api:async()=>({id:'owned',status:'pending_review',version:1,document_revision:1}),esc:v=>String(v??''),card:(t,b)=>`<section><h2>${t}</h2>${b}</section>`,note:s=>`<p>${s}</p>`,namedField:()=>'',sections:{verification:['verifications','Документы']},onRefresh:async()=>{},staffAccess:{managed:true,grants}})).body();
 const read=await render(['GET /admin/verifications/{id}','sensitive.identity']);assert.match(read,/<form id="sensitive-read"[^>]*data-staff-read/);assert.match(read,/<button class="primary">Открыть документы/);assert.match(read,/<button class="primary" disabled[^>]*>Сохранить решение/);
 const withoutSource=await render(['GET /admin/verifications/{id}']);assert.match(withoutSource,/<button class="primary" disabled[^>]*>Открыть документы/);
 const decision=await render(['GET /admin/verifications/{id}','POST /admin/verifications/{id}/decision']);assert.match(decision,/<button class="primary">Сохранить решение/);assert.match(decision,/<button class="primary" disabled[^>]*>Открыть документы/);
});
