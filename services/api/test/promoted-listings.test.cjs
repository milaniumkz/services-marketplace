const {test}=require('node:test');const assert=require('node:assert/strict');const {randomUUID}=require('node:crypto');
const {Store}=require('../dist/store');const {promotedListings}=require('../dist/promoted-listings');
const record=(kind,owner,extra={})=>({id:randomUUID(),kind,owner,country:'KZ',version:1,created_at:new Date().toISOString(),...extra});
test('promoted inventory is separate, confirmed, scoped and eligible before capacity; current owner access and pair blocks take effect immediately',async()=>{
 const s=new Store('memory://');await s.initialize();try{
  const owner=randomUUID(),viewer=randomUUID(),now=new Date(),start=new Date(Date.now()-3600000).toISOString(),end=new Date(Date.now()+3600000).toISOString();
  await s.put({...record('user',owner,{status:'active',verification:'passed'}),id:owner});
  const access=record('grant',owner,{valid_until:end,capabilities:['search_full']});await s.put(access);
  await s.put(record('placement_policy',owner,{status:'effective',payload:{placement_id:'search.services.promoted',capacity:1}}));
  const hidden=record('contractor',owner,{title:'Скрытый профиль',city:'Алматы',status:'published',moderation_status:'hidden'}),visible=record('contractor',owner,{title:'Публичный профиль',city:'Алматы',status:'published'});await s.put(hidden);await s.put(visible);
  for(const t of [hidden,visible])await s.put(record('boost',owner,{target_id:t.id,placement_id:'search.services.promoted',provenance:'admin_grant',status:'active',starts_at:start,ends_at:end}));
  const result=await promotedListings(s,'KZ',viewer,'search.services.promoted',{city:'Алматы'},now);assert.equal(result.items.length,1);assert.equal(result.items[0].target.id,visible.id);assert.equal(result.items[0].promoted,true);assert.equal(result.organic_rank_changed,false);assert.equal(result.items[0].actor_id,undefined);
  assert.equal((await promotedListings(s,'KZ',viewer,'search.services.promoted',{city:'Астана'},now)).items.length,0);
  assert.equal((await promotedListings(s,'KG',viewer,'search.services.promoted',{},now)).items.length,0);
  await s.put({...access,valid_until:start,version:2});assert.equal((await promotedListings(s,'KZ',viewer,'search.services.promoted',{},now)).items.length,0);await s.put(access);
  await s.put(record('pair_block',viewer,{target_id:owner,status:'active'}));assert.equal((await promotedListings(s,'KZ',viewer,'search.services.promoted',{},now)).items.length,0);
 }finally{await s.close();}
});
