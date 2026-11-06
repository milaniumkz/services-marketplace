const {test}=require('node:test'),assert=require('node:assert/strict'),{randomUUID}=require('node:crypto');
const {Store}=require('../dist/store'),{adminReviewQueues}=require('../dist/admin-review-queues'),{adminContentDetail}=require('../dist/admin-content-detail');
test('review queues count pending draft revisions, separate identity roles, cap previews and scope country and permissions',async()=>{
 const store=new Store('memory://');await store.initialize();try{
 const customer=randomUUID(),executor=randomUUID();
 const put=(kind,data={},owner=executor,country='KZ')=>store.put({id:randomUUID(),kind,owner,country,version:1,created_at:new Date().toISOString(),...data});
 await put('user',{id:customer,active_role:'customer',phone:'private',display_name:'Заказчик'},customer);await put('user',{id:executor,active_role:'executor',display_name:'Исполнитель'},executor);
 await put('verification',{status:'pending_review'},customer);await put('verification',{status:'pending_review',submitted_role:'customer'},executor);await put('verification',{status:'pending_review'},executor);await put('verification',{status:'passed'},executor);await put('verification',{status:'pending_review'},executor,'KG');
 for(let i=0;i<7;i++)await put('portfolio',{status:'published',draft:{title:'Новая редакция',status:'pending_review'}});
 await put('portfolio',{status:'published'});await put('contractor',{status:'pending_review'});await put('case',{status:'closed'});
 const data=await adminReviewQueues(store,'KZ');const queue=key=>data.queues.find(q=>q.key===key);
 assert.equal(queue('customers').count,2);assert.equal(queue('executors').count,1);assert.equal(queue('portfolio').count,7);assert.equal(queue('portfolio').items.length,5);assert.equal(queue('portfolio').items[0].title,'Новая редакция');assert.equal(queue('contractors').count,1);assert.equal(queue('cases').count,0);assert.match(queue('customers').href,/owner_role=customer/);assert.equal(JSON.stringify(data).includes('private'),false);assert.ok(data.activity.some(x=>x.status==='passed'));assert.ok(data.activity.every(x=>x.document_refs===undefined));assert.ok(data.activity.length<=20);
 const restricted=await adminReviewQueues(store,'KZ',['GET /admin/portfolio']);assert.deepEqual(restricted.queues.map(q=>q.key),['portfolio']);
 }finally{await store.close();}
});
test('content review details include owner and staged categories without phone or private identity documents',async()=>{
 const store=new Store('memory://');await store.initialize();try{
 const owner=randomUUID(),category=randomUUID(),profile=randomUUID();const put=(kind,data={})=>store.put({id:randomUUID(),kind,owner,country:'KZ',version:1,created_at:new Date().toISOString(),...data});
 await put('user',{id:owner,display_name:'Мастер',phone:'+77000000123',avatar_id:'avatar',status:'active',roles:['executor']});await put('category',{id:category,title:'Отделочные работы'});
 const record=await put('contractor',{id:profile,title:'Старая версия',status:'published',draft:{title:'Новая версия',status:'pending_review',gallery_ids:['work'],category_id:category}});
 await put('portfolio',{title:'Пример',status:'pending_review'});await put('verification',{status:'passed',document_refs:['SECRET']});await put('portfolio',{title:'Чужая страна',country:'KG'});
 const detail=await adminContentDetail(store,record);assert.equal(detail.title,'Новая версия');assert.equal(detail.subject.phone,undefined);assert.equal(detail.subject.phone_masked,'•••• 0123');assert.equal(detail.subject.avatar_id,'avatar');assert.equal(detail.categories[0].name,'Отделочные работы');assert.equal(detail.related.portfolio.length,1);assert.equal(detail.related.verifications[0].document_refs,undefined);assert.equal(JSON.stringify(detail).includes('SECRET'),false);
 const restricted=await adminContentDetail(store,record,['GET /admin/contractors/{id}']);assert.deepEqual(restricted.related,{portfolio:[],services:[],verifications:[]});
 }finally{await store.close();}
});
