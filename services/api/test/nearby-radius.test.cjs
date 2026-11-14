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
test('city-only contractor uses an explicitly approximate same-country city centre; precise location and distance still win',async()=>{
 const s=new Store('memory://');await s.initialize();try{
 const base={country:'KZ',version:1,created_at:new Date().toISOString()};
 for(const[name,latitude,longitude,country]of [['Караганда',49.8,73.1,'KZ'],['Павлодар',52.3,76.9,'KZ'],['Без координат',49.8,73.1,'RU']])await s.put({...base,id:randomUUID(),owner:randomUUID(),kind:'city',status:'active',name,latitude,longitude,country});
 const ids={};for(const[name,city,point]of [['city','Караганда',null],['far','Павлодар',null],['exactFar','Караганда',{latitude:52.3,longitude:76.9}],['foreign','Без координат',null]]){
  const owner=randomUUID(),id=randomUUID();ids[name]=id;await s.put({...base,id:owner,owner,kind:'user',status:'active',verification:'passed'});await s.put({...base,id,owner,kind:'contractor',status:'published',city,public_location:point});
 }
 const rows=await s.select('contractor','KZ',{publicActor:randomUUID(),statuses:['published'],near:{latitude:49.8,longitude:73.1,radius:20},limit:10});assert.deepEqual(rows.map(r=>r.id),[ids.city]);assert.equal(rows[0].location_approximate,true);assert.equal(rows[0].public_location.precision,'city');
 const ranked=await s.select('contractor','KZ',{publicActor:randomUUID(),statuses:['published'],near:{latitude:49.8,longitude:73.1,radius:20},ranking:{windowDays:30,dislikeWeight:1,ageDays:30,sort:'popular'},limit:10});assert.equal(ranked[0].location_approximate,true);
 assert.equal((await s.get(ids.city)).public_location,null,'approximation must not rewrite a private profile');
 }finally{await s.close();}
});
test('new accounts sort by creation date across all countries, with stable next-page ordering instead of random UUID order',async()=>{
 const s=new Store('memory://');await s.initialize();try{
 const rows=[['ffffffff-ffff-4fff-8fff-ffffffffffff','KZ','2026-01-01T00:00:00Z'],['00000000-0000-4000-8000-000000000001','BY','2026-11-09T00:00:00Z'],['aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa','KG','2026-10-09T00:00:00Z']];
 for(const[id,country,created_at]of rows)await s.put({id,owner:id,kind:'user',country,created_at,version:1,status:'active'});
 const first=await s.select('user','ALL',{endUserOnly:true,newestFirst:true,limit:2});assert.deepEqual(first.map(x=>x.country),['BY','KG']);const next=await s.select('user','ALL',{endUserOnly:true,newestFirst:true,after:first[1].id,limit:2});assert.deepEqual(next.map(x=>x.country),['KZ']);
 }finally{await s.close();}
});
