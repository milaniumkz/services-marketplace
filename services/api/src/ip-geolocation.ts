import {BlockList,isIP} from 'node:net';
import {readFileSync} from 'node:fs';
import {resolve} from 'node:path';
import {Reader,CityResponse} from 'maxmind';

const reserved=new BlockList();
for(const [ip,bits] of [['0.0.0.0',8],['10.0.0.0',8],['100.64.0.0',10],['127.0.0.0',8],['169.254.0.0',16],['172.16.0.0',12],['192.0.0.0',24],['192.0.2.0',24],['192.168.0.0',16],['198.18.0.0',15],['198.51.100.0',24],['203.0.113.0',24],['224.0.0.0',4],['240.0.0.0',4]] as const)reserved.addSubnet(ip,bits,'ipv4');
for(const [ip,bits] of [['::',128],['::1',128],['fc00::',7],['fe80::',10],['ff00::',8],['2001:db8::',32],['100::',64],['2001:2::',48]] as const)reserved.addSubnet(ip,bits,'ipv6');
let reader:Reader<CityResponse>|undefined;
export function networkLocation(ip:unknown){
 const base={source:'ip_database',provider:'DB-IP City Lite',database_version:'2026-11',database_built_at:'2026-11-01T02:52:26.000Z',accuracy:'approximate',street_address:null};
 if(typeof ip!=='string'||!isIP(ip)||ip.includes('%'))return {...base,status:'unavailable',reason:'invalid_ip'};
 if(reserved.check(ip,isIP(ip)===4?'ipv4':'ipv6'))return {...base,status:'unavailable',reason:'non_public_ip'};
 try{
  reader??=new Reader<CityResponse>(readFileSync(resolve(__dirname,'../data/dbip-city-2026-11.mmdb')));
  const row=reader.get(ip);if(!row?.country?.iso_code)return {...base,status:'unavailable',reason:'not_in_database'};
  const name=(v:any)=>typeof v?.names?.ru==='string'?v.names.ru:typeof v?.names?.en==='string'?v.names.en:null;
  return {...base,status:'estimated',country_code:row.country.iso_code,country:name(row.country),region:name(row.subdivisions?.[0]),city:name(row.city)};
 }catch{return {...base,status:'unavailable',reason:'database_unavailable'};}
}
export function eventNetworkLocation(event:any){return event.network_location??{...networkLocation(event.ip),historical_lookup:true};}
