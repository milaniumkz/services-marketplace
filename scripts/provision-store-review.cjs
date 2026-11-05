// One explicit owner-authorized store-review account. No staff rights or paid grants.
const {randomUUID,randomBytes,publicEncrypt,constants}=require('node:crypto');
const {readFileSync,writeFileSync,existsSync}=require('node:fs');
const {Store}=require('/app/services/api/dist/store');
const {hash}=require('/app/node_modules/@node-rs/argon2');
(async()=>{
 if(process.env.JOBA_STORE_REVIEW_AUTHORIZATION!=='owner-authorized')throw Error('Explicit owner authorization required');
 const key=readFileSync('/tmp/joba-store-review-recipient.pem');
 const reviewPhone=process.env.JOBA_STORE_REVIEW_PHONE||'+77000000991';
 if(!/^\+77000000\d{3}$/.test(reviewPhone))throw Error('Dedicated review phone required');
 const privatePath=reviewPhone==='+77000000991'?'/app/.local/store-review-credentials.json':`/app/.local/store-review-credentials-${reviewPhone.slice(1)}.json`;
 const store=new Store();await store.initialize();
 try {
  let credentials;
  if(existsSync(privatePath)){
   credentials=JSON.parse(readFileSync(privatePath,'utf8'));
   const user=await store.get(credentials.user_id);
   if(!user?.store_review_demo||user.status!=='active')throw Error('Existing review account needs owner inspection; no reset performed');
  }else{
   const phone=reviewPhone,country='KZ';
   if((await store.db.query('SELECT 1 FROM credentials WHERE country=$1 AND phone=$2',[country,phone])).rows.length)throw Error('Phone already exists; refusing overwrite');
   const id=randomUUID(),password=randomBytes(24).toString('base64url'),now=new Date().toISOString();
   await store.db.exec('BEGIN');
   try {
    await store.put({id,kind:'user',owner:id,country,version:1,created_at:now,display_name:'JOBA · демонстрационный аккаунт',phone,phone_status:'unverified',city:'Алматы',locale:'ru',languages:['ru'],roles:['customer','executor'],active_role:'customer',verification:'passed',status:'active',store_review_demo:true,verification_basis:'Owner-authorized demonstration account for Apple/Google review; not a verified real person'});
    await store.db.query('INSERT INTO credentials(country,phone,user_id,password_hash) VALUES($1,$2,$3,$4)',[country,phone,id,await hash(password,{memoryCost:19456,timeCost:2,parallelism:1})]);
    await store.put({id:randomUUID(),kind:'audit',owner:id,country,version:1,created_at:now,actor_id:'owner-authorized-store-publication',action:'store_review_demo.created',target_id:id,reason:`Owner explicitly requested a dedicated store-review demonstration account; provisioned ${now}. No real identity document or payment was fabricated.`});
    await store.db.exec('COMMIT');
   }catch(e){await store.db.exec('ROLLBACK');throw e;}
   credentials={phone,password,country,user_id:id,purpose:'Apple and Google store review only'};
   writeFileSync(privatePath,JSON.stringify(credentials),{mode:0o600,flag:'wx'});
  }
  const envelope=publicEncrypt({key,padding:constants.RSA_PKCS1_OAEP_PADDING,oaepHash:'sha256'},Buffer.from(JSON.stringify(credentials)));
  process.stdout.write(envelope.toString('base64')+'\n');
 }finally{await store.close();}
})().catch(e=>{console.error(e.message);process.exitCode=1;});
