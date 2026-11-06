const {test}=require('node:test');
const assert=require('node:assert/strict');
const {randomUUID}=require('node:crypto');
const {Marketplace}=require('../dist/marketplace');
const {Store}=require('../dist/store');
const {rankingParameters}=require('../dist/ranking');
test('Top ranks eligible records before limiting, applies configured votes and strips private fields',async()=>{
 const api=new Marketplace(new Store('memory://'));await api.initialize();
 const call=(u,p,q={})=>api.handle('GET',p,{},'Bearer '+u.access_token,randomUUID(),q,'top-test');
 try{
  const reader=await api.handle('POST','/auth/register',{country:'KZ',phone:'+77000000781',password:'Isolated ranking test password!'},undefined,randomUUID(),{},'top-test');
  await api.store.put({...await api.store.get(reader.user.id),verification:'passed',roles:['customer','executor'],active_role:'executor'});
  const now=new Date().toISOString(),future=new Date(Date.now()+86400000).toISOString();
  await api.store.put({id:randomUUID(),kind:'grant',owner:reader.user.id,country:'KZ',version:1,created_at:now,valid_until:future,capabilities:['search_full']});
  const owner=randomUUID();await api.store.put({id:owner,kind:'user',owner,country:'KZ',version:1,created_at:now,status:'active',verification:'passed'});
  const base={kind:'order',owner,country:'KZ',version:1,created_at:now,published_at:now,expires_at:future,status:'open',city:'Алматы',category_id:'repair',title:'Real test order',exact_address:'PRIVATE ADDRESS',reason:'PRIVATE REASON',case_id:randomUUID(),draft:{title:'PRIVATE DRAFT'}};
  for(let i=0;i<102;i++)await api.store.put({...base,id:randomUUID()},{skipContentCheck:true});
  const winner={...base,id:'ffffffff-ffff-4fff-8fff-fffffffffff1'};await api.store.put(winner,{skipContentCheck:true});
  await api.store.db.query('INSERT INTO votes(voter,target,value) VALUES($1,$2,1)',[reader.user.id,winner.id]);
  await api.store.db.query('INSERT INTO votes(voter,target,value) VALUES($1,$2,1)',[owner,winner.id]);
  await api.store.db.query("INSERT INTO votes(voter,target,value,created_at) VALUES($1,$2,-1,now()-interval '400 days')",[randomUUID(),winner.id]);
  const ineligible=[];
  for(const extra of [{moderation_status:'hidden'},{status:'closed'},{expires_at:new Date(Date.now()-1000).toISOString()}]){
   const id=randomUUID();ineligible.push(id);await api.store.put({...base,...extra,id},{skipContentCheck:true});await api.store.db.query('INSERT INTO votes(voter,target,value) VALUES($1,$2,1)',[reader.user.id,id]);
  }
  const result=await call(reader,'/top-listings',{target_type:'orders'});
  assert.equal(result.items.length,100);assert.equal(result.items[0].id,winner.id);assert.equal(result.items[0].likes,1);assert.equal(result.items[0].dislikes,0);assert.equal(result.items[0].my_vote,1);
  assert.ok(result.items[0].organic_score>0);assert.ok(!JSON.stringify(result).includes('PRIVATE'));
  assert.ok(!JSON.stringify(await call(reader,'/orders')).includes('PRIVATE'));
  assert.deepEqual((await call(reader,'/top-listings',{target_type:'orders',city:'Астана'})).items,[]);
  assert.deepEqual((await call(reader,'/top-listings',{target_type:'orders',category_id:'other'})).items,[]);
  for(const q of [{country:'BY'},{sort:'unknown'},{target_type:'unknown'}])await assert.rejects(()=>call(reader,'/top-listings',q),e=>e.getStatus()===400);
  for(const id of ineligible) await assert.rejects(()=>api.handle('PUT','/listing-votes/orders/'+id,{value:1},'Bearer '+reader.access_token,randomUUID(),{},'top-test'),e=>[404,409].includes(e.getStatus()));
  const profile={...base,id:randomUUID(),kind:'contractor',status:'published',display_name:undefined};await api.store.put(profile,{skipContentCheck:true});
  assert.equal((await call(reader,'/top-listings')).items[0].id,profile.id);
  await api.store.put({...await api.store.get(owner),verification:'expired'});
  assert.deepEqual((await call(reader,'/top-listings')).items,[]);
  await api.store.put({...await api.store.get(owner),verification:'passed'});
  const config={id:randomUUID(),kind:'ranking_config',owner:reader.user.id,country:'KZ',version:3,created_at:now,status:'effective',payload:{window_days:7,dislike_weight:2,age_days:14}};await api.store.put(config);
  const configured=await call(reader,'/top-listings',{target_type:'orders',sort:'new'});assert.equal(configured.meta.algorithm_id,config.id);assert.equal(configured.meta.algorithm_version,3);assert.equal(configured.meta.parameters.dislikeWeight,2);assert.ok(!configured.items.some(row=>row.id===winner.id),'new sorting uses publication time and ID rather than vote score');
  await api.store.put({id:randomUUID(),kind:'pair_block',owner:reader.user.id,country:'KZ',version:1,created_at:now,status:'active',target_id:owner});
  assert.deepEqual((await call(reader,'/top-listings',{target_type:'orders'})).items,[]);
  assert.throws(()=>rankingParameters({window_days:0,dislike_weight:1,age_days:30}),e=>e.getStatus()===400);
 }finally{await api.store.close();}
});
