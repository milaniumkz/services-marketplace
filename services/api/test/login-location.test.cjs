const {test}=require('node:test'),assert=require('node:assert/strict');
const {Store}=require('../dist/store'),{Marketplace}=require('../dist/marketplace'),{networkLocation}=require('../dist/ip-geolocation'),{securityEventSummary}=require('../dist/staff-account'),{exportSnapshot}=require('../dist/privacy-export');
test('offline IP lookup has honest precision, handles IPv6 and never geolocates private/reserved/invalid addresses',()=>{
 for(const ip of ['8.8.8.8','::ffff:8.8.8.8','2a00:1450:4001:800::200e']){const g=networkLocation(ip);assert.equal(g.status,'estimated');assert.ok(g.city);assert.equal(g.street_address,null);assert.equal(g.latitude,undefined);assert.equal(g.database_version,'2026-11');}
 for(const ip of ['127.0.0.1','::ffff:127.0.0.1','10.0.0.1','100.64.1.1','192.0.2.1','2001:db8::1','fe80::1','fc00::1','224.1.1.1'])assert.equal(networkLocation(ip).reason,'non_public_ip',ip);
 for(const ip of ['local','8.8.8.8, 1.1.1.1','https://attacker.test',null,'::1%eth0'])assert.equal(networkLocation(ip).status,'unavailable');
});
test('login history retains separate locations for registration, failure, login and refresh; city snapshot/device/export are private and bounded',async()=>{
 const store=new Store('memory://'),api=new Marketplace(store);await api.initialize();try{
 const password='Isolated location test password!';
 const s=await api.handle('POST','/auth/register',{country:'KZ',phone:'+77000009531',password},undefined,undefined,{},'8.8.8.8','web','Browser fixture\n'+'x'.repeat(1000));
 await assert.rejects(()=>api.handle('POST','/auth/login',{country:'KZ',phone:'+77000009531',password:'incorrect'},undefined,undefined,{},'1.1.1.1'),e=>e.getStatus()===401);
 const signed=await api.handle('POST','/auth/login',{country:'KZ',phone:'+77000009531',password},undefined,undefined,{},'2a00:1450:4001:800::200e');
 await api.handle('POST','/auth/refresh',{refresh_token:signed.refresh_token},undefined,undefined,{},'1.1.1.1');
 const events=(await store.all('security_event','KZ')).filter(r=>r.owner===s.user.id),registered=events.find(r=>r.auth_action==='registered');
 assert.equal(registered.network_location.city,'Mountain View');assert.equal(registered.user_agent.length,512);assert.equal(registered.user_agent.includes('\n'),false);
 const failed=events.find(r=>r.event==='auth.login_failed');assert.equal(failed.network_location.country_code,'AU');assert.equal(failed.password,undefined);
 assert.equal(events.find(r=>r.auth_action==='login').network_location.country_code,'DE');assert.equal(events.find(r=>r.auth_action==='refresh').network_location.country_code,'AU');
 assert.equal((await store.get(registered.id)).network_location.city,'Mountain View');
 const summary=securityEventSummary(registered);assert.equal(summary.ip,undefined);assert.equal(summary.session_family,undefined);assert.equal(summary.network_location.historical_lookup,undefined);
 assert.equal(securityEventSummary({ip:'8.8.8.8'}).network_location.historical_lookup,true);
 const other=await api.handle('POST','/auth/register',{country:'KZ',phone:'+77000009532',password},undefined,undefined,{},'1.1.1.1');
 const exported=await exportSnapshot(store,s.user.id,'KZ');assert.ok(exported.data.security_event.some(r=>r.network_location?.city==='Mountain View'));assert.ok(exported.data.security_event.every(r=>events.some(e=>e.id===r.id)));assert.ok(exported.data.security_event.every(r=>!r.session_family));
 await assert.rejects(()=>api.handle('GET','/admin/security-events',{},'Bearer '+s.access_token),e=>e.getStatus()===403);
 }finally{await store.close();}
});
