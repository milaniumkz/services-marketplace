const{test}=require('node:test'),assert=require('node:assert/strict'),{randomUUID}=require('node:crypto');
const{Marketplace}=require('../dist/marketplace'),{Store}=require('../dist/store');
test('order errors name the Russian field, exact bound and count with machine-readable focus metadata',async()=>{
 const a=new Marketplace(new Store('memory://'));await a.initialize();try{
 const user=await a.handle('POST','/auth/register',{country:'KZ',phone:'+77000000951',password:'Validation test password'},undefined,undefined,{},'validation-case');
 const category=(await a.handle('GET','/catalog/categories',{},'Bearer '+user.access_token)).items[0].id;
 const body={category_id:category,city:'Караганда',title:'Штукатурка стен',description:'Мало'};
 const create=b=>a.handle('POST','/orders',b,'Bearer '+user.access_token,randomUUID());
 await assert.rejects(()=>create(body),e=>{const x=e.getResponse().error;assert.equal(x.details.field,'description');assert.equal(x.details.min,20);assert.equal(x.details.actual,4);assert.equal(x.details.constraint,'min_length');assert.match(x.message,/Описание/);assert.match(x.message,/Добавьте ещё 16/);assert.doesNotMatch(x.message,/description/);return true;});
 await assert.rejects(()=>create({...body,description:'я'.repeat(5001)}),e=>{const x=e.getResponse().error;assert.equal(x.details.max,5000);assert.equal(x.details.constraint,'max_length');assert.match(x.message,/Уберите 1/);return true;});
 await assert.rejects(()=>create({...body,title:'Нет'}),e=>e.getResponse().error.details.field==='title');
 }finally{await a.store.close();}
});
