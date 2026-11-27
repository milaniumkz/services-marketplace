const {test}=require('node:test'),assert=require('node:assert/strict');
for(const lost of ['content','finalize'])test('admin attachment recovers lost '+lost+' response without retransmitting bytes',async t=>{
 const {staffApi}=await import('../../../apps/admin/api.js');
 const session={access_token:'isolated',user:{id:'staff',country:'KZ'}};
 const api=staffApi({getSession:()=>session,saveSession:()=>{}});
 let state='initiated',puts=0,finalizes=0,reads=0;
 t.mock.method(globalThis,'fetch',async(path,options)=>{
  let data;
  if(path.includes('/initiate'))data={id:'fixture-upload',status:state};
  else if(path.includes('/content')){puts++;state='uploaded';if(lost==='content')throw new TypeError('lost response');data={id:'fixture-upload',status:state};}
  else if(path.includes('/finalize')){finalizes++;state='scanning';throw new TypeError('timeout after commit');}
  else if(path.includes('/metadata')){reads++;if(state==='scanning')state='clean';data={id:'fixture-upload',status:state};}
  else assert.fail(path);
  return Response.json({data});
 });
 const file=new File(['fixture'],'test.jpg',{type:'image/jpeg'});
 assert.equal((await api.upload(file,'chat')).status,'clean');
 assert.equal((await api.upload(file,'chat')).status,'clean');
 assert.equal(puts,1);assert.equal(finalizes,1);assert.ok(reads>=2);
});
test('admin rejected attachment cannot be sent and a retry starts a new upload',async t=>{
 const {staffApi}=await import('../../../apps/admin/api.js');const session={access_token:'isolated',user:{id:'staff',country:'KZ'}};
 const api=staffApi({getSession:()=>session,saveSession:()=>{}});let starts=0;
 t.mock.method(globalThis,'fetch',async(path)=>Response.json({data:{id:'fixture',status:path.includes('/initiate')?(starts++,'initiated'):path.includes('/content')?'uploaded':'rejected'}}));
 const file=new File(['fixture'],'test.jpg',{type:'image/jpeg'});
 await assert.rejects(api.upload(file,'chat'),e=>e.code==='FILE_REJECTED');
 await assert.rejects(api.upload(file,'chat'),e=>e.code==='FILE_REJECTED');assert.equal(starts,2);
});
test('admin waits for scanning and recovers a later manual retry using metadata only',async t=>{
 const {staffApi}=await import('../../../apps/admin/api.js');const session={access_token:'isolated',user:{id:'staff',country:'KZ'}};
 const api=staffApi({getSession:()=>session,saveSession:()=>{}});let state='initiated',puts=0,reads=0,unavailable=true;
 t.mock.method(globalThis,'fetch',async(path)=>{
  if(path.includes('/initiate'))return Response.json({data:{id:'fixture',status:state}});
  if(path.includes('/content')){puts++;state='uploaded';}
  if(path.includes('/finalize')){state='scanning';throw new TypeError('timeout');}
  if(path.includes('/metadata')){reads++;if(unavailable)throw new TypeError('offline');state='clean';}
  return Response.json({data:{id:'fixture',status:state}});
 });
 const file=new File(['fixture'],'test.jpg',{type:'image/jpeg'});
 await assert.rejects(api.upload(file,'chat'),e=>e.code==='NETWORK_ERROR');
 unavailable=false;assert.equal((await api.upload(file,'chat')).status,'clean');assert.equal(puts,1);assert.equal(reads,2);
});
test('admin polls an in-progress scan until the file is clean',async t=>{
 const {staffApi}=await import('../../../apps/admin/api.js');const session={access_token:'isolated',user:{id:'staff',country:'KZ'}};
 const api=staffApi({getSession:()=>session,saveSession:()=>{}});let reads=0;
 t.mock.method(globalThis,'fetch',async(path)=>Response.json({data:{id:'fixture',status:path.includes('/initiate')?'initiated':path.includes('/content')?'uploaded':path.includes('/metadata')?(++reads,'clean'):'scanning'}}));
 assert.equal((await api.upload(new File(['fixture'],'test.jpg',{type:'image/jpeg'}),'chat')).status,'clean');assert.equal(reads,1);
});
