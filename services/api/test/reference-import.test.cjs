const {test}=require('node:test'),assert=require('node:assert/strict'),{randomUUID}=require('node:crypto');
const {Marketplace}=require('../dist/marketplace'),{Store}=require('../dist/store');
const {referenceDataset,validateReferenceDataset,importReferenceDataset}=require('../dist/reference-import');
const {referenceId}=require('../dist/reference-data'),{cityCatalog,cityName}=require('../dist/city-catalog');
test('full reference import preserves edits and IDs; city searches and descendant filters use real records',async()=>{
 const a=new Marketplace(new Store('memory://'));await a.initialize();
 try{
  const data=referenceDataset();validateReferenceDataset(data);assert.equal(data.categories.length,933);
  assert.equal((await importReferenceDataset(a.store,data)).unchanged,false);
  for(const c of ['KZ','KG','RU','BY']){assert.equal((await a.store.all('category',c)).length,933);assert.equal((await a.store.all('city',c)).length,data.cities[c].length);}
  assert.equal((await cityCatalog(a.store,'RU','моск')).items.some(c=>c.name==='Москва'),true);
  assert.equal((await cityCatalog(a.store,'RU','Moscow')).items.some(c=>c.name==='Москва'),true);
  assert.equal(await cityName(a.store,'KZ',referenceId('joba:city:KZ:Алматы')),'Алматы');
  assert.equal(await cityName(a.store,'RU',referenceId('joba:city:KZ:Алматы')),undefined);
  const cities=await cityCatalog(a.store,'RU');assert.equal(new Set(cities.items.map(c=>c.name.toLowerCase())).size,cities.items.length);
  const root=referenceId('joba:category:KZ:0');assert.equal((await a.store.get(root)).legacy_id,'1');
  const categories=await a.store.all('category','KZ'),child=categories.find(c=>c.payload.parent_id===root),leaf=categories.find(c=>c.payload.parent_id===child.id);
  const record={id:randomUUID(),kind:'contractor',country:'KZ',owner:randomUUID(),version:1,created_at:new Date().toISOString(),status:'published',category_id:leaf.id};await a.store.put(record);
  assert.equal((await a.store.select('contractor','KZ',{category:root})).some(r=>r.id===record.id),true);
  assert.equal((await a.store.select('contractor','KZ',{category:referenceId('joba:category:KZ:1')})).some(r=>r.id===record.id),false);
  await a.store.put({...child,title:'Изменено владельцем',version:2});assert.equal((await importReferenceDataset(a.store,data)).unchanged,true);assert.equal((await a.store.get(child.id)).title,'Изменено владельцем');
  assert.equal((await a.store.all('audit')).filter(x=>x.action==='reference.catalog_import').length,4);
 }finally{await a.store.close();}
});
test('KZ republican cities carry server ordering and legacy Baikonur groups are corrected without deleting cities',async()=>{
 const a=new Marketplace(new Store('memory://'));await a.initialize();
 try{
  const dataset=referenceDataset();await importReferenceDataset(a.store,dataset);
  const cities=await a.store.all('city','KZ'),baikonur=cities.find(c=>c.geonames_id===1521368),toretam=cities.find(c=>c.geonames_id===9858283);
  assert.ok(baikonur&&toretam);assert.equal(baikonur.region,'Кызылординская Область');
  await a.store.put({...baikonur,region:'Байконур',name:'Байконур — имя, изменённое владельцем',version:baikonur.version+1});
  const astana=cities.find(c=>c.geonames_id===1526273);await a.store.put({...astana,region_sort_order:undefined,region_kind:undefined,version:astana.version+1});
  assert.equal((await importReferenceDataset(a.store,dataset)).unchanged,true);
  assert.equal((await a.store.get(baikonur.id)).name,'Байконур — имя, изменённое владельцем');assert.equal((await a.store.get(baikonur.id)).region,'Кызылординская Область');
  for(const[name,rank]of [['Астана',0],['Алматы',1],['Шымкент',2]]){const city=(await a.store.all('city','KZ')).find(c=>c.region===name);assert.equal(city.region_sort_order,rank);assert.equal(city.region_kind,'republican_city');}
  const catalog=await cityCatalog(a.store,'KZ');assert.equal(catalog.items.some(c=>c.region==='Байконур'),false);assert.ok(catalog.items.find(c=>c.id===astana.id).region_sort_order===0);
  assert.equal((await a.store.all('city','KZ')).length,cities.length);
  const again=await a.store.get(toretam.id);await a.store.put({...again,region:'Байконур',version:again.version+1});
  await importReferenceDataset(a.store,dataset);assert.equal((await a.store.get(toretam.id)).region,'Кызылординская Область');
  const version=(await a.store.get(baikonur.id)).version;await importReferenceDataset(a.store,dataset);assert.equal((await a.store.get(baikonur.id)).version,version);
 }finally{await a.store.close();}
});
