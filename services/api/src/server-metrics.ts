import {readFile,stat} from 'node:fs/promises';

/** Host snapshots come from a local, unprivileged collector, never from user input. */
export async function serverMetrics(file=process.env.JOBA_SERVER_METRICS_FILE,now=Date.now()) {
  const unavailable=(reason:string)=>({available:false,reason,server_time:new Date(now).toISOString()});
  if(!file)return unavailable('collector_not_configured');
  try {
    if((await stat(file)).size>262144)return unavailable('invalid_snapshot');
    const value=JSON.parse(await readFile(file,'utf8'));
    const age=now-Date.parse(value.collected_at);
    const number=(v:any)=>typeof v==='number'&&Number.isFinite(v)&&v>=0;
    const percent=(v:any)=>number(v)&&v<=100;
    if(value.schema!==1||value.source!=='host'||!Number.isFinite(age)||age< -30000||age>120000)return unavailable('stale_snapshot');
    if(!number(value.uptime_seconds)||!Number.isInteger(value.cpu?.logical_cores)||value.cpu.logical_cores<1||!Array.isArray(value.cpu.load_average)||value.cpu.load_average.length!==3||!value.cpu.load_average.every(number)||!(value.cpu.usage_percent===null||percent(value.cpu.usage_percent)))return unavailable('invalid_snapshot');
    for(const group of ['memory','disk'])if(!['total_bytes','used_bytes','available_bytes'].every(key=>number(value[group]?.[key]))||!percent(value[group].usage_percent)||value[group].total_bytes<=0||value[group].used_bytes>value[group].total_bytes||value[group].available_bytes>value[group].total_bytes)return unavailable('invalid_snapshot');
    if(!number(value.memory.swap_total_bytes)||!number(value.memory.swap_used_bytes)||value.memory.swap_used_bytes>value.memory.swap_total_bytes)return unavailable('invalid_snapshot');
    const history=(Array.isArray(value.history)?value.history:[]).slice(-180).filter((p:any)=>Number.isFinite(Date.parse(p?.at))&&(p.cpu_percent===null||percent(p.cpu_percent))&&percent(p.memory_percent)&&percent(p.disk_percent)).map((p:any)=>({at:p.at,cpu_percent:p.cpu_percent,memory_percent:p.memory_percent,disk_percent:p.disk_percent}));
    const rate=(v:any)=>number(v)?v:null;
    return {available:true,source:'host',collected_at:value.collected_at,age_seconds:Math.max(0,Math.floor(age/1000)),refresh_seconds:20,uptime_seconds:value.uptime_seconds,
      cpu:{logical_cores:value.cpu.logical_cores,usage_percent:value.cpu.usage_percent,load_average:value.cpu.load_average},
      memory:{total_bytes:value.memory.total_bytes,used_bytes:value.memory.used_bytes,available_bytes:value.memory.available_bytes,usage_percent:value.memory.usage_percent,swap_total_bytes:value.memory.swap_total_bytes,swap_used_bytes:value.memory.swap_used_bytes},
      disk:{mount:'/',total_bytes:value.disk.total_bytes,used_bytes:value.disk.used_bytes,available_bytes:value.disk.available_bytes,usage_percent:value.disk.usage_percent},
      network:{received_bytes_per_second:rate(value.network?.received_bytes_per_second),sent_bytes_per_second:rate(value.network?.sent_bytes_per_second)},history};
  }catch{return unavailable('collector_unavailable');}
}
