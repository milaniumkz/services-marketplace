const {test}=require('node:test'),assert=require('node:assert/strict');
test('admin transport retains an ambiguous command key across an intervening 429 response',async t=>{
 const {staffApi}=await import('../../../apps/admin/api.js');let session={access_token:'isolated',user:{id:'staff-owner'}};const api=staffApi({getSession:()=>session,saveSession:value=>{session=value;}}),saved=new Map(),keys=[];let attempts=0,writes=0;
 t.mock.method(globalThis,'fetch',async(path,options)=>{
  const key=options.headers['Idempotency-Key'];keys.push(key);attempts++;
  if(attempts===2)return new Response(JSON.stringify({error:{code:'RATE_LIMITED',message:'Try later',details:{retry_after_seconds:30}}}),{status:429});
  if(!saved.has(key))saved.set(key,{id:'stored-command-'+(++writes)});
  if(attempts===1)throw new TypeError('response lost after commit');
  return new Response(JSON.stringify({data:saved.get(key)}));
 });
 const command=()=>api('/admin/categories','POST',{title:'Owned draft',reason:'Isolated retry check'});
 await assert.rejects(command,e=>e.code==='NETWORK_ERROR');await assert.rejects(command,e=>e.status===429);const result=await command();
 assert.equal(new Set(keys).size,1);assert.equal(writes,1);assert.equal(result.id,'stored-command-1');
});
