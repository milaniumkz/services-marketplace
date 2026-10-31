const {test}=require('node:test');
const assert=require('node:assert/strict');
const {mkdtemp,writeFile,rm}=require('node:fs/promises');
const {tmpdir}=require('node:os');
const {join}=require('node:path');
const {serverMetrics}=require('../dist/server-metrics');
test('host metrics reject stale/corrupt snapshots and expose only resource counters',async()=>{
 const directory=await mkdtemp(join(tmpdir(),'joba-metrics-')),file=join(directory,'metrics.json'),now=Date.now();
 const sample={schema:1,source:'host',collected_at:new Date(now-20000).toISOString(),uptime_seconds:3600,cpu:{logical_cores:2,usage_percent:10,load_average:[0.1,0.2,0.3]},memory:{total_bytes:4096,used_bytes:1024,available_bytes:3072,usage_percent:25,swap_total_bytes:100,swap_used_bytes:0},disk:{total_bytes:8000,used_bytes:2000,available_bytes:6000,usage_percent:25},network:{received_bytes_per_second:20,sent_bytes_per_second:10},history:[],_sample:{private_counter:123},unexpected:'not returned'};
 try{
  await writeFile(file,JSON.stringify(sample));const data=await serverMetrics(file,now);
  assert.equal(data.available,true);assert.equal(data.age_seconds,20);assert.equal(data.cpu.logical_cores,2);assert.equal(data.memory.used_bytes,1024);assert.equal(data._sample,undefined);assert.equal(data.unexpected,undefined);
  await writeFile(file,JSON.stringify({...sample,collected_at:new Date(now-121000).toISOString()}));assert.equal((await serverMetrics(file,now)).available,false);
  await writeFile(file,JSON.stringify({...sample,memory:{...sample.memory,used_bytes:9000}}));assert.equal((await serverMetrics(file,now)).reason,'invalid_snapshot');
  await writeFile(file,'broken json');assert.equal((await serverMetrics(file,now)).available,false);
  await writeFile(file,'x'.repeat(262145));assert.equal((await serverMetrics(file,now)).reason,'invalid_snapshot');
 }finally{await rm(directory,{recursive:true,force:true});}
});
