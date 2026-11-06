const {test}=require('node:test'),assert=require('node:assert/strict'),{randomUUID}=require('node:crypto');
const {Store}=require('../dist/store'),{OsmGeocoder,geocode,geoPoint,orderAddress}=require('../dist/osm-geocoding'),{publicContent}=require('../dist/content-revisions');
test('OSM requests identify JOBA, serialize cache misses and reuse cached/in-flight searches',async()=>{
 const starts=[],urls=[];let finish;
 const provider=new OsmGeocoder(async(url,options)=>{starts.push(Date.now());urls.push(url);assert.match(options.headers['User-Agent'],/JOBA.*https:\/\/joba.com.kz/);if(url.searchParams.get('q')==='first')await new Promise(r=>finish=r);return new Response(JSON.stringify([]));},30);
 const one=provider.get('search',{q:'first'}),duplicate=provider.get('search',{q:'first'});await new Promise(r=>setTimeout(r,5));finish();await Promise.all([one,duplicate,provider.get('search',{q:'second'})]);assert.equal(starts.length,2);assert.ok(starts[1]-starts[0]>=25);await provider.get('search',{q:'second'});assert.equal(starts.length,2);assert.ok(urls.every(u=>u.origin==='https://nominatim.openstreetmap.org'));
 const failed=new OsmGeocoder(async()=>{throw Error('network unavailable')},0);await assert.rejects(()=>failed.get('reverse',{lat:'1',lon:'1'}),e=>e.getStatus()===503);
});
test('geocoding resolves against editable city data, validates region and coordinates, and does not expose precise order data',async()=>{
 const store=new Store('memory://');await store.initialize();try{
 const id=randomUUID();await store.put({id,kind:'city',owner:id,country:'KZ',version:1,created_at:new Date().toISOString(),name:'Тестовая Караганда',latitude:49.8,longitude:73.1,status:'active'});
 const provider={get:async(mode,params)=>{if(mode==='search')assert.equal(params.countrycodes,'kz');const value={lat:'49.8123456',lon:'73.1234567',display_name:'Тестовый адрес',address:{country_code:'kz'}};return mode==='search'?[value]:value;}};
 const result=await geocode(store,'KZ','search',{q:'Караганда улица'},provider);assert.equal(result.items[0].city.id,id);assert.equal(result.items[0].latitude,49.812346);assert.equal(result.attribution,'© OpenStreetMap contributors');
 const reverse=await geocode(store,'KZ','reverse',{latitude:49.8,longitude:73.1},provider);assert.equal(reverse.items[0].city.name,'Тестовая Караганда');
 await assert.rejects(()=>geocode(store,'KZ','reverse',{latitude:91,longitude:0},provider),e=>e.getStatus()===400);
 await assert.rejects(()=>geocode(store,'KZ','search',{q:'aa'},provider),e=>e.getStatus()===400);
 await assert.rejects(()=>geocode(store,'KZ','reverse',{latitude:49,longitude:73},{get:async()=>({lat:'49',lon:'73',address:{country_code:'ru'}})}),e=>e.getResponse().error.code==='LOCATION_OUTSIDE_COUNTRY');
 assert.throws(()=>geoPoint('',73),e=>e.getStatus()===400);assert.throws(()=>geoPoint(true,73),e=>e.getStatus()===400);assert.deepEqual(geoPoint(0,0),{latitude:0,longitude:0});
 const data=orderAddress({exact_address:'  улица, дом  ',exact_location:{latitude:49.81234567,longitude:73.12345678}});assert.equal(data.exact_address,'улица, дом');assert.deepEqual(data.public_location,{latitude:49.81,longitude:73.12,approximate:true});
 const visible=publicContent({id:'order',kind:'order',...data});assert.equal(visible.exact_address,undefined);assert.equal(visible.exact_location,undefined);assert.deepEqual(visible.public_location,data.public_location);assert.deepEqual(orderAddress({exact_location:null}),{exact_location:null,public_location:null});
 }finally{await store.close();}
});
test('order API saves GPS address, public search strips precise coordinates, assigned executor receives them',async()=>{
 const {Marketplace}=require('../dist/marketplace'),{paidCustomer}=require('./paid-customer-fixture.cjs');const api=new Marketplace(new Store('memory://'));await api.initialize();try{
 const call=(u,method,path,body={},query={})=>api.handle(method,path,body,u?'Bearer '+u.access_token:undefined,randomUUID(),query,'osm-address-test');
 const register=phone=>call(null,'POST','/auth/register',{country:'KZ',phone,password:'Isolated OSM password'});
 const customer=await register('+77000000971'),worker=await register('+77000000972');await paidCustomer(api,customer);
 await api.store.put({...await api.store.get(customer.user.id),verification:'passed'});await api.store.put({...await api.store.get(worker.user.id),roles:['customer','executor'],active_role:'executor',verification:'passed'});
 await api.store.put({id:randomUUID(),kind:'grant',owner:worker.user.id,country:'KZ',version:1,created_at:new Date().toISOString(),valid_until:new Date(Date.now()+86400000).toISOString(),capabilities:['search_full','send_offer']});
 const draft=await call(customer,'POST','/orders',{title:'Штукатурка стен дома',description:'Необходимо заштукатурить стены внутри дома.',category_id:'1',city:'Караганда',exact_address:'Приватный адрес 123',exact_location:{latitude:49.812345,longitude:73.123456}});
 const order=await call(customer,'POST','/orders/'+draft.id+'/publish',{expected_version:draft.version});
 const publicOrder=await call(worker,'GET','/orders/'+order.id);assert.equal(publicOrder.exact_address,undefined);assert.equal(publicOrder.exact_location,undefined);assert.equal(publicOrder.public_location.latitude,49.81);
 const page=await call(worker,'GET','/orders',{}, {near_lat:49.81,near_lon:73.12,radius_km:5});assert.ok(page.items.some(o=>o.id===order.id));assert.ok(page.items.every(o=>o.exact_address===undefined&&o.exact_location===undefined));
 const offer=await call(worker,'POST','/orders/'+order.id+'/offers',{text:'Готов выполнить работу',amount:100000,acknowledged_revision:order.revision});
 assert.equal((await call(worker,'GET','/offers/'+offer.id)).order.exact_location,undefined);
 await call(customer,'POST','/orders/'+order.id+'/select',{offer_id:offer.id,expected_version:order.version,offer_version:offer.version,contact_consent:true});
 const assigned=await call(worker,'GET','/orders/'+order.id);assert.equal(assigned.exact_address,'Приватный адрес 123');assert.deepEqual(assigned.exact_location,{latitude:49.812345,longitude:73.123456});
 }finally{await api.store.close();}
});
