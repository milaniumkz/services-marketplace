// Public CC BY 4.0 DB-IP Lite snapshot. No user IP is sent to this endpoint.
const fs=require('node:fs'),path=require('node:path'),crypto=require('node:crypto'),zlib=require('node:zlib');
const target=path.resolve(__dirname,'../data/dbip-city-2026-11.mmdb');
const compressed='b69c625515f636ac92112b71df26bb92a5748f648c79bad124ecd9ba1c97bf4a';
const expected='5f64491f77c2c78b56cd83a88db4ea6c4666874322da38805498bbb754ccc735';
const sha=b=>crypto.createHash('sha256').update(b).digest('hex');
(async()=>{if(fs.existsSync(target)&&sha(fs.readFileSync(target))===expected)return;
 const r=await fetch('https://download.db-ip.com/free/dbip-city-lite-2026-11.mmdb.gz',{signal:AbortSignal.timeout(60000)});if(!r.ok)throw Error('DB-IP database download failed: '+r.status);
 const zip=Buffer.from(await r.arrayBuffer());if(sha(zip)!==compressed)throw Error('DB-IP compressed checksum mismatch');
 const data=zlib.gunzipSync(zip,{maxOutputLength:160*1024*1024});if(sha(data)!==expected)throw Error('DB-IP database checksum mismatch');
 fs.mkdirSync(path.dirname(target),{recursive:true});fs.writeFileSync(target+'.tmp',data);fs.renameSync(target+'.tmp',target);console.log('Verified DB-IP City Lite 2026-11 installed');
})().catch(e=>{console.error(e.message);process.exitCode=1;});
