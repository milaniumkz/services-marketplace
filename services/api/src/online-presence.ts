/** Authenticated, live event connections; never estimates registered accounts. */
export class OnlinePresence {
 private connections=new Map<string,{user:string;seen:number}>();
 constructor(private clock=()=>Date.now(),readonly timeoutMs=65000){}
 connect(connection:string,user:{id:string;status?:string;staff_permissions?:string[]}){
  if(user.status==='active'&&!user.staff_permissions?.length)this.connections.set(connection,{user:user.id,seen:this.clock()});
 }
 heartbeat(connection:string){const current=this.connections.get(connection);if(current)current.seen=this.clock();}
 disconnect(connection:string){this.connections.delete(connection);}
 count(){const now=this.clock();for(const [key,value]of this.connections)if(now-value.seen>this.timeoutMs)this.connections.delete(key);return new Set([...this.connections.values()].map(v=>v.user)).size;}
}
