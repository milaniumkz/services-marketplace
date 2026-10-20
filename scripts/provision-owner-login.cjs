// Explicit owner-requested offline provisioning. Only encrypted delivery leaves the server.
const {randomBytes,publicEncrypt,constants}=require('node:crypto');
const {readFileSync}=require('node:fs');
const {Store}=require('/app/services/api/dist/store');
const {PrivateFiles}=require('/app/services/api/dist/private-files');
const {bootstrapStaff}=require('/app/services/api/dist/staff-bootstrap');
(async()=>{
 if(process.env.JOBA_OWNER_PASSWORD_LOGIN!=='owner-authorized')throw Error('Owner authorization required');
 const key=readFileSync('/tmp/joba-admin-public.pem');
 const store=new Store();await store.initialize();
 try{
  const countries=['KZ','KG','RU','BY'];
  for(const country of countries)if((await store.db.query('SELECT 1 FROM credentials WHERE country=$1 AND phone=$2',[country,'admin'])).rows.length)throw Error('Existing admin account preserved; refusing password reset');
  const password=randomBytes(24).toString('base64url');
  for(const country of countries)await bootstrapStaff(store,new PrivateFiles(),{country,identifier:'admin',display_name:'Владелец JOBA',password,authentication:'password',permissions:['platform_owner'],reason:'Владелец запросил первичную настройку входа по логину и паролю'},async()=>{});
  const encrypted=publicEncrypt({key,padding:constants.RSA_PKCS1_OAEP_PADDING,oaepHash:'sha256'},Buffer.from(JSON.stringify({login:'admin',password,countries})));
  console.log(encrypted.toString('base64'));
 }finally{await store.close();}
})().catch(()=>{console.error('Owner provisioning failed; inspect account state without exposing credentials');process.exitCode=1;});
