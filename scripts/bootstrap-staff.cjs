const {readFile,open,rm,stat}=require('node:fs/promises');
const {Store}=require('../services/api/dist/store');
const {PrivateFiles}=require('../services/api/dist/private-files');
const {bootstrapStaff}=require('../services/api/dist/staff-bootstrap');
async function main(){
 if(process.env.JOBA_STAFF_BOOTSTRAP!=='1')throw Error('Offline staff creation requires JOBA_STAFF_BOOTSTRAP=1');
 if(!process.env.JOBA_STAFF_CONFIG_PATH||!process.env.JOBA_STAFF_ENROLLMENT_PATH)throw Error('Set private config and enrollment paths; never pass secrets as command arguments');
 const mode=(await stat(process.env.JOBA_STAFF_CONFIG_PATH)).mode;if(mode&0o077)throw Error('Private staff configuration must have mode 0600');
 let input;try{input=JSON.parse(await readFile(process.env.JOBA_STAFF_CONFIG_PATH,'utf8'));}catch{throw Error('Private staff configuration is not valid JSON');}
 const file=await open(process.env.JOBA_STAFF_ENROLLMENT_PATH,'wx',0o600);let completed=false;
 const store=new Store();
 try{
  await store.initialize();const result=await bootstrapStaff(store,new PrivateFiles(),input,async enrollment=>{await file.writeFile(JSON.stringify(enrollment,null,2));await file.sync();});
  completed=true;console.log('Staff account created:',result.id,'country:',result.country,'MFA enrollment saved to the protected file.');
 }finally{await file.close();if(!completed)await rm(process.env.JOBA_STAFF_ENROLLMENT_PATH,{force:true});await store.close();}
}
main().catch(error=>{console.error('Staff bootstrap failed:',error.code||error.message);process.exitCode=1;});
