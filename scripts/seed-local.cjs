const { Store } = require('../services/api/dist/store');
const { hash } = require('@node-rs/argon2');
const { randomUUID,randomBytes } = require('node:crypto');
const { mkdirSync,writeFileSync,existsSync } = require('node:fs');
const { resolve } = require('node:path');

async function main() {
  if(process.env.NODE_ENV==='production'||process.env.JOBA_LOCAL_FIXTURES!=='1')throw Error('Local synthetic fixtures require JOBA_LOCAL_FIXTURES=1 and non-production');
  const dir=resolve(__dirname,'../.local/e2e');mkdirSync(dir,{recursive:true});
  const credentialsPath=resolve(dir,'development-accounts.json');
  if(existsSync(credentialsPath)){console.log('Existing local fixture accounts preserved.');return;}
  const store=new Store(process.env.JOBA_DATA_DIR??resolve(dir,'joba'));await store.initialize();
  const credentials={};
  try {
    for(const [name,phone,permissions] of [['customer','+77000000001',[]],['executor','+77000000002',[]],['staff','staff-local',['administrator','support','auditor','senior_moderator']]]) {
      const id=randomUUID(),password=randomBytes(24).toString('base64url'),secret=name==='staff'?randomBytes(20).toString('hex'):undefined;
      const user={id,kind:'user',owner:id,country:'KZ',version:1,created_at:new Date().toISOString(),display_name:name==='customer'?'Заказчик · локальный тест':name==='executor'?'Исполнитель · локальный тест':'Сотрудник · локальный тест',phone,phone_status:'unverified',city:'Алматы',roles:name==='executor'?['customer','executor']:['customer'],verification:name==='executor'?'passed':'not_started',status:'active',staff_permissions:permissions,totp_secret:secret,fixture:true};
      await store.put(user);await store.db.query('INSERT INTO credentials(country,phone,user_id,password_hash) VALUES($1,$2,$3,$4)', ['KZ',phone,id,await hash(password)]);
      if(name!=='staff')await store.put({id:randomUUID(),kind:'grant',owner:id,country:'KZ',version:1,created_at:new Date().toISOString(),valid_until:new Date(Date.now()+7*86400000).toISOString(),source:'synthetic_local_fixture',capabilities:['publish_order','search_full','send_offer','select_offer','publish_profile']});
      credentials[name]={phone,password,country:'KZ',id,...(secret?{totp_secret:secret}:{})};
    }
    writeFileSync(credentialsPath,JSON.stringify(credentials,null,2),{mode:0o600,flag:'wx'});
    console.log('Synthetic fixture accounts created; credentials saved only to ignored .local/development-accounts.json. No production identity verification or purchase was performed.');
  } finally {await store.close();}
}
main().catch(e=>{console.error(e.message);process.exitCode=1;});
