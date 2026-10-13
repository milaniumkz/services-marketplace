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
test('image finalization rejects mismatched formats and preserves EXIF orientation without retaining metadata',async()=>{
 const dir=await mkdtemp(join(tmpdir(),'joba-image-policy-')),providers=new Providers();
 providers.scanner={scan:async()=> 'clean'}; // Isolated adapter; this test validates image processing only.
 const api=new Marketplace(new Store('memory://'),providers,new PrivateFiles(dir));await api.initialize();
 const call=(session,method,path,body={},query={})=>api.handle(method,path,body,session?'Bearer '+session.access_token:undefined,randomUUID(),query,'image-policy-test');
 try{
  const user=await call(null,'POST','/auth/register',{country:'KZ',phone:'+77000000802',password:'Isolated image policy password!'});
  const upload=async(bytes,mime)=>{const record=await call(user,'POST','/uploads/initiate',{purpose:'portfolio',mime,size:bytes.length});await call(user,'PUT','/uploads/'+record.id+'/content',bytes);return record;};
  const png=await sharp({create:{width:2,height:3,channels:3,background:'#245BDB'}}).png().toBuffer();
  const wrong=await call(user,'POST','/uploads/initiate',{purpose:'portfolio',mime:'image/jpeg',size:png.length});
  await assert.rejects(()=>call(user,'PUT','/uploads/'+wrong.id+'/content',png),error=>error.getResponse().error.code==='POLICY_REJECTED');
  assert.equal((await call(user,'GET','/uploads/'+wrong.id+'/metadata')).status,'initiated');
  const corrupt=await upload(Buffer.concat([Buffer.from([0xff,0xd8,0xff]),png]),'image/jpeg');
  await assert.rejects(()=>call(user,'POST','/uploads/'+corrupt.id+'/finalize'),error=>error.getResponse().error.code==='POLICY_REJECTED');
  assert.equal((await call(user,'GET','/uploads/'+corrupt.id+'/metadata')).status,'rejected');
  const source=await sharp(png).withMetadata({orientation:6}).jpeg().toBuffer(),correct=await upload(source,'image/jpeg');
  assert.equal((await call(user,'POST','/uploads/'+correct.id+'/finalize')).status,'clean');
  const result=await call(user,'GET','/uploads/'+correct.id+'/download'),metadata=await sharp(result.download_buffer).metadata();
  assert.deepEqual([metadata.width,metadata.height],[3,2]);assert.equal(metadata.orientation,undefined);assert.equal(metadata.exif,undefined);
  const large=await upload(await sharp({create:{width:1600,height:1200,channels:3,background:'#245BDB'}}).png().toBuffer(),'image/png');await call(user,'POST','/uploads/'+large.id+'/finalize');
  const original=await call(user,'GET','/uploads/'+large.id+'/download'),preview=await call(user,'GET','/uploads/'+large.id+'/download',{}, {variant:'preview'});
  const dimensions=await sharp(preview.download_buffer).metadata();assert.deepEqual([dimensions.width,dimensions.height],[960,720]);assert.ok(preview.download_buffer.length<original.download_buffer.length);
  await assert.rejects(()=>call(user,'GET','/uploads/'+large.id+'/download',{}, {variant:'arbitrary-path'}),error=>error.getResponse().error.code==='VALIDATION_ERROR');

 }finally{await api.store.close();await rm(dir,{recursive:true,force:true});}
});
