const {test}=require('node:test');
const assert=require('node:assert/strict');
const {randomUUID}=require('node:crypto');
const {Marketplace}=require('../dist/marketplace');
const {Store}=require('../dist/store');

test('conversation inbox pages only own regional chats, searches linked names and titles, and hides moderated previews',async()=>{
 const api=new Marketplace(new Store('memory://'));await api.initialize();
 const call=(actor,method,path,body={},q={})=>api.handle(method,path,body,actor?'Bearer '+actor.access_token:undefined,randomUUID(),q);
 const register=(phone,country='KZ')=>call(null,'POST','/auth/register',{country,phone,password:'Isolated conversation inbox password!',display_name:'Участник'});
 try{
  const own=await register('+77005550101'),peer=await register('+77005550102'),stranger=await register('+77005550103'),foreign=await register('+375291112233','BY');
  await api.store.put({...await api.store.get(peer.user.id),display_name:'Алексей Кухонный'});
  const put=async(kind,data)=>api.store.put({id:randomUUID(),kind,country:'KZ',owner:own.user.id,created_at:new Date().toISOString(),version:1,...data});
  const order=await put('order',{title:'Сборка кухни',status:'in_progress'});
  const first=await put('conversation',{members:[own.user.id,peer.user.id],order_id:order.id,status:'working',read_sequences:{[own.user.id]:1}});
  const second=await put('conversation',{members:[own.user.id,peer.user.id],order_id:order.id,status:'closed'});
  await put('conversation',{owner:stranger.user.id,members:[stranger.user.id,peer.user.id],order_id:order.id,status:'open'});
  await put('conversation',{country:'BY',members:[own.user.id,foreign.user.id],order_id:order.id,status:'working'});
  await put('message',{owner:peer.user.id,thread_id:first.id,sequence:1,text:'Ранее прочитано'});
  await put('message',{owner:peer.user.id,thread_id:first.id,sequence:2,text:'Видимый ответ'});
  await put('message',{owner:peer.user.id,thread_id:first.id,sequence:3,text:'Скрытый секрет',moderation_status:'quarantined'});
  await put('message',{owner:own.user.id,thread_id:second.id,sequence:1,text:'Удалённый секрет',tombstone:true});
  const page=await call(own,'GET','/me/conversations',{}, {limit:'1'});assert.equal(page.items.length,1);assert.ok(page.meta.next_cursor);
  const next=await call(own,'GET','/me/conversations',{}, {limit:'1',cursor:page.meta.next_cursor});assert.equal(next.items.length,1);assert.equal(next.meta.next_cursor,null);
  const rows=[...page.items,...next.items];assert.deepEqual(new Set(rows.map(r=>r.id)),new Set([first.id,second.id]));
  const summary=rows.find(r=>r.id===first.id);assert.equal(summary.peer.display_name,'Алексей Кухонный');assert.equal(summary.peer.phone,undefined);
  assert.equal(summary.order_title,'Сборка кухни');assert.equal(summary.last_message.text,'Видимый ответ');assert.equal(summary.unread_count,1);
  assert.equal(rows.find(r=>r.id===second.id).last_message.text,'');assert.equal(JSON.stringify(rows).includes('секрет'),false);
  for(const q of ['кухни','Кухонный'])assert.equal((await call(own,'GET','/me/conversations',{}, {q})).items.length,2);
  assert.equal((await call(own,'GET','/me/conversations',{}, {q:'Несуществующий запрос'})).items.length,0);
  assert.equal((await call(foreign,'GET','/me/conversations')).items.length,1);
  assert.equal((await call(stranger,'GET','/me/conversations')).items.length,1);
 }finally{await api.store.close();}
});
