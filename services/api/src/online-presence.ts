/** Authenticated foreground event connections; one person across all devices. */
export class OnlinePresence {
 private connections=new Map<string,{user:string;country?:string;seen:number}>();
 constructor(private clock=()=>Date.now(),readonly timeoutMs=65000){}
 connect(connection:string,user:{id:string;country?:string;status?:string;staff_access_mode?:string;staff_permissions?:string[]}){
  if(user.status==='active'&&user.staff_access_mode!=='managed'&&!user.staff_permissions?.length)this.connections.set(connection,{user:user.id,country:user.country,seen:this.clock()});
 }
 heartbeat(connection:string){const current=this.connections.get(connection);if(current)current.seen=this.clock();}
 disconnect(connection:string){this.connections.delete(connection);}
 private prune(){const now=this.clock();for(const [key,value]of this.connections)if(now-value.seen>this.timeoutMs)this.connections.delete(key);}
 count(country='ALL'){this.prune();return new Set([...this.connections.values()].filter(v=>country==='ALL'||v.country===country).map(v=>v.user)).size;}
 status(user:string){this.prune();return {online:[...this.connections.values()].some(v=>v.user===user),checked_at:new Date(this.clock()).toISOString()};}
}
