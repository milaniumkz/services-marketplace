const root=process.env.JOBA_REFERENCE_MODULE_ROOT||'../services/api/dist/';
const {Store}=require(root+'store'),{importReferenceDataset}=require(root+'reference-import');
(async()=>{if(process.env.JOBA_REFERENCE_IMPORT!=='owner-authorized-2026-10-20')throw Error('Explicit owner authorization required');const store=new Store();try{await store.initialize();console.log(JSON.stringify(await importReferenceDataset(store)));}finally{await store.close();}})().catch(error=>{console.error('Reference import failed:',error.message);process.exitCode=1;});
