import { WebSocket, WebSocketServer } from 'ws';
import { Marketplace } from './marketplace';
import { Server } from 'node:http';

/** Authenticated event stream; clients fetch object details with the usual object ACL. */
export function startRealtime(server:Server,marketplace:Marketplace) {
  const wss=new WebSocketServer({noServer:true,maxPayload:4096,handleProtocols:protocols=>protocols.has('joba.v1')?'joba.v1':false});
  const timers=new Set<ReturnType<typeof setInterval>>();
  server.on('upgrade',async(req,socket,head)=>{
    if(req.url?.split('?')[0]!=='/api/v1/events/ws')return;
    if(wss.clients.size>=1000){socket.destroy();return;}
    const protocols=String(req.headers['sec-websocket-protocol']??'').split(',').map(v=>v.trim());
    const credential=protocols.find(p=>p.startsWith('auth.'))?.slice(5);
    const token=req.headers.authorization??(credential?'Bearer '+credential:undefined);
    try {
      const user=await marketplace.handle('GET','/me',{},token);
      wss.handleUpgrade(req,socket,head,ws=>{
        let cursor=0,running=false,alive=true,dirty=false;
        ws.on('pong',()=>alive=true);
        ws.on('message',async raw=>{
          try{const q=JSON.parse(raw.toString());if(q.type==='resume'&&Number.isSafeInteger(q.after_sequence)&&q.after_sequence>=0)cursor=q.after_sequence;}catch{ws.close(1008,'Invalid event cursor');}
        });
        const pump=async()=>{
          if(running){dirty=true;return;}if(ws.readyState!==WebSocket.OPEN)return;running=true;
          try {
            const events=await marketplace.handle('GET','/events',{},token,undefined,{after_sequence:cursor});
            for(const event of events.items){ws.send(JSON.stringify(event));cursor=event.sequence;}
          }catch{ws.close(1008,'Session expired or revoked');}finally{running=false;if(dirty){dirty=false;void pump();}}
        };
        marketplace.events.on(user.id,pump);void pump();
        const timer=setInterval(pump,1000);timers.add(timer);
        const heartbeat=setInterval(()=>{if(!alive){ws.terminate();return;}alive=false;ws.ping();},30000);timers.add(heartbeat);
        ws.on('close',()=>{marketplace.events.off(user.id,pump);clearInterval(timer);clearInterval(heartbeat);timers.delete(timer);timers.delete(heartbeat);});
      });
    }catch{socket.destroy();}
  });
  return ()=>{for(const t of timers)clearInterval(t);for(const ws of wss.clients)ws.close(1001,'Server shutting down');wss.close();};
}
