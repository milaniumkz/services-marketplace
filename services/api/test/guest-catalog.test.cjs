const {test}=require('node:test');
const assert=require('node:assert/strict');
const {randomUUID}=require('node:crypto');
const {Marketplace}=require('../dist/marketplace');
const {Store}=require('../dist/store');

test('guests can search published services without receiving private fields',async()=>{
 const api=new Marketplace(new Store('memory://'));await api.initialize();
 try{
  const created_at=new Date().toISOString();
  const owner=randomUUID();
  await api.store.put({id:owner,owner,kind:'user',country:'KZ',version:1,created_at,status:'active',verification:'passed'});
  const id=randomUUID();
  const listing={id,owner,kind:'contractor',country:'KZ',version:1,created_at,status:'published',title:'Ремонт кухни',description:'Покраска стен',city:'Алматы',category_id:'repair',phone:'private',draft:{description:'private draft'}};
  await api.store.put(listing);
  await api.store.put({...listing,id:randomUUID(),title:'Ремонт скрытый',moderation_status:'hidden'});
  await api.store.put({...listing,id:randomUUID(),title:'Ремонт черновик',status:'draft'});
  const result=await api.handle('GET','/public/contractors',{},undefined,undefined,{country:'KZ',q:'Ремонт'},'test');
  assert.deepEqual(result.items,[{id,title:'Ремонт кухни',description:'Покраска стен',city:'Алматы',category_id:'repair'}]);
  assert.equal(result.next_cursor,null);
 }finally{await api.store.close();}
});
