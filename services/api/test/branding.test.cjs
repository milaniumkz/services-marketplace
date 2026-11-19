const {test}=require('node:test');
const assert=require('node:assert/strict');
const {randomUUID}=require('node:crypto');
const {mkdtemp,rm}=require('node:fs/promises');
const {join}=require('node:path');
const {tmpdir}=require('node:os');
const sharp=require('sharp');
const {inflateRawSync}=require('node:zlib');
const {Marketplace}=require('../dist/marketplace');
const {Store}=require('../dist/store');
const {Providers}=require('../dist/providers');
const {PrivateFiles}=require('../dist/private-files');
function archiveEntries(bytes){
 let end=bytes.length-22;while(end>=0&&bytes.readUInt32LE(end)!==0x06054b50)end--;
 assert.ok(end>=0);let offset=bytes.readUInt32LE(end+16);const count=bytes.readUInt16LE(end+10),entries=new Map();
 for(let i=0;i<count;i++){
  assert.equal(bytes.readUInt32LE(offset),0x02014b50);
  const method=bytes.readUInt16LE(offset+10),size=bytes.readUInt32LE(offset+20),nameLength=bytes.readUInt16LE(offset+28),extra=bytes.readUInt16LE(offset+30),comment=bytes.readUInt16LE(offset+32),local=bytes.readUInt32LE(offset+42);
  const name=bytes.subarray(offset+46,offset+46+nameLength).toString();
  const start=local+30+bytes.readUInt16LE(local+26)+bytes.readUInt16LE(local+28),data=bytes.subarray(start,start+size);
  entries.set(name,method===8?inflateRawSync(data):data);offset+=46+nameLength+extra+comment;
 }return entries;
}
test('branding uses scanned PNG, independent approval and complete opaque iOS/adaptive Android resources',async()=>{
 const dir=await mkdtemp(join(tmpdir(),'joba-brand-test-')),providers=new Providers();
 // Only the isolated test supplies this scanner; production remains closed without AV.
 providers.scanner={scan:async()=> 'clean'};
 const api=new Marketplace(new Store('memory://'),providers,new PrivateFiles(dir));await api.initialize();
 const call=(user,method,path,body={})=>api.handle(method,path,body,'Bearer '+user.access_token,randomUUID());
 const staff=async(phone,permissions)=>{
  const session=await api.handle('POST','/auth/register',{country:'KZ',phone,password:'Isolated brand fixture!'},undefined,undefined,{},phone);
  const user=await api.store.get(session.user.id);await api.store.put({...user,staff_permissions:permissions});
  await api.store.db.query('UPDATE tokens SET mfa_verified=true WHERE user_id=$1',[user.id]);return session;
 };
 try{
  const creator=await staff('+77000000381',['content','brand_owner']),approver=await staff('+77000000382',['brand_owner']),release=await staff('+77000000383',['release']);
  const source=await sharp({create:{width:1200,height:1024,channels:4,background:{r:30,g:100,b:200,alpha:.8}}}).png().toBuffer();
  await assert.rejects(()=>call(approver,'POST','/uploads/initiate',{purpose:'brand',mime:'image/png',size:source.length}),e=>e.getStatus()===403);
  await assert.rejects(()=>call(creator,'POST','/uploads/initiate',{purpose:'brand',mime:'image/jpeg',size:source.length}),e=>e.getStatus()===422);
  const upload=await call(creator,'POST','/uploads/initiate',{purpose:'brand',mime:'image/png',size:source.length});
  await call(creator,'PUT','/uploads/'+upload.id+'/content',source);
  const checked=await call(creator,'POST','/uploads/'+upload.id+'/finalize');assert.equal(checked.status,'clean');assert.equal(checked.mime,'image/png');
  await assert.rejects(()=>call(creator,'POST','/admin/brand-icons',{upload_id:upload.id,crop:{left:1000,top:0,size:1024},reason:'Проверка неверной обрезки'}),e=>e.getResponse().error.code==='INVALID_CROP');
  const version=await call(creator,'POST','/admin/brand-icons',{upload_id:upload.id,reason:'Новый исходник для сборки'});assert.equal(version.crop.left,88);assert.equal(version.crop.size,1024);
  assert.equal((await call(approver,'GET','/admin/brand-icons')).items.length,1);
  await assert.rejects(()=>call(creator,'POST','/admin/brand-icons/'+version.id+'/approve',{expected_version:1,reason:'Проверка служебных прав'}),e=>e.getResponse().error.code==='SECOND_APPROVAL_REQUIRED');
  await assert.rejects(()=>call(release,'POST','/admin/brand-icons/'+version.id+'/generate',{expected_version:1,reason:'Проверка до утверждения'}),e=>e.getResponse().error.code==='APPROVAL_REQUIRED');
  const approved=await call(approver,'POST','/admin/brand-icons/'+version.id+'/approve',{expected_version:1,reason:'Проверены маски и исходник'});
  await assert.rejects(()=>call(creator,'POST','/admin/brand-icons/'+version.id+'/generate',{expected_version:approved.version,reason:'Проверка отдельной роли'}),e=>e.getStatus()===403);
  const result=await call(release,'POST','/admin/brand-icons/'+version.id+'/generate',{expected_version:approved.version,reason:'Подготовить ресурсы сборки'});
  assert.equal(result.release_status,'not_built');assert.equal(result.variants.length,39);
  const bundle=await api.handle('GET','/admin/brand-icons/'+version.id+'/bundle',{},'Bearer '+release.access_token,undefined,{reason:'Проверить пакет перед сборкой'});
  const chunks=[];for await(const chunk of bundle.download_stream)chunks.push(chunk);
  const entries=archiveEntries(Buffer.concat(chunks));assert.equal(entries.size,40);
  const catalog=JSON.parse(entries.get('ios/Assets.xcassets/AppIcon.appiconset/Contents.json'));
  assert.equal(catalog.images.length,18);
  for(const image of catalog.images){const metadata=await sharp(entries.get('ios/Assets.xcassets/AppIcon.appiconset/'+image.filename)).metadata();assert.equal(metadata.width,Math.round(parseFloat(image.size)*parseFloat(image.scale)));assert.equal(metadata.hasAlpha,false);}
  const foreground=await sharp(entries.get('android/res/mipmap-xxxhdpi/ic_launcher_foreground.png')).ensureAlpha().raw().toBuffer({resolveWithObject:true});
  assert.equal(foreground.info.width,432);assert.equal(foreground.data[3],0);assert.equal(foreground.data[(216*432+216)*4+3],255);
  const manifest=JSON.parse(entries.get('manifest.json'));assert.equal(manifest.safe_zone_dp,66);assert.equal(manifest.source_checksum,result.source_checksum);
  assert.ok(entries.get('android/res/mipmap-anydpi-v26/ic_launcher.xml').toString().includes('@mipmap/ic_launcher_foreground'));
  assert.equal((await sharp(entries.get('store/google-play-512.png')).metadata()).width,512);
  const repeated=await call(release,'POST','/admin/brand-icons/'+version.id+'/generate',{expected_version:result.version,reason:'Повтор запроса готового пакета'});assert.equal(repeated.bundle_file_id,result.bundle_file_id);
  const foreign={...result,id:randomUUID(),country:'RU'};await api.store.put(foreign);await assert.rejects(()=>call(release,'GET','/admin/brand-icons/'+foreign.id),e=>e.getStatus()===404);

 }finally{await api.store.close();await rm(dir,{recursive:true,force:true});}
});
