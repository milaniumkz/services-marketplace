const {randomUUID,createHash}=require('node:crypto');
async function publishCountryReadiness(store,documents){
 const countries=['KZ','RU','BY','KG'],types=['terms','privacy','payments','refunds','public_offer','contacts','verification_consent'];
 for(const country of countries)for(const type of types)if(!documents.some(d=>d.country===country&&d.type===type&&d.locale==='ru'&&d.content?.length>=500))throw Error('Missing complete regional document: '+country+'/'+type);
 const owner='00000000-0000-4000-8000-000000000001',result=[];await store.db.exec('BEGIN');
 try{await store.db.query('SELECT pg_advisory_xact_lock(1752138231)');
 for(const country of countries){const existing=await store.all('legal_document',country),now=new Date().toISOString(),row=(kind,data)=>({id:randomUUID(),kind,owner,country,version:1,created_at:now,...data});
 for(const d of documents.filter(d=>d.country===country)){
  const family=d.type==='terms'?['terms','terms_of_use']:d.type==='privacy'?['privacy','privacy_policy']:d.type==='payments'?['payments','subscriptions','subscription']:[d.type];
  if(existing.some(x=>x.status==='published'&&x.locale==='ru'&&family.includes(x.type)))continue;
  const saved=await store.put(row('legal_document',{...d,status:'published',published_at:now,minimum_age:d.type==='terms'?18:undefined,hash:createHash('sha256').update(d.content).digest('hex'),operator_details_pending:true,publication_basis:'Explicit owner request 2026-10-29: all four country registration flows and documents'}));existing.push(saved);
  await store.put(row('audit',{action:'legal.regional_initial_publication',target_id:saved.id,reason:'Владелец поручил заполнить недостающие документы всех четырёх стран; существующие опубликованные версии сохранены'}));result.push({country,type:d.type,status:'published'});
 }
 if(!(await store.all('verification_policy',country)).some(x=>x.status==='effective')){const document=existing.find(x=>x.type==='verification_consent'&&x.status==='published');await store.put(row('verification_policy',{status:'effective',title:'Проверка документа и селфи',payload:{document_id:document.id,document_types:['id_card','passport'],required_pages:{id_card:['Лицевая сторона','Обратная сторона','Селфи'],passport:['Основная страница','Вторая страница документа','Селфи']},selfie_index:2}}));}
 const applied=(await store.all('country_readiness_migration',country)).some(x=>x.model==='registration-2026-10-29');
 if(!applied){
  for(const control of await store.all('country_control',country))if(control.status==='effective')await store.put({...control,payload:{...control.payload,registration_enabled:true,stop_new_business:false},version:control.version+1});
  if(!(await store.all('test_payment_settings',country)).length)await store.put(row('test_payment_settings',{enabled:true}));
  const old=(await store.all('subscription_catalog',country))[0];if(old&&(!Number.isSafeInteger(old.prices?.customer)||old.prices.customer<=0))await store.put({...old,prices:{...old.prices,customer:50000},version:old.version+1});
  await store.put(row('country_readiness_migration',{model:'registration-2026-10-29',status:'applied'}));await store.put(row('audit',{action:'country.registration_ready',target_id:country,reason:'Поручение владельца 2026-10-29: активировать регистрацию всех стран и заполнить обязательные документы'}));
 }
 }
 await store.db.exec('COMMIT');return result;
 }catch(error){await store.db.exec('ROLLBACK');throw error;}
}
module.exports={publishCountryReadiness};
if(require.main===module){if(process.env.JOBA_COUNTRY_READINESS!=='owner-authorized-2026-10-29')throw Error('Owner publication authorization required');const {Store}=require(process.env.JOBA_COUNTRY_STORE_MODULE||'../services/api/dist/store'),{readFileSync}=require('node:fs'),store=new Store();publishCountryReadiness(store,JSON.parse(readFileSync(0,'utf8'))).then(x=>console.log(JSON.stringify(x))).catch(e=>{console.error(e.message);process.exitCode=1;}).finally(()=>store.close());}
