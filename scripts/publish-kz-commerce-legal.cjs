// Explicit owner instruction: prepare KZ payment information; keep operator details blank for later admin revision.
const {randomUUID,createHash}=require('node:crypto');
async function publishCommerceLegal(store,documents){
 const types=['payments','refunds','public_offer','contacts'];
 if(!Array.isArray(documents)||documents.length!==types.length||!types.every(type=>documents.filter(d=>d.type===type&&d.locale==='ru'&&typeof d.content==='string'&&d.content.length>=500).length===1))throw Error('Expected four complete KZ commerce documents');
 await store.db.exec('BEGIN');
 try{
  await store.db.query('SELECT pg_advisory_xact_lock(1752138231)');
  const existing=await store.all('legal_document','KZ'),owner='00000000-0000-4000-8000-000000000001',result=[];
  for(const d of documents){
   if(existing.some(x=>(d.type==='payments'?['payments','subscriptions','subscription'].includes(x.type):x.type===d.type)&&x.locale===d.locale)){result.push({type:d.type,status:'preserved_existing'});continue;}
   const id=randomUUID(),now=new Date().toISOString();
   await store.put({...d,id,kind:'legal_document',owner,country:'KZ',version:1,status:'published',created_at:now,published_at:now,hash:createHash('sha256').update(d.content).digest('hex'),operator_details_pending:true,publication_basis:'Owner requested KZ payment/refund information on 2026-10-16; no bank approval asserted'});
   await store.put({id:randomUUID(),kind:'audit',owner,country:'KZ',version:1,created_at:now,action:'legal.commerce_initial_publication',target_id:id,reason:'Owner-authorized payment information; operator details pending, no VTB acceptance asserted'});result.push({type:d.type,id,status:'published'});
  }
  await store.db.exec('COMMIT');return result;
 }catch(error){await store.db.exec('ROLLBACK');throw error;}
}
module.exports={publishCommerceLegal};
if(require.main===module){
 if(process.env.JOBA_KZ_COMMERCE_LEGAL!=='owner-authorized-2026-10-16')throw Error('Explicit commerce legal publication authorization required');
 const {Store}=require(process.env.JOBA_LEGAL_STORE_MODULE||'../services/api/dist/store'),{readFileSync}=require('node:fs'),store=new Store();
 publishCommerceLegal(store,JSON.parse(readFileSync(0,'utf8'))).then(result=>console.log(JSON.stringify(result))).catch(error=>{console.error(error.message);process.exitCode=1}).finally(()=>store.close());
}
