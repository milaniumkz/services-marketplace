import {HttpException} from '@nestjs/common';
import {randomUUID} from 'node:crypto';
import {Store,RecordData} from './store';
export async function supportReadStates(store:Store,actor:string,country:string,threads:RecordData[]){
 const messages=await store.all('support_message',country),reads=await store.select('support_read',country,{owner:actor,limit:10000});
 const byThread=new Map(reads.map(r=>[r.thread_id,r])),owners=new Map(threads.map(t=>[t.id,t.owner])),counts=new Map<string,number>();
 for(const m of messages)if(owners.get(m.thread_id)===m.owner&&!m.tombstone&&m.sequence>(byThread.get(m.thread_id)?.sequence??0))counts.set(m.thread_id,(counts.get(m.thread_id)??0)+1);
 return threads.map(t=>{const read=byThread.get(t.id),unread=counts.get(t.id)??0;return {...t,unread_count:unread,is_read:!!read&&!unread,read_at:read?.read_at??null};});
}
export async function markSupportRead(store:Store,actor:{id:string;country:string},thread:RecordData,sequence:any){
 const messages=(await store.all('support_message',thread.country)).filter(m=>m.thread_id===thread.id),last=Math.max(0,...messages.map(m=>m.sequence??0));
 if(!Number.isSafeInteger(sequence)||sequence<0||sequence>last)throw new HttpException({error:{code:'VALIDATION_ERROR',message:'Проверьте прочитанную границу сообщений',retryable:false}},422);
 await store.db.query('SELECT pg_advisory_xact_lock(hashtextextended($1,0))',['support-read:'+actor.id+':'+thread.id]);
 const old=(await store.select('support_read',thread.country,{owner:actor.id,limit:10000})).find(r=>r.thread_id===thread.id),now=new Date().toISOString(),seen=Math.max(old?.sequence??0,sequence);
 if(!old||seen!==old.sequence)await store.put({id:old?.id??randomUUID(),kind:'support_read',owner:actor.id,country:thread.country,thread_id:thread.id,sequence:seen,read_at:now,created_at:old?.created_at??now,version:(old?.version??0)+1});
 const unseen=messages.some(m=>m.owner===thread.owner&&!m.tombstone&&m.sequence>seen);
 for(const n of await store.select('notification',thread.country,{owner:actor.id,limit:10000}))if(!n.read&&n.target_id===thread.id&&String(n.type).startsWith('support.')&&(typeof n.source_sequence==='number'?n.source_sequence<=seen:!unseen))await store.put({...n,read:true,version:n.version+1});
 return (await supportReadStates(store,actor.id,thread.country,[thread]))[0];
}
