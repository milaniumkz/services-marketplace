import { ZipFile } from 'yazl';
import { Readable } from 'node:stream';
import { Store,RecordData } from './store';
import { PrivateFiles } from './private-files';

const fields:Record<string,string[]>={
 user:['display_name','phone','phone_status','city','roles','locale','avatar_id','verification','status'],
 contractor:['title','description','category_id','category_ids','work_modes','languages','service_cities','travel_radius_km','experience_years','availability','price','gallery_ids','status','draft'],
 order:['title','description','category_id','city','work_mode','budget_amount','currency','attributes','time_window','upload_ids','status','revision','executor_id','agreed_amount','published_at','completed_at'],
 offer:['order_id','text','amount','currency','status','acknowledged_revision','conversation_id'],
 portfolio:['title','description','category_id','photos','cover_id','position','order_id','rights_confirmed','status','draft'],
 content_revision:['source_id','source_kind','source_version','content'],
 review:['order_id','target_id','rating','text','status','published_at'],
 conversation:['order_id','members','status','read_sequences','delivered_sequences'],
 message:['thread_id','text','upload_ids','sequence','edited_at','tombstone'],
 support:['subject','status','last_activity','resolved_at'],
 support_message:['thread_id','text','upload_ids','sequence','edited_at','tombstone'],
 case:['target_type','target_id','description','reason_code','status','decision','reason','appeal_reason'],
 case_message:['case_id','text','upload_ids'],
 consent:['document_id','document_version','document_hash','accepted','sequence'],
 subscription:['provider','product_id','status','state','amount_minor','currency','valid_until','ends_at','canceled_at'],
 grant:['source','valid_until','capabilities','balance'],
 payment:['amount_minor','currency','status','product_id','provider','occurred_at'],
 invite:['order_id','recipient_id','status','order_revision'],
 amendment:['order_id','description','amount','reason','status'],
 cancel_request:['order_id','reason','status'],
 boost:['target_type','target_id','starts_at','ends_at','status','placement_id'],
 referral_reward:['campaign_id','status','capabilities','valid_until','redeemed_at'],
 notification:['type','target_id','read'],
 privacy:['type','status','completed_at','reason'],
};
export async function exportSnapshot(store:Store,owner:string,country:string){
 const raw:Record<string,RecordData[]>={};
 for(const kind of Object.keys(fields))raw[kind]=await store.all(kind,country);
 const chats=new Set(raw.conversation.filter(r=>r.members?.includes(owner)).map(r=>r.id));
 const support=new Set(raw.support.filter(r=>r.owner===owner).map(r=>r.id));
 const cases=new Set(raw.case.filter(r=>r.owner===owner||r.subject_user_id===owner).map(r=>r.id));
 const data:Record<string,any[]>={};
 for(const [kind,rows] of Object.entries(raw))data[kind]=rows.filter(r=>
  kind==='conversation'?chats.has(r.id):kind==='message'?chats.has(r.thread_id):kind==='support_message'?support.has(r.thread_id):kind==='case_message'?cases.has(r.case_id)&&!r.internal:
  kind==='order'?r.owner===owner||r.executor_id===owner:kind==='case'?cases.has(r.id):r.owner===owner
 ).map(r=>Object.fromEntries(['id','created_at','version',...fields[kind]].filter(key=>r[key]!==undefined).map(key=>[key,key==='draft'&&r.draft?Object.fromEntries(fields[kind].filter(field=>field!=='draft'&&r.draft[field]!==undefined).map(field=>[field,r.draft[field]])):(r.tombstone||r.moderation_status==='quarantined')&&['text','upload_ids'].includes(key)?key==='text'?'':[]:r[key]])));
 const attachments=(await store.all('upload',country)).filter(r=>r.owner===owner&&r.status==='clean'&&r.purpose!=='export');
 return {data,attachments};
}
function csvCell(value:any){
 let text=typeof value==='object'?JSON.stringify(value):String(value??'');
 if(/^[=+@\-\t\r]/.test(text))text="'"+text;
 return '"'+text.replaceAll('"','""')+'"';
}
export async function writeExport(files:PrivateFiles,id:string,snapshot:Awaited<ReturnType<typeof exportSnapshot>>,createdAt:string){
 const zip=new ZipFile();
 const output=zip.outputStream as Readable;
 zip.on('error',error=>output.destroy(error));
 zip.addBuffer(Buffer.from(JSON.stringify({format_version:1,created_at:createdAt,attachment_count:snapshot.attachments.length},null,2)),'manifest.json');
 zip.addBuffer(Buffer.from(JSON.stringify(snapshot.data,null,2)),'data.json');
 for(const [kind,rows] of Object.entries(snapshot.data)){
  const columns=['id','created_at','version',...fields[kind]];
  const content=[columns.map(csvCell).join(','),...rows.map(row=>columns.map(key=>csvCell(row[key])).join(','))].join('\r\n')+'\r\n';
  zip.addBuffer(Buffer.from('\uFEFF'+content),'csv/'+kind+'.csv');
 }
 for(const upload of snapshot.attachments){
  const extension=upload.mime==='image/jpeg'?'jpg':upload.mime==='image/png'?'png':upload.mime==='application/pdf'?'pdf':'bin';
  zip.addReadStreamLazy('attachments/'+upload.id+'.'+extension,callback=>{
   files.readStream(upload.id).then(stream=>callback(null,stream),error=>callback(error,Readable.from([])));
  });
 }
 const written=files.writeStream(id,output);zip.end();return written;
}
