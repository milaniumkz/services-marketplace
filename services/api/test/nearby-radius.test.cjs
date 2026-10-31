const{test}=require('node:test'),assert=require('node:assert/strict'),{randomUUID}=require('node:crypto');
const{Store}=require('../dist/store');
test('20 km selection excludes distant and unlocated contractors despite service cities',async()=>{
 const s=new Store('memory://');await s.initialize();try{
 const ids={},base={country:'KZ',version:1,created_at:new Date().toISOString()};
 for(const[name,km]of [['near',19.9],['far',20.1],['missing',null]]){
  const owner=randomUUID(),id=randomUUID();ids[name]=id;await s.put({...base,id:owner,owner,kind:'user',status:'active',verification:'passed'});
  await s.put({...base,id,owner,kind:'contractor',status:'published',city:'Другой город',service_cities:['Караганда'],public_location:km===null?null:{latitude:49.8+km/6371*180/Math.PI,longitude:73.1}});
 }
 const rows=await s.select('contractor','KZ',{publicActor:randomUUID(),statuses:['published'],near:{latitude:49.8,longitude:73.1,radius:20},limit:10});assert.deepEqual(rows.map(r=>r.id),[ids.near]);
 }finally{await s.close();}
});
