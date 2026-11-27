import {Store} from './store';
import {referenceId} from './reference-data';
export const fallbackCities:Record<string,string[]>={KZ:['Алматы','Астана','Шымкент'],KG:['Бишкек','Ош'],RU:['Москва','Санкт-Петербург'],BY:['Минск','Гомель']};
const cache=new WeakMap<Store,Map<string,{at:number;items:any[]}>>();
export async function cityCatalog(store:Store,country:string,query=''){
 let countries=cache.get(store);if(!countries){countries=new Map();cache.set(store,countries);}
 let entry=countries.get(country);
 if(!entry||Date.now()-entry.at>30000){
  const rows=(await store.all('city',country)).filter(x=>x.status==='active');
  const items=rows.length?rows.sort((a,b)=>(b.population??0)-(a.population??0)||a.name.localeCompare(b.name,'ru')).map(r=>({id:r.id,name:r.name,country,region:r.region,region_kind:r.region_kind,region_sort_order:r.region_sort_order,geonames_id:r.geonames_id,aliases:r.aliases??[],latitude:r.latitude,longitude:r.longitude})):(fallbackCities[country]??[]).map(name=>({id:referenceId(`joba:city:${country}:${name}`),name,country}));
  entry={at:Date.now(),items};if(rows.length)countries.set(country,entry);
 }
 const normalized=query.trim().toLocaleLowerCase('ru').replaceAll('ё','е');
 return {items:normalized?entry.items.filter(x=>[x.name,...(x.aliases??[])].some(s=>s.toLocaleLowerCase('ru').replaceAll('ё','е').includes(normalized))):entry.items,meta:{total:entry.items.length,source:'GeoNames',attribution:'GeoNames geographical database — https://www.geonames.org/',license:'https://creativecommons.org/licenses/by/4.0/'}};
}
export async function cityName(store:Store,country:string,id:string){
 if(!/^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i.test(id))return undefined;
 const record=await store.get(id);if(record?.kind==='city'&&record.country===country&&record.status==='active')return record.name as string;
 return fallbackCities[country]?.find(name=>referenceId(`joba:city:${country}:${name}`)===id);
}
