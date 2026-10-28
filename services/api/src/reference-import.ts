import {readFileSync} from 'node:fs';
import {resolve} from 'node:path';
import {createHash} from 'node:crypto';
import {Store,RecordData} from './store';
import {referenceId} from './reference-data';
import {categoryId} from './category-payload';
const roots=['Ремонт','Уборка','Перевозки','Красота','Обучение'];
const legacyCities:Record<string,string>={'1526384':'Алматы','1526273':'Астана','1518980':'Шымкент','1528675':'Бишкек','1527534':'Ош','524901':'Москва','498817':'Санкт-Петербург','625144':'Минск','627907':'Гомель'};
export function referenceDataset(){
 const dir=resolve(__dirname,'../reference'),categories=JSON.parse(readFileSync(resolve(dir,'categories.json'),'utf8'));
 const cities=Object.fromEntries(['KZ','KG','RU','BY'].map(c=>[c,JSON.parse(readFileSync(resolve(dir,'cities-'+c+'.json'),'utf8'))]));
 return {categories,cities,hash:createHash('sha256').update(JSON.stringify({categories,cities})).digest('hex')};
}
export function validateReferenceDataset(dataset:ReturnType<typeof referenceDataset>){
 const keys=new Set<string>();
 for(const node of dataset.categories){if(typeof node.key!=='string'||keys.has(node.key)||typeof node.name!=='string'||node.name.length<2||node.name.length>120||node.parent&&!keys.has(node.parent)||![1,2,3].includes(node.depth))throw Error('Invalid category tree');keys.add(node.key);}
 for(const [country,rows] of Object.entries(dataset.cities)){
  if(!['KZ','KG','RU','BY'].includes(country)||!Array.isArray(rows))throw Error('Invalid country');const ids=new Set(),names=new Set();
  for(const c of rows){if(!Number.isSafeInteger(c.geonames_id)||ids.has(c.geonames_id)||typeof c.display_name!=='string'||c.display_name.length>100||names.has(c.display_name.toLocaleLowerCase('ru'))||!Number.isFinite(c.latitude)||Math.abs(c.latitude)>90||!Number.isFinite(c.longitude)||Math.abs(c.longitude)>180)throw Error('Invalid city record');ids.add(c.geonames_id);names.add(c.display_name.toLocaleLowerCase('ru'));}
 }
}
/** Correct only imported geographic classification; preserve IDs, names and operator edits. */
export async function normalizeKazakhstanRegions(store:Store){
 const priorities:Record<string,number>={'Астана':0,'Алматы':1,'Шымкент':2};let changed=0;
 for(const row of await store.all('city','KZ')){
  if(row.source!=='geonames')continue;
  const patch:Record<string,any>={};
  if(row.region==='Байконур'){patch.region='Кызылординская Область';patch.region_kind='oblast';patch.region_sort_order=undefined;}
  else if(priorities[row.region]!==undefined){if(row.region_sort_order===undefined)patch.region_sort_order=priorities[row.region];if(row.region_kind!=='republican_city')patch.region_kind='republican_city';}
  if(!Object.keys(patch).length)continue;
  await store.put({...row,...patch,version:row.version+1});changed++;
 }
 if(changed){const id=referenceId('joba:kz-regions-normalization:20261028'),prior=await store.get(id);await store.put({id,kind:'audit',owner:'system',country:'KZ',version:prior?prior.version+1:1,created_at:prior?.created_at??new Date().toISOString(),action:'reference.kz_regions_normalized',actor_id:'system',reason:'По поручению владельца: Астана, Алматы, Шымкент перед областями; Байконур не является отдельным регионом списка',changed});}
 return changed;
}
export async function importReferenceDataset(store:Store,dataset=referenceDataset()){
 validateReferenceDataset(dataset);await store.db.exec('BEGIN');
 try{
  await store.db.query('SELECT pg_advisory_xact_lock(hashtextextended($1,0))',['reference-catalog-import']);
  for(const country of ['BY','KG','KZ','RU'])await store.db.query('SELECT pg_advisory_xact_lock(hashtextextended($1,0))',['category-publish:'+country]);
  await normalizeKazakhstanRegions(store);
  const markerId=referenceId('joba:reference-import:'+dataset.hash);
  if(await store.get(markerId)){await store.db.exec('COMMIT');return {unchanged:true,hash:dataset.hash};}
  const now=new Date().toISOString(),existing=await store.all('category'),result:Record<string,any>={};
  const bulk=async(rows:RecordData[])=>{
   let count=0;
   for(let i=0;i<rows.length;i+=300){const r=await store.db.query(`INSERT INTO records(id,kind,owner,country,version,data) SELECT (v->>'id')::uuid,v->>'kind',v->>'owner',v->>'country',(v->>'version')::int,v FROM jsonb_array_elements($1::jsonb) v ON CONFLICT(id) DO NOTHING RETURNING id`,[JSON.stringify(rows.slice(i,i+300))]);count+=r.rows.length;}
   return count;
  };
  for(const country of ['KZ','KG','RU','BY']){
   const ids=new Set(existing.filter(r=>r.country===country).map(categoryId)),active=existing.filter(r=>r.country===country&&r.status==='effective'),mapping=new Map<string,string>(),inactive=new Set<string>(),records:RecordData[]=[];
   for(const [sortOrder,node] of dataset.categories.entries()){
    if(node.parent&&inactive.has(node.parent)){inactive.add(node.key);continue;}
    const parent=node.parent?mapping.get(node.parent):null;
    if(node.parent&&!parent)throw Error('Missing parent');
    const oldIndex=roots.indexOf(node.key),stable=oldIndex>=0?referenceId(`joba:category:${country}:${oldIndex}`):referenceId(`joba:category:${country}:reference:${node.key}`);
    const same=active.find(r=>(r.payload?.parent_id??null)===parent&&(r.payload?.labels?.ru??r.title).toLocaleLowerCase('ru')===node.name.toLocaleLowerCase('ru'));
    const id=same?categoryId(same):stable;mapping.set(node.key,id);
    if(ids.has(id)){if(!active.some(r=>categoryId(r)===id))inactive.add(node.key);continue;}
    records.push({id,kind:'category',owner:'system',country,version:1,created_at:now,status:'effective',title:node.name,payload:{category_id:id,parent_id:parent,labels:{ru:node.name},icon:node.depth===1?'layers':'briefcase',schema:{properties:{},required:[]},source:'joba_service_catalog',source_key:node.key,depth:node.depth,sort_order:sortOrder,translation_status:'ru_complete_other_locales_fallback'}});ids.add(id);
   }
   const cityRecords:RecordData[]=dataset.cities[country].map((c:any)=>({id:legacyCities[String(c.geonames_id)]?referenceId(`joba:city:${country}:${legacyCities[String(c.geonames_id)]}`):referenceId(`joba:geonames:city:${country}:${c.geonames_id}`),kind:'city',owner:'system',country,version:1,created_at:now,status:'active',name:c.display_name,local_name:c.name,region:c.region,region_kind:c.region_kind,region_sort_order:c.region_sort_order,geonames_id:c.geonames_id,latitude:c.latitude,longitude:c.longitude,population:c.population,aliases:c.aliases,labels:c.labels,source:'geonames',license:'CC BY 4.0'}));
   result[country]={categories_added:await bulk(records),cities_added:await bulk(cityRecords),categories_expected:dataset.categories.length,cities_expected:cityRecords.length};
   await store.put({id:referenceId('joba:reference-audit:'+dataset.hash+':'+country),kind:'audit',owner:'system',country,version:1,created_at:now,actor_id:'system',action:'reference.catalog_import',reason:'Владелец поручил заполнить города и категории 20.10.2026',counts:result[country],dataset_hash:dataset.hash});
  }
  await store.put({id:markerId,kind:'reference_import',owner:'system',country:'KZ',version:1,created_at:now,hash:dataset.hash,counts:result});await store.db.exec('COMMIT');return {unchanged:false,hash:dataset.hash,countries:result};
 }catch(error){await store.db.exec('ROLLBACK');throw error;}
}
