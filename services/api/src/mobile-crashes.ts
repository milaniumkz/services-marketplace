import {HttpException} from '@nestjs/common';
import {Store} from './store';
const invalid=():never=>{throw new HttpException({error:{code:'INVALID_DIAGNOSTIC',message:'Некорректный диагностический отчёт',retryable:false}},400);};
export function redactDiagnostic(value:unknown,max=1200):string {
 return String(value??'').slice(0,max*2)
  .replace(/https?:\/\/[^\s<>]+/gi,'[url]')
  .replace(/Bearer\s+[^\s,;]+/gi,'Bearer [redacted]')
  .replace(/\beyJ[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+\b/g,'[token]')
  .replace(/\b(password|authorization|cookie|secret|api[_-]?key|access_token|refresh_token|nonce|pin)\b["']?\s*[:=]\s*["']?[^\s,;"'}]+/gi,'$1=[redacted]')
  .replace(/[\w.+-]+@[\w.-]+\.[A-Za-z]{2,}/g,'[email]')
  .replace(/\+?\d[\d ()-]{7,}\d/g,'[number]')
  .replace(/[\x00-\x08\x0b\x0c\x0e-\x1f]/g,'').slice(0,max);
}
export function crashReport(body:any,now=Date.now()) {
 if(!body||typeof body!=='object'||Array.isArray(body)||Buffer.byteLength(JSON.stringify(body))>24576)invalid();
 if(!/^[a-f0-9]{8}-[a-f0-9]{4}-[a-f0-9]{4}-[a-f0-9]{4}-[a-f0-9]{12}$/i.test(body.id??'')||!['flutter','unhandled_dart','android_java','android_exit','diagnostic_test'].includes(body.kind)||!['android','ios'].includes(body.platform))invalid();
 const occurred=Date.parse(body.occurred_at);if(!Number.isFinite(occurred)||occurred>now+300000||occurred<now-30*86400000)invalid();
 if(typeof body.fatal!=='boolean')invalid();
 const screen=(v:any)=>typeof v==='string'&&/^[a-z][a-z0-9-]{0,63}$/.test(v)?v:'unknown';
 const safe:any={id:body.id,kind:body.kind,platform:body.platform,fatal:body.fatal,occurred_at:new Date(occurred).toISOString(),app_version:redactDiagnostic(body.app_version,32),build:redactDiagnostic(body.build,16),device_model:redactDiagnostic(body.device_model,120),os_version:redactDiagnostic(body.os_version,80),screen:screen(body.screen),message:redactDiagnostic(body.message),stack:redactDiagnostic(body.stack,12000)};
 if(typeof body.installation_id==='string'&&/^[a-f0-9-]{36}$/i.test(body.installation_id))safe.installation_id=body.installation_id;
 safe.breadcrumbs=(Array.isArray(body.breadcrumbs)?body.breadcrumbs:[]).slice(-20).map((v:any)=>({screen:screen(v?.screen),at:Number.isFinite(Date.parse(v?.at))?new Date(v.at).toISOString():null}));
 for(const key of ['reason','status','pss_kb','rss_kb'])if(Number.isSafeInteger(body[key])&&body[key]>=0&&body[key]<=1e12)safe[key]=body[key];
 return safe;
}
export async function receiveMobileCrash(store:Store,body:any) {
 const report=crashReport(body);
 const inserted=await store.db.query('INSERT INTO mobile_crash_reports(id,report) VALUES($1,$2) ON CONFLICT(id) DO NOTHING RETURNING id',[report.id,JSON.stringify(report)]);
 if(inserted.rows.length)console.error(JSON.stringify({event:'mobile.crash.received',report_id:report.id,kind:report.kind,app_version:report.app_version,build:report.build,screen:report.screen}));
 return {accepted:true,id:report.id,duplicate:!inserted.rows.length};
}
export async function mobileCrashes(store:Store,q:any) {
 const limit=Math.min(100,Math.max(1,Number(q.limit)||30));
 const conditions:string[]=[],values:any[]=[];
 for(const key of ['id','kind','app_version','installation_id'])if(q[key]){values.push(String(q[key]).slice(0,100));conditions.push(key==='id'?`id::text=$${values.length}`:`report->>'${key}'=$${values.length}`);}
 values.push(Math.floor(limit));
 const rows=await store.db.query(`SELECT id::text,received_at,report FROM mobile_crash_reports ${conditions.length?'WHERE '+conditions.join(' AND '):''} ORDER BY received_at DESC,id DESC LIMIT $${values.length}`,values);
 return {items:rows.rows,retention_days:30,source:'client_reported'};
}
