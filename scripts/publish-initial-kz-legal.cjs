// One-time, explicitly authorized publication. Normal revisions use staff approval.
const {Store}=require(process.env.JOBA_LEGAL_STORE_MODULE||'../services/api/dist/store');
const {readFileSync}=require('node:fs');
const {randomUUID,createHash}=require('node:crypto');
async function publishInitialLegal(store,documents){
 if(!Array.isArray(documents)||documents.length!==2||!['terms','privacy'].every(type=>documents.some(d=>d.type===type&&d.locale==='ru'&&typeof d.content==='string'&&d.content.length>=1000)))throw Error('Expected complete KZ Russian terms and privacy documents');
 const owner='00000000-0000-4000-8000-000000000001';
 await store.db.exec('BEGIN');
 try{
  // Serialize against another bootstrap; never replace an administrator's version.
  await store.db.query("SELECT pg_advisory_xact_lock(1752138231)");
  const existing=await store.all('legal_document','KZ');const result=[];
  for(const document of documents){
   if(existing.some(d=>d.locale==='ru'&&[document.type,document.type==='terms'?'terms_of_use':'privacy_policy'].includes(d.type))){result.push({type:document.type,status:'preserved_existing'});continue;}
   const now=new Date().toISOString(),id=randomUUID();
   await store.put({id,kind:'legal_document',owner,country:'KZ',locale:'ru',type:document.type,version:1,status:'published',content:document.content,hash:createHash('sha256').update(document.content).digest('hex'),created_at:now,published_at:now,...(document.type==='terms'?{minimum_age:18}:{}),publication_basis:'Owner explicitly requested publication with blank operator details on 2026-10-15',operator_details_pending:true});
   await store.put({id:randomUUID(),kind:'audit',owner,country:'KZ',version:1,created_at:now,occurred_at:now,action:'legal.initial_publication',target_id:id,actor_kind:'owner_authorized_deployment',reason:'Explicit owner instruction: prepare and publish KZ documents; leave operator details blank for subsequent editing. No independent legal review asserted.'});
   result.push({type:document.type,status:'published',id});
  }
  await store.db.exec('COMMIT');return result;
 }catch(error){await store.db.exec('ROLLBACK');throw error;}
}
module.exports={publishInitialLegal};
if(require.main===module){
 if(process.env.JOBA_INITIAL_KZ_LEGAL!=='owner-authorized-2026-10-15')throw Error('Explicit initial publication authorization required');
 const store=new Store();publishInitialLegal(store,JSON.parse(readFileSync(0,'utf8'))).then(result=>console.log(JSON.stringify(result))).catch(error=>{console.error(error.message);process.exitCode=1}).finally(()=>store.close());
}
