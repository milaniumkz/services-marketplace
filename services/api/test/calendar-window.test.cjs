const {test}=require('node:test');
const assert=require('node:assert/strict');
const {timeWindow}=require('../dist/validation');
test('calendar order dates follow the service timezone and include the final day across DST',()=>{
 const window=timeWindow({start_date:'2026-03-29',end_date:'2026-03-29',time_zone:'Europe/Belgrade'});
 assert.equal(window.start,'2026-03-28T23:00:00.000Z');assert.equal(window.end,'2026-03-29T22:00:00.000Z');
 assert.equal(Date.parse(window.end)-Date.parse(window.start),23*3600000);
 assert.deepEqual(timeWindow({start_date:'2026-10-14',end_date:'2026-10-16',time_zone:'Asia/Almaty'}),{
  start:'2026-10-13T19:00:00.000Z',end:'2026-10-16T19:00:00.000Z',time_zone:'Asia/Almaty',start_date:'2026-10-14',end_date:'2026-10-16'});
 for(const data of [{start_date:'2026-02-30',end_date:'2026-03-01',time_zone:'Asia/Almaty'},
  {start_date:'2026-10-16',end_date:'2026-10-14',time_zone:'Europe/Belgrade'},
  {start_date:'2026-10-14',end_date:'2026-10-16',time_zone:'bad/zone'}]){
  assert.throws(()=>timeWindow(data),e=>e.getResponse().error.code==='VALIDATION_ERROR');
 }
});
