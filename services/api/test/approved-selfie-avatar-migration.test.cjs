const {test}=require('node:test'),assert=require('node:assert/strict'),{randomUUID}=require('node:crypto');
const {Store}=require('../dist/store');
test('approved portrait restoration preserves manual avatars and never promotes a document page, rejected or deleted identity',async()=>{
 const s=new Store('memory://');await s.initialize();try{
 const put=async(kind,owner,data)=>{const r={id:randomUUID(),kind,owner,country:'KZ',version:1,created_at:new Date().toISOString(),...data};await s.put(r);return r;};
 const scenarios=[];
 for(const mode of ['active','blocked','deleted','rejected','document','manual']){
  const id=randomUUID(),manual=mode==='manual'?randomUUID():null;
  await put('user',id,{id,status:mode==='deleted'?'deleted':mode==='blocked'?'blocked':'active',verification:'passed',avatar_id:manual});
  const pages=[randomUUID(),randomUUID(),randomUUID()];
  const verification=await put('verification',id,{status:mode==='rejected'?'rejected':'passed',document_refs:pages});
  const avatar=await put('upload',id,{purpose:'identity',status:'clean',source_verification_id:verification.id,derived_from:pages[mode==='document'?0:2]});
  scenarios.push({mode,id,manual,avatar});
 }
 await s.initialize();
 for(const x of scenarios){const user=await s.get(x.id);assert.equal(user.avatar_id,['active','blocked'].includes(x.mode)?x.avatar.id:x.manual,x.mode);}
 const versions=await Promise.all(scenarios.map(x=>s.get(x.id)));await s.initialize();assert.deepEqual(await Promise.all(scenarios.map(x=>s.get(x.id))),versions);
 }finally{await s.close();}
});
