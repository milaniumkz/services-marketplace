const {test}=require('node:test');
const assert=require('node:assert/strict');
const {randomUUID}=require('node:crypto');
const {mkdtemp,rm}=require('node:fs/promises');
const {join}=require('node:path');
const {tmpdir}=require('node:os');
const sharp=require('sharp');
const {Marketplace}=require('../dist/marketplace');
const {Store}=require('../dist/store');
const {PrivateFiles}=require('../dist/private-files');
const {Providers}=require('../dist/providers');
test('file checks remain private and do not block other API requests',async()=>{
 const dir=await mkdtemp(join(tmpdir(),'joba-upload-worker-')),providers=new Providers();
 let start,release;const started=new Promise(resolve=>start=resolve),gate=new Promise(resolve=>release=resolve);let scans=0;
 providers.scanner={scan:async()=>{scans++;start();await gate;return 'clean';}}; // Isolated delayed adapter, not a production antivirus.
 const api=new Marketplace(new Store('memory://'),providers,new PrivateFiles(dir));await api.initialize();
 const call=(session,method,path,body={},key=randomUUID())=>api.handle(method,path,body,session?'Bearer '+session.access_token:undefined,key,{},'upload-worker-test');
 let pending;
 try{
  const user=await call(null,'POST','/auth/register',{country:'KZ',phone:'+77000000801',password:'Isolated file worker password!'});
  const image=await sharp({create:{width:4,height:4,channels:3,background:'#245BDB'}}).png().toBuffer();
  const upload=await call(user,'POST','/uploads/initiate',{purpose:'avatar',mime:'image/png',size:image.length});
  await call(user,'PUT','/uploads/'+upload.id+'/content',image);
  const key=randomUUID();pending=call(user,'POST','/uploads/'+upload.id+'/finalize',{},key);await started;
  let timeout;const readable=await Promise.race([call(user,'GET','/me'),new Promise((_,reject)=>timeout=setTimeout(()=>reject(Error('File scan blocked unrelated API read')),200))]);clearTimeout(timeout);assert.equal(readable.id,user.user.id);
  assert.equal((await call(user,'GET','/uploads/'+upload.id+'/metadata')).status,'scanning');
  await assert.rejects(()=>call(user,'GET','/uploads/'+upload.id+'/download'),error=>error.getStatus()===404);
  const repeated=call(user,'POST','/uploads/'+upload.id+'/finalize',{},key);release();
  const results=await Promise.all([pending,repeated]);assert.equal(results[0].status,'clean');assert.equal(results[1].status,'clean');assert.equal(scans,1);
  const profile=await call(user,'GET','/me');const saved=await call(user,'PATCH','/me',{expected_version:profile.version,avatar_id:results[0].id});assert.equal(saved.avatar_id,upload.id);
  assert.equal((await sharp((await call(user,'GET','/uploads/'+upload.id+'/download')).download_buffer).metadata()).format,'jpeg');
 }finally{release();await pending?.catch(()=>{});await api.store.close();await rm(dir,{recursive:true,force:true});}
});
