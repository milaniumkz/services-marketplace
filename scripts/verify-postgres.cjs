// Isolated ephemeral PostgreSQL validation; never point this at application/production data.
const {readFileSync}=require('node:fs');
const {resolve}=require('node:path');
const {randomUUID}=require('node:crypto');
const {performance}=require('node:perf_hooks');
const assert=require('node:assert/strict');
const variables=Object.fromEntries(readFileSync(resolve(__dirname,'../.local/postgres-test.env'),'utf8').trim().split('\n').map(l=>{const i=l.indexOf('=');return [l.slice(0,i),l.slice(i+1)];}));
const url=new URL('postgresql://127.0.0.1:5439/'+variables.POSTGRES_DB);url.username=variables.POSTGRES_USER;url.password=variables.POSTGRES_PASSWORD;
process.env.DATABASE_URL=url.toString();
const {Store}=require('../services/api/dist/store');
const {Marketplace}=require('../services/api/dist/marketplace');
async function main(){
  const api=new Marketplace(new Store());await api.initialize();
  try{
    assert.equal((await api.store.all('user')).length,0,'Use a fresh ephemeral validation database');
    const credentials=await api.handle('POST','/auth/register',{country:'KZ',phone:'+77000000401',password:'a long isolated validation password',display_name:'Isolated SQL fixture'},undefined,undefined,{},'test-postgres');
    const user=await api.store.get(credentials.user.id);await api.store.put({...user,verification:'passed',roles:['customer','executor'],fixture:true});
    await api.store.put({id:randomUUID(),kind:'grant',owner:user.id,country:'KZ',version:1,created_at:new Date().toISOString(),valid_until:new Date(Date.now()+86400000).toISOString(),source:'isolated_fixture',capabilities:['search_full','publish_order','send_offer','select_offer']});
    const records=Array.from({length:5000},(_,i)=>({id:randomUUID(),kind:'order',owner:user.id,country:'KZ',version:1,created_at:new Date().toISOString(),title:'SQL fixture order '+i,description:'Synthetic validation data; never used by the application database.',city:'Алматы',category_id:'1',currency:'KZT',budget_amount:null,status:'open',revision:1,fixture:true,expires_at:new Date(Date.now()+86400000).toISOString()}));
    const args=[],values=records.map(r=>{const start=args.length;args.push(r.id,r.kind,r.owner,r.country,r.version,JSON.stringify(r));return '('+Array.from({length:6},(_,i)=>'$'+(start+i+1)).join(',')+')';});
    await api.store.db.query('INSERT INTO records(id,kind,owner,country,version,data) VALUES '+values.join(','),args);
    const auth='Bearer '+credentials.access_token,times=[];
    for(let i=0;i<110;i++){
      const start=performance.now();const page=await api.handle('GET','/orders',{},auth,undefined,{limit:20});assert.equal(page.items.length,20);if(i>=10)times.push(performance.now()-start);
    }
    const first=await api.handle('GET','/orders',{},auth,undefined,{limit:20});
    const second=await api.handle('GET','/orders',{},auth,undefined,{limit:20,cursor:first.meta.next_cursor});
    assert.equal(first.items.some(a=>second.items.some(b=>a.id===b.id)),false);
    await assert.rejects(()=>api.handle('GET','/orders',{},auth,undefined,{limit:20,cursor:first.meta.next_cursor,city:'Другой город'}),e=>e.getResponse().error.code==='VALIDATION_ERROR');
    times.sort((a,b)=>a-b);console.log(JSON.stringify({database:'PostgreSQL 16',dataset:5000,queries:100,returned_per_page:20,p50_ms:Number(times[49].toFixed(2)),p95_ms:Number(times[94].toFixed(2)),max_ms:Number(times[99].toFixed(2)),cursor_isolation:'passed'},null,2));
  }finally{await api.store.close();}
}
main().catch(e=>{console.error('PostgreSQL validation failed:',e.code??e.message);process.exitCode=1;});
