export function profileFields(body:any, previous:any, currency:string, categoryIds:Set<string>) {
  const value=(key:string,fallback:any)=>body[key]===undefined?(previous?.[key]??fallback):body[key];
  const invalid=(key:string):never=>{throw new Error(key);};
  const list=(key:string,fallback:string[],allowed?:Set<string>,max=10)=>{
    const values=value(key,fallback);
    if(!Array.isArray(values)||!values.length||values.length>max||new Set(values).size!==values.length||values.some(x=>typeof x!=='string'||!x.trim()||x.length>100||(allowed&&!allowed.has(x))))invalid(key);
    return values.map((x:string)=>x.trim());
  };
  const categories=list('category_ids',[body.category_id??previous?.category_id],categoryIds);
  if(body.category_id!==undefined&&body.category_ids===undefined&&body.category_id!==previous?.category_id){categories.splice(0,categories.length,body.category_id);}
  const modes=list('work_modes',['onsite'],new Set(['onsite','workshop','remote','hybrid']),4);
  const languages=list('languages',['ru'],new Set(['ru','kk','ky','sr','be','en']),5);
  const cities=list('service_cities',[body.city??previous?.city],undefined,20);
  const radius=value('travel_radius_km',0),experience=value('experience_years',null);
  if(typeof radius!=='number'||!Number.isFinite(radius)||radius<0||radius>1000)invalid('travel_radius_km');
  if(experience!==null&&(!Number.isInteger(experience)||experience<0||experience>100))invalid('experience_years');
  const availability=value('availability','available');
  if(!['available','busy','paused'].includes(availability))invalid('availability');
  const price=value('price',{mode:'negotiable',currency});
  if(!price||typeof price!=='object'||Array.isArray(price)||!['fixed','hourly','per_unit','negotiable'].includes(price.mode)||price.currency!==currency)invalid('price');
  let safePrice:any={mode:price.mode,currency};
  if(price.mode!=='negotiable'){
    if(!Number.isSafeInteger(price.amount_min)||price.amount_min<0)invalid('price.amount_min');
    if(price.amount_max!==undefined&&price.amount_max!==null&&(!Number.isSafeInteger(price.amount_max)||price.amount_max<price.amount_min))invalid('price.amount_max');
    if(price.mode==='per_unit'&&!['job','hour','day','piece','m2','m3','meter','visit'].includes(price.unit))invalid('price.unit');
    safePrice={...safePrice,amount_min:price.amount_min,amount_max:price.amount_max??null,unit:price.mode==='hourly'?'hour':price.mode==='per_unit'?price.unit:'job'};
  }
  return {category_ids:categories,category_id:categories[0],work_modes:modes,languages,service_cities:cities,travel_radius_km:radius,experience_years:experience,availability,price:safePrice};
}
