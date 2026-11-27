const {test}=require('node:test'),assert=require('node:assert/strict');
const {mkdtemp,rm,readdir,stat}=require('node:fs/promises');
const {tmpdir}=require('node:os'),{join}=require('node:path'),{randomUUID}=require('node:crypto');
const {PrivateFiles}=require('../dist/private-files');
test('concurrent initializers publish one complete key and all can decrypt the same file',async()=>{
 const dir=await mkdtemp(join(tmpdir(),'joba-key-init-'));
 try{
  const workers=Array.from({length:40},()=>new PrivateFiles(dir));
  await Promise.all(workers.map(w=>w.initialize()));
  const id=randomUUID(),content=Buffer.from('Isolated concurrency verification');
  await workers[0].write(id,content);
  for(const w of workers)assert.deepEqual(await w.read(id),content);
  assert.deepEqual((await readdir(dir)).sort(),[id+'.encrypted','storage.key'].sort());
  assert.equal((await stat(join(dir,'storage.key'))).size,32);
 }finally{await rm(dir,{recursive:true,force:true});}
});
