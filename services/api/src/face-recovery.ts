import {createHash,randomBytes,randomUUID,timingSafeEqual} from 'node:crypto';
import {HttpException} from '@nestjs/common';
import {hash,verify} from '@node-rs/argon2';
import {Store,RecordData} from './store';
import {PrivateFiles} from './private-files';
export const FACE_NOTICE='Сохранить зашифрованный биометрический шаблон моего лица на сервере JOBA для восстановления пароля. Исходный снимок не сохраняется. Здесь выполняется только сравнение лица, без проверки живого присутствия: фотография или видео могут пройти такую проверку. Отключить способ и удалить шаблон можно в профиле.';
const digest=(s:string)=>createHash('sha256').update(s).digest('hex');
const fail=(message:string,status=422,code='FACE_RECOVERY_ERROR'):never=>{throw new HttpException({error:{code,message,details:{},retryable:status>=500}},status);};
const token=()=>randomBytes(32).toString('base64url');
const equal=(value:any,expected:any)=>{const a=Buffer.from(digest(String(value??''))),b=Buffer.from(String(expected??''));return a.length===b.length&&timingSafeEqual(a,b);};
const row=(kind:string,owner:string,country:string,data:any={})=>({id:randomUUID(),kind,owner,country,created_at:new Date().toISOString(),version:1,...data});
export interface FaceEngine {enabled:boolean;describe(photo:Buffer):Promise<number[]>;}
function normalized(v:any):number[]{if(!Array.isArray(v)||v.length!==128||v.some(x=>typeof x!=='number'||!Number.isFinite(x)))fail('Сервис сравнения лица недоступен.',503,'FACE_UNAVAILABLE');const norm=Math.sqrt(v.reduce((s:number,x:number)=>s+x*x,0));if(norm<1e-8)fail('Сервис сравнения лица недоступен.',503,'FACE_UNAVAILABLE');return v.map((x:number)=>x/norm);}
function photo(value:any){if(typeof value!=='string'||value.length>2800000||!(/^[A-Za-z0-9+/]+={0,2}$/).test(value))fail('Сделайте снимок лица в формате JPG или PNG до 2 МБ.');const b=Buffer.from(value,'base64');if(b.length>2*1024*1024||!(b.subarray(0,3).equals(Buffer.from([255,216,255]))||b.subarray(0,8).equals(Buffer.from([137,80,78,71,13,10,26,10]))))fail('Сделайте снимок лица в формате JPG или PNG до 2 МБ.');return b;}
export class LocalFaceEngine implements FaceEngine{
 readonly enabled=!!process.env.JOBA_FACE_SERVICE_URL;
 async describe(image:Buffer){if(!this.enabled)fail('Сервис сравнения лица пока недоступен.',503,'FACE_UNAVAILABLE');try{const r=await fetch(new URL('/embedding',process.env.JOBA_FACE_SERVICE_URL),{method:'POST',body:new Uint8Array(image),headers:{'Content-Type':'application/octet-stream'},signal:AbortSignal.timeout(20000)});const data:any=await r.json();if(!r.ok)fail(r.status===422?String(data.error):'Сервис сравнения лица временно недоступен.',r.status===422?422:503,r.status===422?'FACE_QUALITY':'FACE_UNAVAILABLE');if(data.model!=='opencv-sface-2021dec-yunet-2023mar-v1')fail('Модель сравнения недоступна.',503,'FACE_UNAVAILABLE');return normalized(data.embedding);}catch(e){if(e instanceof HttpException)throw e;return fail('Сервис сравнения лица временно недоступен. Повторите позже.',503,'FACE_UNAVAILABLE');}}
}
export class FaceRecovery {
 constructor(private store:Store,private files:PrivateFiles,readonly engine:FaceEngine=new LocalFaceEngine()){}
 private async lock(id:string){await this.store.db.query('SELECT pg_advisory_xact_lock(hashtextextended($1,0))',['face-account:'+id]);}
 private async template(id:string,country:string){return (await this.store.select('face_template',country,{owner:id,limit:1}))[0];}
 private async eligible(id:string){const u=await this.store.get(id);return u?.kind==='user'&&u.status==='active'&&!u.admin_blocked&&!u.staff_permissions?.length?u:undefined;}
 private async password(u:RecordData,value:any){const c=(await this.store.db.query<any>('SELECT password_hash FROM credentials WHERE user_id=$1 AND country=$2',[u.id,u.country])).rows[0];if(!c||typeof value!=='string'||!await verify(c.password_hash,value))fail('Подтвердите текущий пароль.',403,'REAUTH_REQUIRED');}
 private async expire(id:string){await this.store.db.query("UPDATE records SET version=version+1,data=data||jsonb_build_object('status','expired','version',version+1) WHERE kind='face_recovery_challenge' AND owner=$1 AND data->>'status' IN('pending','verified')",[id]);}
 async clearLogin(id:string){await this.lock(id);await this.expire(id);const u=await this.store.read(id),lookup=u?.phone?await this.files.requestDigest('face-login:'+u.country+':'+u.phone):'';await this.store.db.query("DELETE FROM records WHERE kind='face_login_counter' AND (owner=$1 OR data->>'lookup_hash'=$2)",[id,lookup]);}
 async revoke(id:string,country:string,reason='user_disabled'){
  await this.lock(id);const t=await this.template(id,country);if(t)await this.store.put({...t,status:'revoked',encrypted_vector:null,revoked_at:new Date().toISOString(),version:t.version+1});await this.expire(id);await this.store.db.query("DELETE FROM records WHERE kind IN('face_login_counter','face_recovery_challenge') AND owner=$1",[id]);
  if(t?.status==='active')await this.store.put(row('biometric_consent',id,country,{accepted:false,purpose:'password_recovery',reason,notice_version:1}));
 }
 async account(user:RecordData,method:string,b:any){
  if(!this.engine.enabled)fail('Сервис сравнения лица пока недоступен.',503,'FACE_UNAVAILABLE');
  await this.lock(user.id);const u=await this.eligible(user.id);if(!u)fail('Способ недоступен для этого аккаунта.',403);
  const old=await this.template(u!.id,u!.country),fresh=!old&&Date.now()-Date.parse(u!.created_at)<15*60000;
  if(method==='PATCH'){await this.store.put({...u!,face_recovery_prompted:true,version:u!.version+1});return {dismissed:true,version:u!.version+1};}
  if(method==='GET')return {prompt_required:!old&&!u!.face_recovery_prompted,enabled:true,enrolled:old?.status==='active',can_enroll_without_password:fresh,notice:FACE_NOTICE,liveness:false};
  if(method==='DELETE'){await this.password(u!,b.current_password);await this.revoke(u!.id,u!.country);return {disabled:true};}
  if(method!=='POST')fail('Действие не поддерживается.');
  if(b.consent!==true)fail('Для сохранения шаблона нужно ваше согласие.');
  if(!fresh)await this.password(u!,b.current_password);
  const vector=normalized(await this.engine.describe(photo(b.photo))),sealed=await this.files.sealSecret(JSON.stringify(vector),'face-template:'+u!.id);
  const t={...(old??row('face_template',u!.id,u!.country)),status:'active',model:'opencv-sface-v1',encrypted_vector:sealed,updated_at:new Date().toISOString(),version:(old?.version??0)+1};
  await this.store.put(t);await this.expire(u!.id);await this.store.put(row('biometric_consent',u!.id,u!.country,{accepted:true,purpose:'password_recovery',notice_version:1,notice_text:FACE_NOTICE,template_version:t.version}));
  return {enrolled:true,liveness:false};
 }
 // Called in its own transaction after a rejected login has rolled back.
 async failedLogin(b:any){
  if(!this.engine.enabled||!['KZ','RU','BY','KG'].includes(b.country)||!/^\+[0-9]{8,15}$/.test(String(b.phone)))return null;
  await this.store.db.exec('BEGIN');try{
   const lookup=await this.files.requestDigest('face-login:'+b.country+':'+b.phone);
   await this.lock(lookup);
   const c=(await this.store.db.query<any>('SELECT user_id FROM credentials WHERE country=$1 AND phone=$2',[b.country,b.phone])).rows[0],u=c?await this.eligible(c.user_id):undefined;
   const old=(await this.store.db.query<{data:RecordData}>("SELECT data FROM records WHERE kind='face_login_counter' AND country=$1 AND data->>'lookup_hash'=$2 LIMIT 1",[b.country,lookup])).rows[0]?.data;
   const failures=old?.expires_at>new Date().toISOString()?(old.failures??0)+1:1;
   await this.store.put({...old??row('face_login_counter',u?.id??'unknown',b.country),lookup_hash:lookup,failures,expires_at:new Date(Date.now()+10*60000).toISOString(),version:(old?.version??0)+1});
   let result=null;
   if(failures>=2){const nonce=token(),challenge=row('face_recovery_challenge',u?.id??'unknown',b.country,{status:'pending',nonce_hash:digest(nonce),attempts:0,expires_at:new Date(Date.now()+5*60000).toISOString()});await this.store.put(challenge);result={id:challenge.id,nonce,expires_at:challenge.expires_at};}
   await this.store.db.exec('COMMIT');return result;
  }catch(e){await this.store.db.exec('ROLLBACK');throw e;}
 }
 async public(path:string,b:any,passwordMin:(country:string)=>Promise<number>){
  const c=typeof b.id==='string'?await this.store.read(b.id):undefined;
  if(!c||c.kind!=='face_recovery_challenge')fail('Срок проверки истёк. Начните вход заново.',409);
  await this.store.get(c!.owner);await this.lock(c!.owner);const current=await this.store.get(c!.id);
  if(!this.engine.enabled)fail('Сервис сравнения лица недоступен.',503,'FACE_UNAVAILABLE');
  if(!current||current.expires_at<=new Date().toISOString()||!['pending','verified'].includes(current.status))fail('Срок проверки истёк. Начните вход заново.',409);
  const u=await this.eligible(current!.owner),t=u?await this.template(u.id,u.country):undefined;
  if(path.endsWith('/verify')){
   if(!equal(b.nonce,current!.nonce_hash))fail('Проверка недействительна.',403);
   if(current!.status==='verified'&&(!u||t?.status!=='active'||t.version!==current!.template_version))fail('Проверка недействительна.',403);
   if(current!.status==='verified')return {verified:true,reset_token:await this.files.unsealSecret(current!.reset_secret,'face-reset:'+current!.id)};
   if(current!.attempts>=5)fail('Лимит сравнения исчерпан. Начните вход заново.',429);
   let matched=false,message='Лицо не совпало или этот способ восстановления не настроен. Повторите снимок либо обратитесь в поддержку.';
   try{const image=photo(b.photo);if(u&&t?.status==='active'&&t.encrypted_vector){const v=normalized(await this.engine.describe(image)),ref=normalized(JSON.parse(await this.files.unsealSecret(t.encrypted_vector,'face-template:'+u.id)));matched=v.reduce((sum,x,i)=>sum+x*ref[i],0)>=0.45;}else await new Promise(resolve=>setTimeout(resolve,200));}
   catch(e){if(e instanceof HttpException&&e.getStatus()>=500)throw e;message=e instanceof HttpException?(e.getResponse() as any).error.message:message;}
   const updated={...current!,attempts:current!.attempts+1,version:current!.version+1};
   if(!matched){await this.store.put(updated);return {verified:false,message,attempts_remaining:5-updated.attempts};}
   const secret=token();await this.store.put({...updated,status:'verified',template_version:t!.version,reset_hash:digest(secret),reset_secret:await this.files.sealSecret(secret,'face-reset:'+current!.id)});
   return {verified:true,reset_token:secret};
  }
  if(!path.endsWith('/reset')||current!.status!=='verified'||!equal(b.reset_token,current!.reset_hash)||!u||t?.status!=='active'||t.version!==current!.template_version)fail('Разрешение на смену пароля недействительно.',403);
  const min=await passwordMin(u!.country);if(typeof b.new_password!=='string'||b.new_password.length<min||b.new_password.length>128)fail('Пароль должен содержать от '+min+' до 128 символов.');
  const credentials=(await this.store.db.query<any>('SELECT user_id FROM credentials WHERE user_id=$1 AND country=$2 FOR UPDATE',[u!.id,u!.country])).rows[0];if(!credentials)fail('Восстановление недоступно.',403);
  await this.store.db.query('UPDATE credentials SET password_hash=$1 WHERE user_id=$2 AND country=$3',[await hash(b.new_password,{memoryCost:19456,timeCost:2,parallelism:1}),u!.id,u!.country]);
  await this.store.db.query('UPDATE tokens SET revoked=true WHERE user_id=$1',[u!.id]);
  await this.store.put({...current!,status:'used',reset_secret:null,reset_hash:null,used_at:new Date().toISOString(),version:current!.version+1});await this.clearLogin(u!.id);
  await this.store.put(row('security_event',u!.id,u!.country,{event:'password.face_recovery_completed',occurred_at:new Date().toISOString(),liveness:false}));return {changed:true,login_required:true};
 }
}
