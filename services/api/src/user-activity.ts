import {Store,RecordData} from './store';
/** Activity must never replace/version the user's editable profile. */
export class UserActivity {
 private recorded=new Map<string,number>();
 constructor(private store:Store,private clock=()=>Date.now()){}
 async touch(user:RecordData){
  if(user.status!=='active'||user.staff_access_mode==='managed'||user.staff_permissions?.length)return;
  const now=this.clock();if(now-(this.recorded.get(user.id)??-Infinity)<30000)return;
  this.recorded.set(user.id,now);
  try{await this.store.db.query("UPDATE records SET data=jsonb_set(data,'{last_seen_at}',to_jsonb($2::text),true) WHERE id=$1 AND kind='user' AND data->>'status'='active'",[user.id,new Date(now).toISOString()]);}
  catch{this.recorded.delete(user.id);}
  if(this.recorded.size>10000)for(const [id,seen]of this.recorded)if(now-seen>60000)this.recorded.delete(id);
 }
}
