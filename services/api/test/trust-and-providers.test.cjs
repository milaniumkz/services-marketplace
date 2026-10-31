const {test}=require('node:test');
const assert=require('node:assert/strict');
const {randomUUID,randomBytes}=require('node:crypto');
const {mkdtemp,readFile,writeFile,rm}=require('node:fs/promises');
const {join}=require('node:path');
const {tmpdir}=require('node:os');
const sharp=require('sharp');
const {Marketplace}=require('../dist/marketplace');
const {Store}=require('../dist/store');
const {Providers}=require('../dist/providers');
const {PrivateFiles}=require('../dist/private-files');
const {totp}=require('../dist/totp');
const {matchesRule}=require('../dist/moderation');

const account=(api,phone='+77000000101')=>api.handle('POST','/auth/register',{country:'KZ',phone,password:'a sufficiently long password',display_name:'Тестовый пользователь'},undefined,undefined,{},phone);
const command=(api,u,method,path,body={},key=randomUUID(),q={})=>api.handle(method,path,body,'Bearer '+u.access_token,key,q);
const rejection=(fn,code)=>assert.rejects(fn,e=>e.getResponse().error.code===code);

test('staff password authentication retains separate privileges and append-only audit',async()=>{
  const api=new Marketplace(new Store('memory://'));await api.initialize();
  try {
    const u=await account(api),user=await api.store.get(u.user.id),secret=randomBytes(20).toString('hex');
    await api.store.put({...user,staff_permissions:['administrator','auditor'],totp_secret:secret});
    await rejection(()=>command(api,u,'GET','/admin/users'),'FORBIDDEN');
    await rejection(()=>api.handle('POST','/auth/staff-login',{country:'KZ',phone:user.phone,password:'incorrect password'},undefined,undefined,{},'staff'),'INVALID_CREDENTIALS');
    const staff=await api.handle('POST','/auth/staff-login',{country:'KZ',phone:user.phone,password:'a sufficiently long password',mfa_code:totp(secret)},undefined,undefined,{},'staff');
    const ordinary=await account(api,'+77000000102');
    const visibleUsers=(await command(api,staff,'GET','/admin/users')).items;assert.equal(visibleUsers.length,1);assert.equal(visibleUsers[0].id,ordinary.user.id);
    const d=await command(api,staff,'POST','/admin/categories',{title:'Категория услуг',payload:{labels:{ru:'Категория услуг',kk:'Қызметтер санаты'},icon:'briefcase'},reason:'Настройка рабочего каталога'});
    const audits=await api.store.all('audit','KZ');assert.equal(audits.length,1);
    await assert.rejects(()=>api.store.put({...audits[0],reason:'Переписать историю'}),/append-only/);
    const again=await api.handle('POST','/auth/staff-login',{country:'KZ',phone:user.phone,password:'a sufficiently long password'},undefined,undefined,{},'staff');assert.ok(again.access_token);
    assert.equal(d.status,'draft');
  } finally {await api.store.close();}
});

test('dictionary quarantine is deduplicated, temporary and never a permanent blacklist',async()=>{
  assert.equal(matchesRule('Слово проверкамаркер рядом','проверкамаркер','exact_word'),true);
  assert.equal(matchesRule('антипроверкамаркер','проверкамаркер','exact_word'),false);
  assert.equal(matchesRule('два\nслова','два слова','phrase'),true);
  const api=new Marketplace(new Store('memory://'));await api.initialize();
  try {
    const u=await account(api);
    await api.store.put({id:randomUUID(),kind:'dictionary',owner:'system',country:'KZ',version:1,created_at:new Date().toISOString(),status:'published',payload:{rules:[{type:'exact_word',value:'проверкамаркер'}]}});
    const data={title:'Заказ проверкамаркер',description:'Достаточно длинное описание заказа для проверки текста.',category_id:'1',city:'Алматы',budget_amount:null};const key=randomUUID();
    const order=await command(api,u,'POST','/orders',data,key);
    assert.equal(order.status,'pending_moderation');assert.equal(order.moderation_status,'quarantined');
    await command(api,u,'POST','/orders',data,key);
    assert.equal((await api.store.all('auto_hold','KZ')).length,1);assert.equal((await api.store.all('case','KZ')).length,1);assert.equal((await api.store.all('blacklist','KZ')).length,0);
    await api.maintenance(new Date(Date.now()+61*60000));
    assert.equal((await api.store.get(u.user.id)).status,'active');
    assert.equal((await api.store.get(order.id)).moderation_status,'quarantined');
  } finally {await api.store.close();}
});

test('private files require a clean scan and are encrypted at rest',async()=>{
  const dir=await mkdtemp(join(tmpdir(),'joba-files-'));const providers=new Providers();const files=new PrivateFiles(dir);const api=new Marketplace(new Store('memory://'),providers,files);await api.initialize();
  try {
    const u=await account(api),stranger=await account(api,'+77000000102');
    const image=await sharp({create:{width:2,height:2,channels:3,background:'#245BDB'}}).png().toBuffer();
    const upload=await command(api,u,'POST','/uploads/initiate',{purpose:'portfolio',mime:'image/png',size:image.length});
    await command(api,u,'PUT',`/uploads/${upload.id}/content`,image);
    const stored=await readFile(join(dir,upload.id+'.encrypted'));assert.equal(stored.includes(image),false);
    await rejection(()=>command(api,u,'GET',`/uploads/${upload.id}/download`),'NOT_FOUND');
    await rejection(()=>command(api,u,'POST',`/uploads/${upload.id}/finalize`),'SCANNER_UNAVAILABLE');
    providers.scanner={scan:async()=> 'clean'}; // adapter contract only; this is not a real antivirus validation.
    const final=await command(api,u,'POST',`/uploads/${upload.id}/finalize`);assert.equal(final.status,'clean');assert.equal(final.mime,'image/jpeg');
    const file=await command(api,u,'GET',`/uploads/${upload.id}/download`);assert.equal(file.download_buffer[0],255);
    await rejection(()=>command(api,stranger,'GET',`/uploads/${upload.id}/download`),'NOT_FOUND');
    const bytes=await readFile(join(dir,upload.id+'.encrypted'));bytes[bytes.length-1]^=1;await writeFile(join(dir,upload.id+'.encrypted'),bytes);
    await assert.rejects(()=>files.read(upload.id));
  } finally {await api.store.close();await rm(dir,{recursive:true,force:true});}
});

test('payment evidence, ownership, provider revisions and webhook replay',async()=>{
  const providers=new Providers(),api=new Marketplace(new Store('memory://'),providers);await api.initialize();
  try {
    const u=await account(api),other=await account(api,'+77000000102');
    for(const account of [u,other])await api.store.put({...await api.store.get(account.user.id),roles:['customer','executor'],active_role:'executor'});
    const proof={provider:'test-contract',transaction_id:'transaction-1',original_transaction_id:'original-1',user_id:u.user.id,country:'KZ',product_id:'test-product',environment:'sandbox',amount_minor:100,currency:'KZT',valid_until:new Date(Date.now()+86400000).toISOString(),state:'active',revision:1};
    // Test doubles stay in test files. Runtime Providers has no enabled providers by default.
    providers.billing.set('test-contract',{name:'test-contract',verifyPurchase:async()=>proof,verifyWebhook:async(raw)=>{if(raw.toString()!=='valid')throw Error('Invalid signature');return {event_id:'event-1',purchase:proof};}});
    await api.store.put({id:randomUUID(),kind:'price_version',owner:'system',country:'KZ',version:1,created_at:new Date().toISOString(),status:'effective',payload:{provider:'test-contract',product_id:'test-product',amount_minor:100,currency:'KZT'}});
    await rejection(()=>command(api,other,'POST','/billing/verify-purchase',{provider:'test-contract',transaction_reference:'ref'}),'PURCHASE_OWNERSHIP_MISMATCH');
    const result=await command(api,u,'POST','/billing/verify-purchase',{provider:'test-contract',transaction_reference:'ref'});assert.equal(result.subscription.status,'active');
    const duplicate=await command(api,u,'POST','/billing/restore',{provider:'test-contract',transaction_reference:'ref'});assert.equal(duplicate.duplicate,true);
    assert.equal((await api.store.all('grant','KZ')).length,1);assert.equal((await api.store.all('payment_transaction','KZ')).length,1);
    await assert.rejects(()=>api.handle('POST','/webhooks/billing/test-contract',{raw_body:Buffer.from('bad'),headers:{}}),/Invalid signature/);
    assert.equal((await api.store.all('webhook_inbox','KZ')).length,0);
    await api.handle('POST','/webhooks/billing/test-contract',{raw_body:Buffer.from('valid'),headers:{}});
    assert.equal((await api.handle('POST','/webhooks/billing/test-contract',{raw_body:Buffer.from('valid'),headers:{}})).duplicate,true);
    proof.state='revoked';proof.revision=2;await command(api,u,'POST','/billing/verify-purchase',{provider:'test-contract',transaction_reference:'ref'});
    assert.ok(Date.parse((await api.store.all('grant','KZ'))[0].valid_until)<=Date.now());
  } finally {await api.store.close();}
});

test('export job produces an encrypted archive without passwords, tokens or staff secrets',async()=>{
  const dir=await mkdtemp(join(tmpdir(),'joba-export-')),api=new Marketplace(new Store('memory://'),new Providers(),new PrivateFiles(dir));await api.initialize();
  try {
    const u=await account(api);
    api.providers.scanner={scan:async()=> 'clean'}; // Isolated scanner adapter; production never trusts this.
    const image=await sharp({create:{width:3,height:3,channels:3,background:'#245BDB'}}).png().toBuffer();
    const upload=await command(api,u,'POST','/uploads/initiate',{purpose:'portfolio',mime:'image/png',size:image.length});
    await command(api,u,'PUT',`/uploads/${upload.id}/content`,image);await command(api,u,'POST',`/uploads/${upload.id}/finalize`);
    const clean=await api.files.read(upload.id);
    const job=await command(api,u,'POST','/me/privacy-requests',{type:'export',current_password:'a sufficiently long password'});
    await api.maintenance();const result=await command(api,u,'GET',`/me/privacy-requests/${job.id}`);assert.equal(result.status,'completed');
    const read=api.files.read.bind(api.files);api.files.read=async id=>{if(id===result.upload_id)throw Error('Export must stream instead of buffering the archive');return read(id);};
    const download=await command(api,u,'GET',`/uploads/${result.upload_id}/download`);assert.equal(download.mime,'application/zip');assert.equal(download.download_buffer,undefined);
    const chunks=[];for await(const chunk of download.download_stream)chunks.push(chunk);
    const zipPath=join(dir,'isolated-export.zip');await writeFile(zipPath,Buffer.concat(chunks));
    const {execFileSync}=require('node:child_process');
    const archive=JSON.parse(execFileSync('unzip',['-p',zipPath,'data.json']).toString());
    const csv=execFileSync('unzip',['-p',zipPath,'csv/user.csv']).toString();assert.ok(csv.includes('+77000000101'));
    const manifest=JSON.parse(execFileSync('unzip',['-p',zipPath,'manifest.json']).toString());assert.equal(manifest.format_version,1);assert.equal(manifest.attachment_count,1);assert.deepEqual(execFileSync('unzip',['-p',zipPath,'attachments/'+upload.id+'.jpg']),clean);
    const stored=await readFile(join(dir,result.upload_id+'.encrypted'));assert.notEqual(stored.subarray(0,4).toString('hex'),'504b0304');
    assert.equal((await command(api,u,'GET','/me/notifications')).items.some(n=>n.type==='privacy.export.ready'),true);
    assert.equal(archive.user[0].phone,'+77000000101');assert.equal(JSON.stringify(archive).includes('password_hash'),false);assert.equal(JSON.stringify(archive).includes(u.access_token),false);
  } finally {await api.store.close();await rm(dir,{recursive:true,force:true});}
});
