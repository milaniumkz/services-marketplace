import {editableContent,publicContent,editContent,submitContent} from './content-revisions';
import { HttpException } from '@nestjs/common';
import { randomUUID, randomBytes, createHash } from 'node:crypto';
import { hash, verify } from '@node-rs/argon2';
import { RecordData, Store } from './store';
import { verifyTotp } from './totp';
import { parsePhoneNumberFromString } from 'libphonenumber-js/max';
import { Providers } from './providers';
import { Commerce } from './commerce';
import { PopplerPdfSanitizer } from './pdf-sanitizer';
import { PrivateFiles, ClamAvScanner } from './private-files';
import sharp from 'sharp';
import { Moderation, validateRules } from './moderation';
import { Configuration } from './configuration';
import { Growth } from './growth';
import { Branding } from './branding';
import { DEFAULT_SETTINGS,validateSettings,readSettings } from './settings';
import { seedReferenceData,referenceId } from './reference-data';
import { attributes,timeWindow } from './validation';
import { exportSnapshot,writeExport } from './privacy-export';
import { profileFields } from './contractor-profile';
import { EventEmitter } from 'node:events';

const digest = (s: string) => createHash('sha256').update(s).digest('hex');
const countries: Record<string, {currency: string; locales: string[]; cities: string[]}> = {
  KZ: {currency:'KZT',locales:['ru','kk'],cities:['Алматы','Астана','Шымкент']},
  RS: {currency:'RSD',locales:['sr'],cities:['Београд','Нови Сад']},
  RU: {currency:'RUB',locales:['ru'],cities:['Москва','Санкт-Петербург']},
  BY: {currency:'BYN',locales:['ru','be'],cities:['Минск','Гомель']}
};
export const fail = (status: number, code: string, message: string, details = {}): never => { throw new HttpException({error:{code,message,details,retryable:status===503}},status); };
const text = (b: any, name: string, min: number, max: number) => {
  const v=b?.[name]; if (typeof v !== 'string' || v.trim().length<min || v.length>max) fail(400,'VALIDATION_ERROR',`Проверьте поле ${name}`,{field:name,min,max});
  return v.trim();
};
const password = (b: any, name: string,min=15) => {
  const v=b?.[name];if(typeof v!=='string'||v.length<min||v.length>128)fail(400,'VALIDATION_ERROR','Пароль должен содержать от 15 до 128 символов');
  return v;
};
const safeUser = (u: RecordData) => ({id:u.id,display_name:u.display_name,city:u.city,country:u.country,roles:u.roles,locale:u.locale,languages:u.languages??[u.locale??'ru'],active_role:u.active_role??'customer',avatar_id:u.avatar_id,verification:u.verification,created_at:u.created_at});
type Actor = { id: string; country: string; family: string; user: RecordData; mfa: boolean };
export class Marketplace {
  readonly events=new EventEmitter().setMaxListeners(0);
  private uploadTasks=new Map<string,Promise<any>>();
  private scanSlots=2;
  private scanWaiters:Array<()=>void>=[];
  store: Store;
  readonly providers: Providers;
  readonly commerce: Commerce;
  readonly files: PrivateFiles;
  readonly configuration:Configuration;
  readonly growth:Growth;
  readonly branding:Branding;
  private queue: Promise<any> = Promise.resolve();
  constructor(store = new Store(), providers = new Providers(), files = new PrivateFiles()) {
    this.store=store;this.providers=providers;this.commerce=new Commerce(store,providers);this.files=files;
    this.configuration=new Configuration(store,providers);this.growth=new Growth(store,providers);this.branding=new Branding(store,files);
    const moderation=new Moderation(store);store.contentHook=data=>moderation.check(data);
    if(process.env.JOBA_CLAMSCAN_PATH)providers.scanner=new ClamAvScanner();
    if(process.env.JOBA_PDFTOPPM_PATH)providers.pdfSanitizer=new PopplerPdfSanitizer();
  }
  async initialize() { await this.store.initialize();await seedReferenceData(this.store); }
  private record(kind: string, actor: {id:string;country:string}, data: any = {}): RecordData { return {...data,id:randomUUID(),kind,owner:actor.id,country:actor.country,version:1,created_at:new Date().toISOString()}; }
  private async limited(key:string,max=20){
    const scope=await this.files.requestDigest('rate-limit:'+key);
    const result=await this.store.db.query<any>(`INSERT INTO rate_limits(scope_hash,window_start,attempts) VALUES($1,CURRENT_TIMESTAMP,1)
      ON CONFLICT(scope_hash) DO UPDATE SET
        attempts=CASE WHEN rate_limits.window_start<=CURRENT_TIMESTAMP-INTERVAL '60 seconds' THEN 1 ELSE rate_limits.attempts+1 END,
        window_start=CASE WHEN rate_limits.window_start<=CURRENT_TIMESTAMP-INTERVAL '60 seconds' THEN CURRENT_TIMESTAMP ELSE rate_limits.window_start END
      RETURNING attempts`,[scope]);
    if(result.rows[0].attempts>max)fail(429,'RATE_LIMITED','Слишком много попыток. Повторите позже.');
  }
  private async tokens(user: RecordData, family=randomUUID(), mfa=false,ip='unknown') {
    const settings=await this.settings(user.country);
    const access=randomBytes(32).toString('base64url'), refresh=randomBytes(48).toString('base64url');
    for (const [value,kind,ttl] of [[access,'access',settings.access_seconds],[refresh,'refresh',settings.refresh_days*86400]] as const) {
      await this.store.db.query('INSERT INTO tokens(hash,family,user_id,country,kind,expires_at,mfa_verified) VALUES($1,$2,$3,$4,$5,$6,$7)',[digest(value),family,user.id,user.country,kind,new Date(Date.now()+ttl*1000).toISOString(),mfa]);
    }
    await this.store.put(this.record('security_event',{id:user.id,country:user.country},{event:'session.credentials_issued',ip,session_family:family,mfa,occurred_at:new Date().toISOString()}));
    return {access_token:access,refresh_token:refresh,expires_in:settings.access_seconds,user:{...safeUser(user),phone:user.phone,phone_status:'unverified'}};
  }
  private async actor(authorization?: string): Promise<Actor> {
    const token=authorization?.match(/^Bearer ([A-Za-z0-9_-]+)$/)?.[1];
    if(!token) fail(401,'UNAUTHENTICATED','Требуется вход');
    const t=(await this.store.db.query<any>('SELECT * FROM tokens WHERE hash=$1 AND kind=\'access\' AND NOT revoked AND expires_at>now()',[digest(token!)])).rows[0];
    if(!t) fail(401,'TOKEN_EXPIRED','Сессия истекла');
    const user=await this.store.get(t.user_id);if(!user || user.status==='deleted')fail(401,'UNAUTHENTICATED','Требуется вход');
    return {id:user!.id,country:t.country,family:t.family,user:user!,mfa:t.mfa_verified};
  }
  private async object(id: string, a: Actor, kind?: string, own=false) {
    const r=await this.store.get(id);
    if(!r || r.country!==a.country || (kind&&r.kind!==kind) || (own&&r.owner!==a.id))fail(404,'NOT_FOUND','Объект не найден');
    return r!;
  }
  private version(r: RecordData, b: any) {
    if(b.expected_version!==r.version)fail(409,'STATE_CONFLICT','Данные изменились. Обновите экран.',{current_version:r.version});
  }
  private async entitlement(a: Actor, capability: string, verified=false) {
    if(a.user.status!=='active')fail(403,'FORBIDDEN','Новые действия ограничены. Поддержка доступна.');
    if(verified&&!a.user.roles.includes('executor'))fail(403,'EXECUTOR_ROLE_REQUIRED','Настройте роль исполнителя');
    if(verified&&a.user.verification!=='passed')fail(403,'VERIFICATION_REQUIRED','Требуется проверка документа исполнителя');
    if(['publish_order','select_offer','send_offer','publish_profile'].includes(capability)) {
      const current=(await this.store.all('legal_document',a.country)).filter(d=>d.status==='published'&&d.locale===(a.user.locale??'ru')&&['privacy','privacy_policy','terms','terms_of_use'].includes(d.type)).sort((x,y)=>String(y.published_at??y.created_at).localeCompare(String(x.published_at??x.created_at))||y.id.localeCompare(x.id));
      const checked=new Set<string>();
      for(const document of current) {
        const type=['privacy','privacy_policy'].includes(document.type)?'privacy':'terms';if(checked.has(type))continue;checked.add(type);
        const consent=(await this.store.db.query<any>("SELECT data FROM records WHERE kind='consent' AND country=$1 AND owner=$2 AND data->>'document_id'=$3 ORDER BY (data->>'sequence')::integer DESC LIMIT 1",[a.country,a.id,document.id])).rows[0]?.data;
        if(!consent?.accepted||consent.document_hash!==document.hash)fail(403,'CONSENT_REQUIRED','Примите текущую версию условий и политики конфиденциальности',{document_id:document.id});
      }
    }
    if(capability==='send_offer'){const profile=(await this.store.all('contractor',a.country)).find(r=>r.owner===a.id);if(profile?.status==='paused'||profile?.availability==='paused')fail(403,'FORBIDDEN','Приём новых предложений приостановлен');}
    await this.promotionGrant(a);
    const grants=(await this.store.select('grant',a.country,{owner:a.id,limit:1000})).filter(r=>r.owner===a.id && r.valid_until>new Date().toISOString() && r.capabilities.includes(capability)&&(r.balance===undefined||r.balance>0));
    if(!grants.length)fail(403,'ENTITLEMENT_REQUIRED','Нужен действующий доступ',{capability});
    const selected=grants.find(g=>g.balance===undefined)??grants[0];
    if(selected.balance!==undefined&&['publish_order','send_offer','select_offer'].includes(capability)) {
      await this.store.put({...selected,balance:selected.balance-1,version:selected.version+1});
      await this.store.put(this.record('entitlement_consumption',a,{grant_id:selected.id,capability,consumed_at:new Date().toISOString()}));
    }
  }
  private async staff(a: Actor, permission: string) {
    const has=a.user.staff_permissions?.includes(permission)||(!['identity_view','verification_reviewer'].includes(permission)&&a.user.staff_permissions?.includes('administrator'));
    if(!has||!a.mfa||a.user.status!=='active')fail(403,'FORBIDDEN','Недостаточно служебных прав или MFA');
  }
  async handle(method: string, path: string, body: any={}, authorization?: string, key?: string, query: any={}, ip='local') {
    if(path.startsWith('/auth/')||path.startsWith('/public/')&&!path.startsWith('/public/recovery-threads')||path.startsWith('/webhooks/'))key=undefined;
    // Serialize commands: version check, idempotency, business writes and outbox commit together.
    const run = async () => {
      if(method==='GET')return this.dispatch(method,path,body,authorization,query,ip);
      let actor: Actor|undefined;
      if(!path.startsWith('/auth/')&&!path.startsWith('/public/')&&!path.startsWith('/webhooks/'))actor=await this.actor(authorization);
      // Counters commit independently of rejected business commands.
      if(actor)await this.limited('mutations:'+actor.id,120);
      if(path==='/auth/register')await this.limited('register:'+ip,5);
      if(['/auth/login','/auth/staff-login'].includes(path)){await this.limited('login:'+ip,10);await this.limited('login-account:'+String(body.country)+':'+String(body.phone),10);}
      if(path==='/auth/refresh')await this.limited('refresh:'+ip);
      if(path==='/public/recovery-threads')await this.limited('recovery:'+ip,3);
      if(path.startsWith('/public/recovery-threads/')&&path.endsWith('/messages'))await this.limited('recovery-messages:'+ip);
      if(path.startsWith('/listing-votes/')&&actor)await this.limited('votes:'+actor.id,30);
      const exempt=path.startsWith('/auth/')||path.startsWith('/public/')||path.startsWith('/webhooks/');
      if(key&&!/^[A-Za-z0-9_-]{8,128}$/.test(key)||!exempt&&!key)fail(400,'VALIDATION_ERROR','Требуется Idempotency-Key');
      const scope=`${actor?.id??ip}:${method}:${path}`, bodyHash=key?await this.files.requestDigest(Buffer.isBuffer(body)?body.toString('base64'):JSON.stringify(body)):'';
      await this.store.db.exec('BEGIN');
      try {
        if(key)await this.store.db.query('SELECT pg_advisory_xact_lock(hashtextextended($1,0))',[scope+':'+key]);
        const cached=key?(await this.store.db.query<any>('SELECT * FROM idempotency WHERE scope=$1 AND key=$2',[scope,key])).rows[0]:null;
        if(cached){if(cached.body_hash!==bodyHash)fail(409,'IDEMPOTENCY_CONFLICT','Ключ уже использован с другими данными');await this.store.db.exec('COMMIT');return cached.result;}
        const rawResult=await this.dispatch(method,path,body,authorization,query,ip);
        const result=JSON.parse(JSON.stringify(rawResult??null));
        if(key)await this.store.db.query('INSERT INTO idempotency(scope,key,body_hash,result) VALUES($1,$2,$3,$4)',[scope,key,bodyHash,JSON.stringify(result??null)]);
        await this.store.db.exec('COMMIT');return result;
      } catch(e) {
        // Refresh replay must durably revoke the entire family, even when rejected.
        if(e instanceof HttpException && (e.getResponse() as any)?.error?.code==='REFRESH_REPLAY')await this.store.db.exec('COMMIT');
        else await this.store.db.exec('ROLLBACK');
        throw e;
      }
    };
    const pending=this.queue.then(run,run);this.queue=pending.catch(()=>{});
    const finalize=method==='POST'?path.match(/^\/uploads\/([^/]+)\/finalize$/):null;
    if(finalize)return pending.then(async result=>{
      if(!['processing','scanning'].includes(result?.status))return result;
      const finished=await this.processUpload(finalize[1]);
      if(['SCANNER_UNAVAILABLE','PDF_SANITIZER_UNAVAILABLE','FILE_PROCESSING_UNAVAILABLE'].includes(finished.failure_code))fail(503,finished.failure_code,'Проверка недоступна. Файл остаётся закрытым.');
      if(finished.status==='rejected')fail(422,'POLICY_REJECTED','Файл не прошёл безопасную обработку');
      return finished;
    });
    return pending;
  }
  private async dispatch(method: string,path: string,b: any,authorization: string|undefined,q: any,ip: string): Promise<any> {
    const db=this.store.db;
    path=path.replace(/\/select-offer$/, '/select').replace(/\/request-completion$/, '/complete');
    const orderReview=path.match(/^\/orders\/([^/]+)\/reviews$/);if(orderReview){b={...b,order_id:orderReview[1]};path='/reviews';}
    if(path==='/reports')path='/cases';
    if(path==='/public/config'&&method==='GET')return {countries:Object.entries(countries).map(([code,c])=>({code,name:({KZ:'Казахстан',RS:'Сербия',RU:'Россия',BY:'Беларусь'} as Record<string,string>)[code],...c,launch_status:'unverified',checkout_enabled:false})),subscription_enabled:true,banner_ads_enabled:false,rewarded_access_enabled:false,minimum_supported_version:'0.1.0',mode:'development',server_time:new Date().toISOString()};
    if(path==='/legal/documents'&&method==='GET') {
      if(!countries[q.country??'KZ']||q.locale&&!['ru','kk','sr','be'].includes(q.locale))fail(400,'VALIDATION_ERROR','Проверьте страну и язык');
      const versions=(await this.store.all('legal_document',q.country??'KZ')).filter(x=>x.status==='published'&&(!q.locale||x.locale===q.locale)).sort((a,b)=>String(b.published_at??b.created_at).localeCompare(String(a.published_at??a.created_at))||b.id.localeCompare(a.id));
      const seen=new Set<string>(),visible=q.all_versions==='true'?versions:versions.filter(d=>{const key=d.type+':'+d.locale;if(seen.has(key))return false;seen.add(key);return true;});
      return {items:visible.map(({id,country,type,locale,content,hash,version,created_at,published_at})=>({id,country,type,locale,content,hash,version,created_at,published_at}))};
    }
    const webhook=path.match(/^\/webhooks\/(billing|ads)\/([^/]+)$/);
    if(webhook&&method==='POST') {
      if(!b.raw_body||!b.headers)fail(400,'VALIDATION_ERROR','Требуется исходное тело webhook');
      return webhook[1]==='billing'?this.commerce.webhook(webhook[2],b.raw_body,b.headers):this.commerce.rewardCallback(webhook[2],b.raw_body,b.headers);
    }
    const privateDownload=path.match(/^\/private-files\/([^/]+)$/);
    if(privateDownload&&method==='GET') {
      const found=(await db.query<{data:RecordData}>("SELECT data FROM records WHERE kind='download_ticket' AND data->>'token_hash'=$1 AND data->>'upload_id'=$2 AND data->>'status'='active' AND data->>'expires_at'>$3 LIMIT 1",[digest(String(q.token)),privateDownload[1],new Date().toISOString()])).rows[0]?.data;
      if(!found)fail(404,'NOT_FOUND','Ссылка истекла или недействительна');
      const valid=(await db.query<any>("SELECT mfa_verified FROM tokens WHERE family=$1 AND kind='access' AND NOT revoked AND expires_at>now() LIMIT 1",[found.family])).rows[0];
      const user=await this.store.get(found.owner);if(!valid||!user||user.status==='deleted')fail(404,'NOT_FOUND','Ссылка недействительна');
      const actor:Actor={id:user!.id,country:found.country,family:found.family,user:user!,mfa:valid.mfa_verified};
      const upload=await this.object(found.upload_id,actor,'upload');await this.authorizeFile(upload,actor,{reason:found.reason});
      const claimed=await db.query("UPDATE records SET data=jsonb_set(jsonb_set(data,'{status}','\"used\"'::jsonb),'{version}',to_jsonb(version+1)),version=version+1 WHERE id=$1 AND data->>'status'='active' RETURNING id",[found.id]);
      if(!claimed.rows.length)fail(404,'NOT_FOUND','Ссылка уже использована');if(upload.purpose==='export')return {download_stream:await this.files.readStream(upload.id),download_size:upload.stored_size??upload.size,mime:upload.mime};return {download_buffer:await this.files.read(found.variant==='preview'&&upload.preview_file_id?upload.preview_file_id:upload.id),mime:upload.mime};
    }
    if(path==='/auth/register'&&method==='POST') {
      const country=text(b,'country',2,2);if(!countries[country])fail(400,'VALIDATION_ERROR','Недопустимая страна');
      if(process.env.JOBA_REGION&&country!==process.env.JOBA_REGION)fail(403,'COUNTRY_DISABLED','Выбран неверный региональный endpoint');
      const phone=text(b,'phone',8,16);const number=parsePhoneNumberFromString(phone);
      if(!number?.isValid()||number.country!==country||number.number!==phone)fail(400,'VALIDATION_ERROR','Проверьте формат номера и выбранную страну');
      const secret=password(b,'password',(await this.settings(country)).password_min);
      if((await db.query('SELECT 1 FROM credentials WHERE country=$1 AND phone=$2',[country,phone])).rows.length)fail(409,'REGISTRATION_UNAVAILABLE','Не удалось зарегистрироваться. Обратитесь в поддержку.');
      const locale=b.locale??countries[country].locales[0];if(!['ru','kk','sr','be'].includes(locale))fail(400,'VALIDATION_ERROR','Язык не поддерживается');
      const u=this.record('user',{id:'',country},{phone,phone_status:'unverified',display_name:b.display_name===undefined?'':text(b,'display_name',2,60),locale,city:'',roles:['customer'],verification:'not_started',status:'active'});u.owner=u.id;
      await this.store.put(u);await db.query('INSERT INTO credentials(country,phone,user_id,password_hash) VALUES($1,$2,$3,$4)',[country,phone,u.id,await hash(secret,{memoryCost:19456,timeCost:2,parallelism:1})]);
      return this.tokens(u,randomUUID(),false,ip);
    }
    if(['/auth/login','/auth/staff-login'].includes(path)&&method==='POST') {
      if(process.env.JOBA_REGION&&b.country!==process.env.JOBA_REGION)fail(401,'INVALID_CREDENTIALS','Неверный номер или пароль');
      const c=(await db.query<any>('SELECT * FROM credentials WHERE country=$1 AND phone=$2',[String(b.country),String(b.phone)])).rows[0];
      // Hash even nonexistent credentials to avoid the obvious timing distinction.
      const ok=c?await verify(c.password_hash,String(b.password)):await hash(String(b.password??''),{memoryCost:19456,timeCost:2,parallelism:1}).then(()=>false);
      if(!ok)fail(401,'INVALID_CREDENTIALS','Неверный номер или пароль');
      const u=await this.store.get(c.user_id);if(!u || u.status==='deleted')fail(401,'INVALID_CREDENTIALS','Неверный номер или пароль');
      if(path==='/auth/staff-login') {
        const secret=u!.totp_secret_sealed?await this.files.unsealSecret(u!.totp_secret_sealed,u!.id):process.env.NODE_ENV==='production'?undefined:u!.totp_secret;
        if(!u!.staff_permissions?.length||!secret||!verifyTotp(secret,String(b.mfa_code)))fail(401,'INVALID_CREDENTIALS','Неверные служебные данные или второй фактор');
        if(u!.last_totp_step===Math.floor(Date.now()/30000)||u!.last_totp_code_hash===digest(String(b.mfa_code)))fail(401,'MFA_REPLAY','Код уже использован');
        await this.store.put({...u!,last_totp_step:Math.floor(Date.now()/30000),last_totp_code_hash:digest(String(b.mfa_code)),version:u!.version+1});
        return this.tokens(u!,randomUUID(),true,ip);
      }
      if(u!.staff_permissions?.length)fail(401,'INVALID_CREDENTIALS','Используйте отдельный служебный вход');
      return this.tokens(u!,randomUUID(),false,ip);
    }
    if(path==='/auth/refresh'&&method==='POST') {
      const t=(await db.query<any>('SELECT * FROM tokens WHERE hash=$1 AND kind=\'refresh\' FOR UPDATE',[digest(String(b.refresh_token))])).rows[0];
      if(t?.used){await db.query('UPDATE tokens SET revoked=true WHERE family=$1',[t.family]);fail(401,'REFRESH_REPLAY','Сессия отозвана');}
      if(!t||t.revoked||new Date(t.expires_at).getTime()<=Date.now())fail(401,'TOKEN_EXPIRED','Сессия истекла');
      await db.query('UPDATE tokens SET used=true WHERE hash=$1',[t.hash]);
      await db.query('UPDATE tokens SET revoked=true WHERE family=$1 AND kind=\'access\'',[t.family]);
      return this.tokens((await this.store.get(t.user_id))!,t.family,t.mfa_verified,ip);
    }
    if(path==='/public/recovery-threads'&&method==='POST') {
      if(!countries[b.country])fail(400,'VALIDATION_ERROR','Выберите страну');
      const secret=randomBytes(32).toString('base64url');
      const t=this.record('recovery',{id:'anonymous',country:b.country},{capability_hash:digest(secret),status:'new',subject:text(b,'subject',5,120),expires_at:new Date(Date.now()+86400000).toISOString()});
      await this.store.put(t);await this.store.put(this.record('recovery_message',{id:'anonymous',country:b.country},{thread_id:t.id,text:text(b,'text',1,3000),sequence:1}));
      return {id:t.id,capability:secret,status:t.status};
    }
    const recovery=path.match(/^\/public\/recovery-threads\/([^/]+)\/messages$/);
    if(recovery) {
      const t=await this.store.get(recovery[1]);
      if(!t||t.kind!=='recovery'||t.capability_hash!==digest(String(authorization?.replace('Bearer ','')))||t.expires_at<=new Date().toISOString())fail(404,'NOT_FOUND','Обращение не найдено');
      const messages=(await this.store.all('recovery_message',t!.country)).filter(x=>x.thread_id===t!.id);
      if(method==='GET')return {items:messages};
      if(method==='POST'){const m=this.record('recovery_message',{id:'anonymous',country:t!.country},{thread_id:t!.id,text:text(b,'text',1,3000),sequence:messages.length+1});return this.store.put(m);}
    }
    const a=await this.actor(authorization);
    const settings=await this.settings(a.country);
    if(a.user.staff_permissions?.length&&(path.startsWith('/orders')||path.startsWith('/me/contractor-profile')||path.startsWith('/me/portfolio-projects')||path==='/reviews'))fail(403,'FORBIDDEN','Для действий на бирже используйте отдельный пользовательский аккаунт');
    q={...q,_scope:a.id+':'+path};
    if(path==='/auth/logout'&&method==='POST'){await db.query('UPDATE tokens SET revoked=true WHERE family=$1',[a.family]);return {logged_out:true};}
    if(path==='/auth/logout-all'&&method==='POST') {
      await this.reauth(a,b);await db.query('UPDATE tokens SET revoked=true WHERE user_id=$1',[a.id]);return {logged_out:true};
    }
    if(path==='/me'&&method==='GET')return {...safeUser(a.user),phone:a.user.phone,phone_status:'unverified',status:a.user.status,version:a.user.version};
    if(path==='/me'&&method==='PATCH') {
      this.version(a.user,b);const changes:any={};
      for(const [f,min,max] of [['display_name',2,60],['city',0,100],['locale',2,5]] as const)if(b[f]!==undefined)changes[f]=text(b,f,min,max);
      if(changes.locale&&!['ru','kk','sr','be'].includes(changes.locale))fail(400,'VALIDATION_ERROR','Язык не поддерживается');
      if(b.roles!==undefined){if(!Array.isArray(b.roles)||!b.roles.length||b.roles.some((r:string)=>!['customer','executor'].includes(r)))fail(400,'VALIDATION_ERROR','Недопустимая доменная роль');changes.roles=[...new Set(b.roles)];}
      if(b.languages!==undefined){if(!Array.isArray(b.languages)||!b.languages.length||b.languages.length>5||b.languages.some((v:string)=>!['ru','kk','sr','be','en'].includes(v)))fail(400,'VALIDATION_ERROR','Проверьте языки общения');changes.languages=[...new Set(b.languages)];}
      if(b.active_role!==undefined){if(!['customer','executor'].includes(b.active_role)||!(changes.roles??a.user.roles).includes(b.active_role))fail(400,'VALIDATION_ERROR','Эта роль ещё не настроена');changes.active_role=b.active_role;}
      if(changes.roles&&!changes.roles.includes(changes.active_role??a.user.active_role??'customer'))changes.active_role=changes.roles[0];
      if(b.avatar_id===null)changes.avatar_id=null;
      else if(b.avatar_id!==undefined){const u=await this.object(String(b.avatar_id),a,'upload',true);if(u.status!=='clean'||u.purpose!=='avatar')fail(422,'UNSAFE_UPLOAD','Аватар ещё не проверен');changes.avatar_id=u.id;}
      return this.store.put({...a.user,...changes,version:a.user.version+1}).then(u=>({...safeUser(u),version:u.version}));
    }
    if(path==='/me/password/change'&&method==='POST'){await this.reauth(a,b);await db.query('UPDATE credentials SET password_hash=$1 WHERE user_id=$2',[await hash(password(b,'new_password',settings.password_min)),a.id]);await db.query('UPDATE tokens SET revoked=true WHERE user_id=$1 AND family<>$2',[a.id,a.family]);return {changed:true};}
    if(path==='/me/phone-change-requests'&&method==='POST') {
      await this.reauth(a,b);const value=text(b,'new_phone',8,16),number=parsePhoneNumberFromString(value);if(!number?.isValid()||number.country!==a.country||number.number!==value)fail(400,'VALIDATION_ERROR','Номер не соответствует выбранному региону');
      const exists=(await db.query('SELECT 1 FROM credentials WHERE country=$1 AND phone=$2',[a.country,value])).rows.length;if(exists)fail(409,'PHONE_CHANGE_UNAVAILABLE','Не удалось изменить идентификатор. Обратитесь в поддержку.');
      await db.query('UPDATE credentials SET phone=$1 WHERE user_id=$2',[value,a.id]);await db.query('UPDATE tokens SET revoked=true WHERE user_id=$1 AND family<>$2',[a.id,a.family]);
      await this.store.put({...a.user,phone:value,phone_status:'unverified',version:a.user.version+1});await this.store.put(this.record('security_event',a,{event:'phone.changed',ip,occurred_at:new Date().toISOString()}));return {phone:value,phone_status:'unverified'};
    }
    if(path==='/me/sessions'&&method==='GET')return {items:(await db.query('SELECT DISTINCT family,expires_at FROM tokens WHERE user_id=$1 AND kind=\'refresh\' AND NOT revoked AND NOT used',[a.id])).rows};
    const revokeSession=path.match(/^\/me\/sessions\/([^/]+)$/);
    if(revokeSession&&method==='DELETE'){await db.query('UPDATE tokens SET revoked=true WHERE user_id=$1 AND family=$2',[a.id,revokeSession[1]]);return {revoked:true};}
    if(path==='/me/blocks'&&method==='POST') {
      const target=await this.object(String(b.target_user_id),a,'user');if(target.id===a.id)fail(400,'VALIDATION_ERROR','Нельзя заблокировать себя');
      const old=(await this.store.all('pair_block',a.country)).find(x=>x.owner===a.id&&x.target_id===target.id&&x.status==='active');
      return old??this.store.put(this.record('pair_block',a,{target_id:target.id,status:'active'}));
    }
    if(path==='/me/blocks'&&method==='GET') {
      const visible=[];for(const block of (await this.store.all('pair_block',a.country)).filter(x=>x.owner===a.id&&x.status==='active')) {
        const user=await this.store.get(block.target_id);visible.push({...block,display_name:user?.display_name??''});
      }
      return this.list(visible,q);
    }
    const unblock=path.match(/^\/me\/blocks\/([^/]+)$/);
    if(unblock&&method==='DELETE'){const old=(await this.store.all('pair_block',a.country)).find(x=>x.owner===a.id&&x.target_id===unblock[1]&&x.status==='active');if(old)await this.store.put({...old,status:'released',version:old.version+1});return {released:true};}
    if(path==='/catalog/categories'&&method==='GET')return {items:(await this.store.all('category',a.country)).filter(x=>x.status==='effective').map(x=>({id:x.id,name:x.payload.labels?.[q.locale??a.user.locale??'ru']??x.title,labels:x.payload.labels,schema:x.payload.schema??{properties:{},required:[]},version:x.version}))};
    if(path==='/geo/cities'&&method==='GET')return {items:countries[a.country].cities.filter(c=>!q.q||c.toLowerCase().includes(String(q.q).toLowerCase())).map(name=>({id:referenceId(`joba:city:${a.country}:${name}`),name,country:a.country}))};
    if(path==='/me/monetization-config'&&method==='GET') {
      const config=(await this.store.all('monetization_config',a.country)).find(x=>x.status==='effective');
      return {subscription_enabled:true,banner_ads_enabled:false,rewarded_access_enabled:false,...config?.payload,version:config?.version??1,effective_at:config?.published_at??null,expires_at:new Date(Date.now()+settings.config_ttl_seconds*1000).toISOString(),server_time:new Date().toISOString(),checkout_enabled:false,country_gate:'unverified',offers:(await this.commerce.offers(a.country)).items};
    }
    if(path==='/me/entitlements'&&method==='GET')return {items:(await this.store.all('grant',a.country)).filter(x=>x.owner===a.id)};
    if(path==='/me/verification'&&method==='GET')return {status:a.user.verification,items:(await this.store.all('verification',a.country)).filter(x=>x.owner===a.id).map(({document_refs,...r})=>r)};
    if(path==='/me/verification-sessions'&&method==='POST') {
      const policy=(await this.store.all('verification_policy',a.country)).find(x=>x.status==='effective');
      if(!policy)fail(503,'COUNTRY_FLOW_UNAPPROVED','Типы документов и основание проверки для страны не утверждены');
      const consent=(await this.store.all('consent',a.country)).filter(x=>x.owner===a.id&&x.document_id===policy!.payload.document_id).sort((x,y)=>(y.sequence??0)-(x.sequence??0)||y.created_at.localeCompare(x.created_at))[0];
      if(!consent?.accepted)fail(403,'CONSENT_REQUIRED','Требуется согласие на проверку документа');
      if(!policy!.payload.document_types.includes(b.document_type))fail(400,'VALIDATION_ERROR','Тип документа не разрешён');
      return this.store.put(this.record('verification',a,{status:'draft',document_type:b.document_type,policy_id:policy!.id,policy_version:policy!.version,document_revision:1,document_refs:[]}));
    }
    const verificationSubmit=path.match(/^\/me\/verification-sessions\/([^/]+)\/submit$/);
    if(verificationSubmit&&method==='POST') {
      const r=await this.object(verificationSubmit[1],a,'verification',true);this.version(r,b);
      if(!['draft','rejected'].includes(r.status))fail(409,'STATE_CONFLICT','Заявка уже отправлена');
      const uploads=await this.safeUploads(a,b.upload_ids,'identity');if(!uploads.length)fail(400,'VALIDATION_ERROR','Загрузите документ');
      for(const id of uploads){const upload=await this.store.get(id);if(upload?.verification_id!==r.id)fail(422,'POLICY_REJECTED','Документ загружен для другой заявки');}
      await this.store.put({...a.user,verification:'pending_review',version:a.user.version+1});
      return this.store.put({...r,status:'pending_review',document_refs:uploads,document_revision:r.document_revision+1,version:r.version+1});
    }
    if(path==='/me/consents'&&method==='POST') {
      const d=await this.object(String(b.document_id),a,'legal_document');
      if(d.status!=='published'||b.document_hash!==d.hash)fail(409,'LEGAL_VERSION_CHANGED','Версия документа изменилась');
      if(typeof b.accepted!=='boolean')fail(400,'VALIDATION_ERROR','Требуется явное согласие');
      const count=(await db.query<any>("SELECT COALESCE(MAX((data->>'sequence')::integer),0) AS max FROM records WHERE kind='consent' AND owner=$1 AND country=$2",[a.id,a.country])).rows[0].max;
      return this.store.put(this.record('consent',a,{document_id:d.id,document_version:d.version,document_hash:d.hash,accepted:b.accepted,sequence:Number(count)+1}));
    }
    if(path==='/me/consents'&&method==='GET')return {items:(await this.store.all('consent',a.country)).filter(x=>x.owner===a.id).sort((x,y)=>(y.sequence??0)-(x.sequence??0))};
    if(path==='/me/contractor-profile'&&method==='GET'){const profile=(await this.store.all('contractor',a.country)).find(x=>x.owner===a.id);return {profile:profile?editableContent(profile):null};}
    if(path==='/me/contractor-profile'&&method==='PUT') {
      const old=(await this.store.all('contractor',a.country)).find(x=>x.owner===a.id);if(old)this.version(old,b);
      const title=text(b,'title',5,100),description=text(b,'description',20,3000),city=text(b,'city',2,100);
      const categories=(await this.store.all('category',a.country)).filter(c=>c.status==='effective');
      const category=categories.find(c=>c.id===b.category_id||c.legacy_id===b.category_id);if(!category)fail(400,'VALIDATION_ERROR','Категория недоступна');
      let fields:any;try{fields=profileFields({...b,category_id:category!.id},old?editableContent(old):old,countries[a.country].currency,new Set(categories.map(c=>c.id)));}catch(e:any){fail(400,'VALIDATION_ERROR','Проверьте поле '+e.message,{field:e.message});}
      const uploads=b.gallery_ids===undefined?(old?editableContent(old).gallery_ids??[]:[]):await this.safeUploads(a,b.gallery_ids,'portfolio',20);
      if(uploads.length>20)fail(400,'VALIDATION_ERROR','Не более 20 фотографий');
      if(!a.user.roles.includes('executor'))await this.store.put({...a.user,roles:[...a.user.roles,'executor'],version:a.user.version+1});
      const changes={...fields,title,description,city,gallery_ids:uploads};const staged=old?editContent(old,changes):{...this.record('contractor',a),...changes,status:'draft'};
      if(old&&['published','paused'].includes(old.status)&&b.availability==='paused'){staged.status='paused';staged.availability='paused';}
      return this.store.put(staged).then(editableContent);
    }
    if(path==='/me/contractor-profile/availability'&&method==='PATCH') {
      if(!['available','busy','paused'].includes(b.availability))fail(400,'VALIDATION_ERROR','Проверьте доступность');
      const profile=(await this.store.all('contractor',a.country)).find(r=>r.owner===a.id)??fail(404,'NOT_FOUND','Профиль не найден');this.version(profile,b);
      if(!['published','paused'].includes(profile.status))fail(409,'STATE_CONFLICT','Сначала опубликуйте профиль');
      if(b.availability!=='paused')await this.entitlement(a,'publish_profile',true);
      return this.store.put({...profile,availability:b.availability,status:b.availability==='paused'?'paused':'published',...(profile.draft?{draft:{...profile.draft,availability:b.availability}}:{}),version:profile.version+1}).then(editableContent);
    }
    if(path==='/me/contractor-profile/publish'&&method==='POST') {
      await this.entitlement(a,'publish_profile',true);const p=(await this.store.all('contractor',a.country)).find(x=>x.owner===a.id);if(!p)fail(404,'NOT_FOUND','Профиль не найден');this.version(p!,b);
      if(!['draft','rejected'].includes(editableContent(p!).status))fail(409,'STATE_CONFLICT','Нет черновика для публикации');return this.store.put(submitContent(p!)).then(editableContent);
    }
    if(path==='/me/content-revisions'&&method==='GET'){if(q.source_id){const source=await this.object(String(q.source_id),a,undefined,true);if(!['contractor','portfolio'].includes(source.kind))fail(404,'NOT_FOUND','Материал не найден');}return this.page('content_revision',a,q,{owner:a.id});}
    if(path==='/me/portfolio-projects'&&method==='GET')return {items:(await this.store.all('portfolio',a.country)).filter(x=>x.owner===a.id&&x.status!=='archived').sort((x,y)=>(x.position??0)-(y.position??0)||x.id.localeCompare(y.id)).map(editableContent)};
    if(path==='/me/portfolio-projects/reorder'&&method==='POST') {
      const current=(await this.store.all('portfolio',a.country)).filter(x=>x.owner===a.id&&x.status!=='archived');
      if(!Array.isArray(b.project_ids)||b.project_ids.length!==current.length||new Set(b.project_ids).size!==current.length||b.project_ids.some((id:string)=>!current.some(p=>p.id===id)))fail(400,'VALIDATION_ERROR','Проверьте список проектов');
      for(const p of current)this.version(p,{expected_version:b.expected_versions?.[p.id]});
      const reordered=[];for(let i=0;i<b.project_ids.length;i++){const p=current.find(x=>x.id===b.project_ids[i])!;reordered.push(await this.store.put({...p,position:i,version:p.version+1}));}
      return {items:reordered};
    }
    if(path==='/me/portfolio-projects'&&method==='POST') {
      const projects=(await this.store.all('portfolio',a.country)).filter(x=>x.owner===a.id&&x.status!=='archived');if(projects.length>=settings.portfolio_projects)fail(422,'LIMIT_EXCEEDED','Максимум 20 проектов');
      if(b.rights_confirmed!==undefined&&typeof b.rights_confirmed!=='boolean')fail(400,'VALIDATION_ERROR','Проверьте подтверждение прав');
      const category=(await this.store.all('category',a.country)).find(c=>(c.id===b.category_id||c.legacy_id===b.category_id)&&c.status==='effective');if(!category)fail(400,'VALIDATION_ERROR','Категория недоступна');
      let orderId:string|null=null;if(b.order_id){const order=await this.object(String(b.order_id),a,'order');if(order.status!=='completed'||order.executor_id!==a.id)fail(422,'POLICY_REJECTED','Можно связать только заказ, выполненный вами');orderId=order.id;}
      return this.store.put(this.record('portfolio',a,{title:text(b,'title',5,120),description:text(b,'description',0,3000),category_id:category!.id,order_id:orderId,rights_confirmed:b.rights_confirmed===true,status:'draft',position:projects.length,photos:[]}));
    }
    const portfolio=path.match(/^\/me\/portfolio-projects\/([^/]+)(?:\/(submit))?$/);
    if(portfolio) {
      const stored=await this.object(portfolio[1],a,'portfolio',true),p=editableContent(stored);if(method==='GET')return p;this.version(stored,b);
      if(method==='DELETE')return this.store.put({...stored,draft:undefined,status:'archived',version:stored.version+1});
      if(method==='PATCH') {
        const photos=b.upload_ids?await this.safeUploads(a,b.upload_ids,'portfolio'):p.photos;
        if(photos.length>settings.portfolio_photos)fail(422,'LIMIT_EXCEEDED','Превышен лимит фотографий');
        if(b.cover_id&&!photos.includes(b.cover_id))fail(400,'VALIDATION_ERROR','Обложка должна быть фотографией проекта');
        const category=(await this.store.all('category',a.country)).find(c=>(c.id===(b.category_id??p.category_id)||c.legacy_id===(b.category_id??p.category_id))&&c.status==='effective');if(!category)fail(400,'VALIDATION_ERROR','Категория недоступна');
        const cover=b.cover_id??(photos.includes(p.cover_id)?p.cover_id:photos[0]),extra:any={};
        if(b.rights_confirmed!==undefined){if(typeof b.rights_confirmed!=='boolean')fail(400,'VALIDATION_ERROR','Подтвердите права на материалы');extra.rights_confirmed=b.rights_confirmed;}
        if(b.order_id!==undefined){if(b.order_id===null)extra.order_id=null;else{const order=await this.object(String(b.order_id),a,'order');if(order.status!=='completed'||order.executor_id!==a.id)fail(422,'POLICY_REJECTED','Можно связать только заказ, выполненный вами');extra.order_id=order.id;}}
        return this.store.put(editContent(stored,{...extra,title:b.title===undefined?p.title:text(b,'title',5,120),description:b.description===undefined?p.description:text(b,'description',0,3000),category_id:category!.id,photos,cover_id:cover})).then(editableContent);
      }
      if(portfolio[2]==='submit'){await this.entitlement(a,'publish_profile',true);if(!p.photos.length||p.rights_confirmed!==true)fail(422,'POLICY_REJECTED','Нужна проверенная фотография и подтверждение прав на материалы');if(!['draft','rejected'].includes(p.status))fail(409,'STATE_CONFLICT','Нет черновика для проверки');return this.store.put(submitContent(stored)).then(editableContent);}
    }
    if(path==='/contractors'&&method==='GET'){await this.entitlement(a,'search_full');return this.page('contractor',a,q,{statuses:['published'],publicActor:a.id});}
    const contractor=path.match(/^\/contractors\/([^/]+)(?:\/(portfolio))?$/);
    if(contractor&&method==='GET'){
      await this.entitlement(a,'search_full');const p=await this.object(contractor[1],a,'contractor'),owner=await this.store.get(p.owner);
      if(owner?.status!=='active'||owner.verification!=='passed'||p.status!=='published'||['quarantined','hidden','rejected'].includes(p.moderation_status)||await this.blocked(a,p.owner))fail(404,'NOT_FOUND','Профиль не найден');
      if(!contractor[2])return publicContent(p);
      const projects=(await this.store.all('portfolio',a.country)).filter(x=>x.owner===p.owner&&x.status==='published'&&!['quarantined','hidden','rejected'].includes(x.moderation_status));
      const visible=await Promise.all(projects.map(async project=>{
        const order=project.order_id?await this.store.get(project.order_id):undefined;
        const linked=order?.kind==='order'&&order.country===a.country&&order.status==='completed'&&order.executor_id===project.owner;
        return {...publicContent(project),order_id:undefined,linked_completed_order:linked,source:linked?'joba_completed':'self_reported'};
      }));return this.portfolioPage(visible,q);
    }
    const publicCustomer=path.match(/^\/customers\/([^/]+)$/);
    if(publicCustomer&&method==='GET') {
      await this.entitlement(a,'search_full');const u=await this.object(publicCustomer[1],a,'user');if(u.status!=='active'||u.staff_permissions?.length||await this.blocked(a,u.id))fail(404,'NOT_FOUND','Профиль недоступен');
      const reviews=(await this.store.all('review',a.country)).filter(r=>r.target_id===u.id&&r.status==='published'&&r.moderation_status!=='quarantined');
      return {...safeUser(u),city_source:'self_reported',completed_orders:(await this.store.all('order',a.country)).filter(o=>o.owner===u.id&&o.status==='completed').length,rating:{count:reviews.length,average:reviews.length?reviews.reduce((sum,r)=>sum+r.rating,0)/reviews.length:null}};
    }
    const publicReviews=path.match(/^\/users\/([^/]+)\/reviews$/);
    if(publicReviews&&method==='GET'){await this.entitlement(a,'search_full');const target=await this.object(publicReviews[1],a,'user');if(target.status!=='active'||target.staff_permissions?.length||await this.blocked(a,target.id))fail(404,'NOT_FOUND','Профиль недоступен');return this.list((await this.store.all('review',a.country)).filter(r=>r.target_id===publicReviews[1]&&r.status==='published'&&r.moderation_status!=='quarantined'),q);}
    if(path==='/orders'&&method==='POST') {
      const budget=b.budget?b.budget.mode==='negotiable'?null:b.budget.amount_minor:(b.budget_amount??null);
      if(budget!==null && (!Number.isSafeInteger(budget)||budget<0))fail(400,'VALIDATION_ERROR','Бюджет должен быть целым числом в минимальных единицах валюты либо null');
      if(b.country&&b.country!==a.country||b.budget?.currency&&b.budget.currency!==countries[a.country].currency)fail(400,'VALIDATION_ERROR','Страна и валюта не совпадают с регионом');
      if(!['onsite','remote','hybrid'].includes(b.work_mode??'onsite'))fail(400,'VALIDATION_ERROR','Проверьте формат работы');
      const category=(await this.store.all('category',a.country)).find(c=>(c.id===b.category_id||c.legacy_id===b.category_id)&&c.status==='effective');if(!category)fail(400,'VALIDATION_ERROR','Категория недоступна');
      const city=b.city??countries[a.country].cities.find(name=>referenceId(`joba:city:${a.country}:${name}`)===b.city_id);if(typeof city!=='string'||city.length<2||city.length>100)fail(400,'VALIDATION_ERROR','Город недоступен');
      const uploads=b.upload_ids?await this.safeUploads(a,b.upload_ids,'order'):[];
      return this.store.put(this.record('order',a,{title:text(b,'title',5,120),description:text(b,'description',20,5000),category_id:category!.id,city,budget_amount:budget,currency:countries[a.country].currency,status:'draft',revision:1,upload_ids:uploads,work_mode:b.work_mode??'onsite',attributes:attributes(category!.payload.schema,b.attributes),time_window:timeWindow(b.time_window)}));
    }
    if(path==='/me/orders'&&method==='GET')return this.page('order',a,q,{owner:a.id});
    if(path==='/me/completed-orders'&&method==='GET'){if(q.role&&!['customer','executor'].includes(q.role))fail(400,'VALIDATION_ERROR','Проверьте роль');return this.page('order',a,q,{...(q.role==='executor'?{executor:a.id}:q.role==='customer'?{owner:a.id}:{participant:a.id}),statuses:['completed']});}
    if(path==='/me/assigned-orders'&&method==='GET')return this.list((await this.store.all('order',a.country)).filter(x=>x.executor_id===a.id),q);
    if(path==='/me/offers'&&method==='GET')return this.list((await this.store.all('offer',a.country)).filter(x=>x.owner===a.id),q);
    if(path==='/me/order-change-requests'&&method==='GET')return this.list([...(await this.store.all('cancel_request',a.country)),...(await this.store.all('amendment',a.country))].filter(x=>x.owner===a.id||x.recipient_id===a.id),q);
    if(path==='/orders'&&method==='GET'){await this.entitlement(a,'search_full',true);return this.page('order',a,q,{statuses:['open'],publicActor:a.id});}
    const om=path.match(/^\/orders\/([^/]+)(?:\/(publish|cancel|complete|offers|select|start|extend|clone|invites|cancel-requests|amendments|request-revision|confirm-completion))?$/);
    if(om) {
      const o=await this.object(om[1],a,'order');const action=om[2];
      const participant=o.owner===a.id||o.executor_id===a.id;
      if(!participant&&(o.status!=='open'||['quarantined','hidden','rejected'].includes(o.moderation_status)||o.expires_at<=new Date().toISOString()||await this.blocked(a,o.owner)))fail(404,'NOT_FOUND','Заказ не найден');
      if(!participant)await this.entitlement(a,'search_full',true);
      if(method==='GET'&&!action)return participant?o:{...o,exact_address:undefined};
      if(method==='GET'&&action==='offers'){if(o.owner!==a.id)fail(404,'NOT_FOUND','Заказ не найден');return {items:(await this.store.all('offer',a.country)).filter(x=>x.order_id===o.id)};}
      if(action==='offers'&&method==='POST') {
        await this.entitlement(a,'send_offer',true);if(o.owner===a.id||o.status!=='open')fail(409,'STATE_CONFLICT','Нельзя откликнуться на заказ');
        if(await this.blocked(a,o.owner))fail(404,'NOT_FOUND','Заказ недоступен');
        if(b.acknowledged_revision!==o.revision)fail(409,'REVISION_NOT_ACKNOWLEDGED','Условия заказа изменились');
        if(!Number.isSafeInteger(b.amount)||b.amount<0)fail(400,'VALIDATION_ERROR','Проверьте цену');
        if((await this.store.all('offer',a.country)).some(x=>x.order_id===o.id&&x.owner===a.id&&x.status==='active'))fail(409,'STATE_CONFLICT','Отклик уже отправлен');
        const offer=this.record('offer',a,{order_id:o.id,text:text(b,'text',1,3000),amount:b.amount,currency:o.currency,acknowledged_revision:o.revision,status:'active'});
        const chat=this.record('conversation',a,{order_id:o.id,offer_id:offer.id,members:[o.owner,a.id],status:'open'});offer.conversation_id=chat.id;
        await this.store.put(chat);await this.store.put(offer);await this.notify(o.owner,a,'offer.created',o.id);return offer;
      }
      if(action==='invites'&&method==='POST') {
        if(o.owner!==a.id)fail(404,'NOT_FOUND','Заказ не найден');await this.entitlement(a,'publish_order');
        if(o.status!=='open')fail(409,'STATE_CONFLICT','Заказ закрыт');
        const p=await this.object(String(b.contractor_id),a,'contractor'),owner=await this.store.get(p.owner);if(owner?.status!=='active'||owner.verification!=='passed'||await this.blocked(a,p.owner)||p.owner===a.id||p.status!=='published'||p.availability==='paused')fail(422,'POLICY_REJECTED','Исполнитель недоступен');
        const i=this.record('invite',a,{order_id:o.id,recipient_id:p.owner,status:'pending',order_revision:o.revision});await this.store.put(i);await this.notify(p.owner,a,'invite.created',i.id);return i;
      }
      if(['cancel-requests','amendments'].includes(action??'')&&method==='POST') {
        if(!participant)fail(404,'NOT_FOUND','Заказ не найден');this.version(o,b);
        if(!['assigned','in_progress','completion_requested'].includes(o.status))fail(409,'STATE_CONFLICT','Изменение недоступно');
        const kind=action==='amendments'?'amendment':'cancel_request';
        if((await this.store.all(kind,a.country)).some(x=>x.order_id===o.id&&x.status==='pending'))fail(409,'STATE_CONFLICT','Уже есть ожидающий запрос');
        const data:any={order_id:o.id,recipient_id:o.owner===a.id?o.executor_id:o.owner,status:'pending',order_version:o.version,reason:text(b,'reason',5,1000),expires_at:new Date(Date.now()+settings.offer_expiry_hours*3600000).toISOString()};
        if(kind==='amendment'){if(!Number.isSafeInteger(b.amount)||b.amount<0)fail(400,'VALIDATION_ERROR','Проверьте сумму');data.amount=b.amount;data.description=text(b,'description',20,5000);}
        const r=this.record(kind,a,data);await this.store.put(r);await this.notify(data.recipient_id,a,kind+'.created',r.id);return r;
      }
      if(o.owner!==a.id && !['complete','start'].includes(action??''))fail(404,'NOT_FOUND','Заказ не найден');this.version(o,b);
      if(action==='publish'&&method==='POST'){await this.entitlement(a,'publish_order');if(o.status!=='draft')fail(409,'STATE_CONFLICT','Заказ уже опубликован');return this.store.put({...o,status:'open',revision:o.revision+1,version:o.version+1,published_at:new Date().toISOString(),expires_at:new Date(Date.now()+settings.order_expiry_days*86400000).toISOString()});}
      if(action==='extend'&&method==='POST'){await this.entitlement(a,'publish_order');const expires=Date.parse(String(b.expires_at));if(o.status!=='open'||Date.parse(o.expires_at)<=Date.now()||!Number.isFinite(expires)||expires<=Date.now()||expires>Date.now()+settings.order_expiry_max_days*86400000)fail(409,'STATE_CONFLICT','Недопустимый срок продления');return this.store.put({...o,expires_at:new Date(expires).toISOString(),version:o.version+1});}
      if(action==='clone'&&method==='POST'){await this.entitlement(a,'publish_order');return this.store.put(this.record('order',a,{title:o.title,description:o.description,category_id:o.category_id,city:o.city,budget_amount:o.budget_amount,currency:o.currency,status:'draft',revision:1,upload_ids:[]}));}
      if(method==='PATCH'&&!action) {
        if(!['draft','open'].includes(o.status))fail(409,'STATE_CONFLICT','Редактирование недоступно');
        const category=(await this.store.all('category',a.country)).find(c=>c.id===(b.category_id??o.category_id)&&c.status==='effective');if(!category)fail(400,'VALIDATION_ERROR','Категория недоступна');
        const changes:any={title:b.title===undefined?o.title:text(b,'title',5,120),description:b.description===undefined?o.description:text(b,'description',20,5000),category_id:category!.id,attributes:attributes(category!.payload.schema,b.attributes??o.attributes)};
        if(b.budget_amount!==undefined){if(b.budget_amount!==null&&(!Number.isSafeInteger(b.budget_amount)||b.budget_amount<0))fail(400,'VALIDATION_ERROR','Проверьте бюджет');changes.budget_amount=b.budget_amount;}
        if(b.city!==undefined)changes.city=text(b,'city',2,100);
        if(b.city_id!==undefined){const city=countries[a.country].cities.find(name=>referenceId(`joba:city:${a.country}:${name}`)===b.city_id);if(!city)fail(400,'VALIDATION_ERROR','Город недоступен');changes.city=city;}
        if(b.work_mode!==undefined){if(!['onsite','remote','hybrid'].includes(b.work_mode))fail(400,'VALIDATION_ERROR','Проверьте формат работы');changes.work_mode=b.work_mode;}
        if(b.upload_ids!==undefined)changes.upload_ids=await this.safeUploads(a,b.upload_ids,'order');
        if(b.time_window!==undefined)changes.time_window=timeWindow(b.time_window);
        return this.store.put({...o,...changes,revision:o.revision+1,version:o.version+1});
      }
      if(action==='select'&&method==='POST') {
        await this.entitlement(a,'select_offer');if(o.status!=='open')fail(409,'STATE_CONFLICT','Заказ уже назначен');
        const offer=await this.object(String(b.offer_id),a,'offer');if(offer.order_id!==o.id||offer.status!=='active'||offer.acknowledged_revision!==o.revision||b.offer_version!==offer.version)fail(409,'OFFER_CHANGED','Отклик или условия изменились');
        const executor=await this.store.get(offer.owner);if(!executor||executor.verification!=='passed'||executor.status!=='active')fail(409,'STATE_CONFLICT','Исполнитель больше недоступен');
        for(const x of (await this.store.all('offer',a.country)).filter(x=>x.order_id===o.id)) {
          await this.store.put({...x,status:x.id===offer.id?'selected':'not_selected',version:x.version+1});
          const c=await this.store.get(x.conversation_id);if(c)await this.store.put({...c,status:x.id===offer.id?'working':'closed',version:c.version+1});
        }
        const assignment=this.record('assignment',a,{order_id:o.id,customer_id:a.id,executor_id:offer.owner,conversation_id:offer.conversation_id,order_snapshot:o,offer_snapshot:offer,status:'active'});await this.store.put(assignment);
        const updated={...o,status:'assigned',assignment_id:assignment.id,executor_id:offer.owner,selected_offer_id:offer.id,agreed_amount:offer.amount,version:o.version+1};await this.store.put(updated);await this.notify(offer.owner,a,'order.selected',o.id);return updated;
      }
      if(action==='start'&&method==='POST'){if(o.executor_id!==a.id||o.status!=='assigned')fail(409,'STATE_CONFLICT','Начало работы недоступно');return this.store.put({...o,status:'in_progress',started_at:new Date().toISOString(),version:o.version+1});}
      if(action==='complete'&&method==='POST'){if(o.executor_id!==a.id||o.status!=='in_progress')fail(409,'STATE_CONFLICT','Завершение недоступно');return this.store.put({...o,status:'completion_requested',version:o.version+1});}
      if(action==='confirm-completion'&&method==='POST'){if(o.status!=='completion_requested')fail(409,'STATE_CONFLICT','Исполнитель не запросил завершение');const result=await this.store.put({...o,status:'completed',completed_at:new Date().toISOString(),version:o.version+1});await this.growth.qualify(o.owner,a.country,'completed_order',o.id);await this.growth.qualify(o.executor_id,a.country,'completed_order',o.id);return result;}
      if(action==='request-revision'&&method==='POST'){if(o.status!=='completion_requested')fail(409,'STATE_CONFLICT','Доработка недоступна');return this.store.put({...o,status:'in_progress',revision_reason:text(b,'reason',5,1000),version:o.version+1});}
      if(action==='cancel'&&method==='POST'){if(!['draft','open'].includes(o.status))fail(409,'STATE_CONFLICT','Активный заказ требует разрешения через поддержку');return this.store.put({...o,status:'cancelled',reason:text(b,'reason',5,1000),version:o.version+1});}
    }
    const responseCommand=path.match(/^\/(cancel-requests|amendments)\/([^/]+)\/respond$/);
    if(responseCommand&&method==='POST') {
      const kind=responseCommand[1]==='amendments'?'amendment':'cancel_request',r=await this.object(responseCommand[2],a,kind);
      if(r.recipient_id!==a.id)fail(404,'NOT_FOUND','Запрос не найден');this.version(r,b);
      if(r.status!=='pending'||r.expires_at<=new Date().toISOString())fail(409,'STATE_CONFLICT','Запрос больше не действует');
      if(!['accept','reject'].includes(b.decision))fail(400,'VALIDATION_ERROR','Выберите accept или reject');
      const o=await this.object(r.order_id,a,'order');if(o.version!==r.order_version)fail(409,'STATE_CONFLICT','Заказ изменился');
      if(b.decision==='accept')await this.store.put({...o,...(kind==='amendment'?{agreed_amount:r.amount,description:r.description,revision:o.revision+1}:{status:'cancelled'}),version:o.version+1});
      const result=await this.store.put({...r,status:b.decision==='accept'?'accepted':'rejected',version:r.version+1});await this.notify(r.owner,a,kind+'.'+result.status,r.id);return result;
    }
    const offerCommand=path.match(/^\/offers\/([^/]+)(?:\/(acknowledge|withdraw))?$/);
    if(offerCommand) {
      const f=await this.object(offerCommand[1],a,'offer',true);this.version(f,b);
      if(f.status!=='active')fail(409,'STATE_CONFLICT','Отклик больше не активен');
      const o=await this.object(f.order_id,a,'order');if(o.status!=='open')fail(409,'STATE_CONFLICT','Заказ закрыт');
      if(offerCommand[2]==='withdraw'&&method==='POST'){const c=await this.store.get(f.conversation_id);if(c)await this.store.put({...c,status:'closed',version:c.version+1});return this.store.put({...f,status:'withdrawn',version:f.version+1});}
      await this.entitlement(a,'send_offer',true);
      if(offerCommand[2]==='acknowledge'&&method==='POST'){if(b.order_revision!==o.revision)fail(409,'REVISION_NOT_ACKNOWLEDGED','Условия изменились');return this.store.put({...f,acknowledged_revision:o.revision,version:f.version+1});}
      if(method==='PATCH'){if(!Number.isSafeInteger(b.amount)||b.amount<0)fail(400,'VALIDATION_ERROR','Проверьте цену');return this.store.put({...f,text:text(b,'text',1,3000),amount:b.amount,version:f.version+1});}
    }
    if(path==='/me/order-invites'&&method==='GET')return this.list((await this.store.all('invite',a.country)).filter(x=>x.recipient_id===a.id),q);
    const inviteCommand=path.match(/^\/order-invites\/([^/]+)\/(respond|revoke)$/);
    if(inviteCommand&&method==='POST') {
      const r=await this.object(inviteCommand[1],a,'invite');if((inviteCommand[2]==='respond'?r.recipient_id:r.owner)!==a.id)fail(404,'NOT_FOUND','Приглашение не найдено');this.version(r,b);
      if(r.status!=='pending')fail(409,'STATE_CONFLICT','Приглашение обработано');
      if(inviteCommand[2]==='revoke')return this.store.put({...r,status:'revoked',version:r.version+1});
      if(!['accept','decline'].includes(b.decision))fail(400,'VALIDATION_ERROR','Выберите accept или decline');
      if(b.decision==='accept')await this.entitlement(a,'send_offer',true);return this.store.put({...r,status:b.decision==='accept'?'accepted':'declined',version:r.version+1});
    }
    if(path==='/me/conversations'&&method==='GET')return {items:(await this.store.all('conversation',a.country)).filter(x=>x.members.includes(a.id))};
    const readConversation=path.match(/^\/conversations\/([^/]+)\/(read|delivered)$/);
    if(readConversation&&method==='POST') {
      const c=await this.object(readConversation[1],a,'conversation');if(!c.members.includes(a.id))fail(404,'NOT_FOUND','Чат не найден');
      const all=(await this.store.all('message',a.country)).filter(x=>x.thread_id===c.id);
      const max=Math.max(0,...all.map(x=>x.sequence));if(!Number.isInteger(b.sequence)||b.sequence<0||b.sequence>max)fail(400,'VALIDATION_ERROR','Проверьте sequence');
      const field=readConversation[2]==='read'?'read_sequences':'delivered_sequences';
      if(b.sequence<=(c[field]?.[a.id]??0))return c;
      const result=await this.store.put({...c,[field]:{...c[field],[a.id]:b.sequence},version:c.version+1});
      for(const recipient of c.members)if(recipient!==a.id){
        const id=randomUUID();await db.query('INSERT INTO events(event_id,recipient_id,country,data) VALUES($1,$2,$3,$4)',[id,recipient,a.country,JSON.stringify({event_id:id,type:'conversation.'+readConversation[2],aggregate_id:c.id,occurred_at:new Date().toISOString()})]);this.events.emit(recipient);
      }
      return result;
    }
    const editMessage=path.match(/^\/messages\/([^/]+)$/);
    if(editMessage&&['PATCH','DELETE'].includes(method)) {
      const m=await this.object(editMessage[1],a,'message',true);this.version(m,b);
      if(Date.parse(m.created_at)+settings.message_edit_minutes*60000<Date.now())fail(409,'EDIT_WINDOW_CLOSED','Срок изменения сообщения истёк');
      await this.store.put(this.record('message_revision',a,{message_id:m.id,previous_version:m.version,text:m.text}));
      return this.store.put({...m,text:method==='DELETE'?'':text(b,'text',1,3000),tombstone:method==='DELETE',edited_at:new Date().toISOString(),version:m.version+1});
    }
    const cm=path.match(/^\/conversations\/([^/]+)\/messages$/);
    if(cm){const c=await this.object(cm[1],a,'conversation');if(!c.members.includes(a.id))fail(404,'NOT_FOUND','Чат не найден');return this.messages(c,a,method,b,q,'message');}
    if(path==='/me/support-threads'&&method==='GET')return this.list((await this.store.all('support',a.country)).filter(x=>x.owner===a.id),q);
    if(path==='/support/threads'&&method==='POST')return this.store.put(this.record('support',a,{subject:text(b,'subject',5,120),status:'new',members:[a.id]}));
    const sm=path.match(/^\/support\/threads\/([^/]+)\/messages$/);
    if(sm){const t=await this.object(sm[1],a,'support',true);return this.messages(t,a,method,b,q,'support_message');}
    if(path==='/reviews'&&method==='POST') {
      const o=await this.object(String(b.order_id),a,'order');if(o.status!=='completed'||![o.owner,o.executor_id].includes(a.id))fail(403,'FORBIDDEN','Отзыв доступен только участнику завершённого заказа');
      if(!Number.isInteger(b.rating)||b.rating<1||b.rating>5)fail(400,'VALIDATION_ERROR','Оценка от 1 до 5');
      if((await this.store.all('review',a.country)).some(x=>x.order_id===o.id&&x.owner===a.id))fail(409,'STATE_CONFLICT','Отзыв уже оставлен');
      const r=this.record('review',a,{order_id:o.id,target_id:o.owner===a.id?o.executor_id:o.owner,rating:b.rating,text:text(b,'text',0,2000),status:'sealed',publish_after:new Date(Date.parse(o.completed_at)+settings.review_blind_days*86400000).toISOString()});await this.store.put(r);
      const all=(await this.store.all('review',a.country)).filter(x=>x.order_id===o.id);if(all.length===2)for(const x of all)await this.store.put({...x,status:'published',version:x.version+1});return {...r,status:all.length===2?'published':'sealed'};
    }
    const editReview=path.match(/^\/reviews\/([^/]+)$/);
    if(editReview&&method==='PATCH') {
      const r=await this.object(editReview[1],a,'review',true);this.version(r,b);
      if(r.status==='published'&&(r.correction_count>=1||Date.parse(r.published_at??r.created_at)+settings.review_correction_hours*3600000<Date.now()))fail(409,'EDIT_WINDOW_CLOSED','Срок исправления отзыва истёк');
      if(r.status==='sealed'&&r.publish_after<=new Date().toISOString())fail(409,'EDIT_WINDOW_CLOSED','Срок исправления отзыва истёк');
      if(!Number.isInteger(b.rating)||b.rating<1||b.rating>5)fail(400,'VALIDATION_ERROR','Оценка от 1 до 5');
      await this.store.put(this.record('review_revision',a,{review_id:r.id,text:r.text,rating:r.rating,previous_version:r.version}));
      return this.store.put({...r,text:text(b,'text',0,2000),rating:b.rating,correction_count:(r.correction_count??0)+(r.status==='published'?1:0),version:r.version+1});
    }
    if(path==='/me/notifications'&&method==='GET')return this.list((await this.store.all('notification',a.country)).filter(x=>x.owner===a.id),q);
    if(path==='/events'&&method==='GET') {
      const after=Number(q.after_sequence??0);if(!Number.isSafeInteger(after)||after<0)fail(400,'VALIDATION_ERROR','Недопустимый event cursor');
      const events=await db.query<any>('SELECT sequence,data FROM events WHERE recipient_id=$1 AND country=$2 AND sequence>$3 ORDER BY sequence LIMIT 100',[a.id,a.country,after]);
      return {items:events.rows.map(r=>({...r.data,sequence:Number(r.sequence)}))};
    }
    const notification=path.match(/^\/me\/notifications\/([^/]+)\/read$/);
    if(notification&&method==='POST'){const n=await this.object(notification[1],a,'notification',true);return this.store.put({...n,read:true,version:n.version+1});}
    if(path==='/me/notifications/read-all'&&method==='POST'){for(const n of await this.store.all('notification',a.country))if(n.owner===a.id&&!n.read&&n.created_at<=String(b.before))await this.store.put({...n,read:true,version:n.version+1});return {read:true};}
    if(path==='/me/notification-preferences'&&method==='GET')return a.user.notification_preferences??{marketing:false,chat:true,service:true};
    if(path==='/me/notification-preferences'&&method==='PATCH') {
      this.version(a.user,b);const p=b.preferences;if(!p||['marketing','chat','service'].some(k=>typeof p[k]!=='boolean'))fail(400,'VALIDATION_ERROR','Проверьте категории уведомлений');
      if(p.quiet_hours){if(!/^([01]\d|2[0-3]):[0-5]\d$/.test(p.quiet_hours.start)||!/^([01]\d|2[0-3]):[0-5]\d$/.test(p.quiet_hours.end)||p.quiet_hours.start===p.quiet_hours.end)fail(400,'VALIDATION_ERROR','Проверьте часы тишины');try{new Intl.DateTimeFormat('ru',{timeZone:p.quiet_hours.time_zone}).format(new Date());}catch{fail(400,'VALIDATION_ERROR','Проверьте часовой пояс');}}
      await this.store.put({...a.user,notification_preferences:{marketing:p.marketing,chat:p.chat,service:p.service,quiet_hours:p.quiet_hours},version:a.user.version+1});return p;
    }
    if(path==='/me/push-tokens'&&method==='POST'){if(!['ios','android','web'].includes(b.platform))fail(400,'VALIDATION_ERROR','Проверьте платформу');return this.store.put(this.record('push_token',a,{token:text(b,'token',10,4096),platform:b.platform,session_family:a.family,environment:b.environment==='production'?'production':'sandbox',status:'active'})).then(({token,...r})=>r);}
    const pushToken=path.match(/^\/me\/push-tokens\/([^/]+)$/);if(pushToken&&method==='DELETE'){const r=await this.object(pushToken[1],a,'push_token',true);return this.store.put({...r,status:'revoked',token:'',version:r.version+1}).then(({token,...r})=>r);}
    const votes=path.match(/^\/listing-votes\/(orders|services)\/([^/]+)$/);
    if(votes&&['PUT','DELETE'].includes(method)) {
      await this.entitlement(a,'search_full');const target=await this.object(votes[2],a,votes[1]==='orders'?'order':'contractor');
      if(target.owner===a.id)fail(403,'FORBIDDEN','Нельзя голосовать за свою карточку');
      if(!['open','published'].includes(target.status))fail(409,'STATE_CONFLICT','Карточка недоступна');
      if(method==='DELETE'){await db.query('DELETE FROM votes WHERE voter=$1 AND target=$2',[a.id,target.id]);return {removed:true};}
      if(![-1,1].includes(b.value))fail(400,'VALIDATION_ERROR','Голос: 1 либо -1');
      await db.query('INSERT INTO votes(voter,target,value) VALUES($1,$2,$3) ON CONFLICT(voter,target) DO UPDATE SET value=excluded.value,created_at=now()',[a.id,target.id,b.value]);return {target_id:target.id,value:b.value};
    }
    if(path==='/top-listings'&&method==='GET') {
      const kind=q.target_type==='orders'?'order':'contractor';await this.entitlement(a,'search_full',kind==='order');
      const candidates=(await this.store.all(kind,a.country)).filter(x=>x.status===(kind==='order'?'open':'published'));
      const counts=(await db.query<any>('SELECT target,COUNT(*) FILTER(WHERE value=1) AS likes,COUNT(*) FILTER(WHERE value=-1) AS dislikes FROM votes WHERE created_at>now()-interval \'30 days\' GROUP BY target')).rows;
      const ranked=candidates.map(c=>{const v=counts.find(v=>v.target===c.id);const likes=Number(v?.likes??0),dislikes=Number(v?.dislikes??0);const age=(Date.now()-new Date(c.published_at??c.created_at).getTime())/86400000;return {...publicContent(c),likes,dislikes,organic_score:Math.max(0,Math.log1p(likes)-.5*Math.log1p(dislikes))*Math.exp(-age/30)};}).sort((a,b)=>b.organic_score-a.organic_score||b.likes-a.likes||b.created_at.localeCompare(a.created_at)||a.id.localeCompare(b.id));
      return {items:ranked.slice(0,100),promotions:[],meta:{algorithm_version:1,calculated_at:new Date().toISOString()}};
    }
    const reviews=path.match(/^\/(customers|contractors)\/([^/]+)\/reviews$/);
    if(reviews&&method==='GET'){await this.entitlement(a,'search_full');return this.list((await this.store.all('review',a.country)).filter(x=>x.target_id===reviews[2]&&x.status==='published'),q);}
    if(path==='/me/privacy-requests'&&method==='POST'){await this.reauth(a,b);if(!['export','delete'].includes(b.type))fail(400,'VALIDATION_ERROR','Выберите тип запроса');return this.store.put(this.record('privacy',a,{type:b.type,status:'requested'}));}
    if(path==='/me/privacy-requests'&&method==='GET')return {items:(await this.store.all('privacy',a.country)).filter(x=>x.owner===a.id)};
    const privacy=path.match(/^\/me\/privacy-requests\/([^/]+)$/);if(privacy&&method==='GET')return this.object(privacy[1],a,'privacy',true);
    const privacyCancel=path.match(/^\/me\/privacy-requests\/([^/]+)\/cancel$/);
    if(privacyCancel&&method==='POST') {
      const r=await this.object(privacyCancel[1],a,'privacy',true);this.version(r,b);
      if(!['requested','awaiting_retention_policy'].includes(r.status))fail(409,'STATE_CONFLICT','Обработка уже началась');
      return this.store.put({...r,status:'cancelled',version:r.version+1});
    }
    if(path==='/cases'&&method==='POST')return this.store.put(this.record('case',a,{target_type:text(b,'target_type',1,30),target_id:text(b,'target_id',1,100),reason_code:text(b,'reason_code',1,50),description:text(b,'description',10,3000),status:'new'}));
    if(path==='/me/cases'&&method==='GET')return this.list((await this.store.all('case',a.country)).filter(x=>x.owner===a.id||x.subject_user_id===a.id).map(({internal_notes,...r})=>r),q);
    const caseRead=path.match(/^\/cases\/([^/]+)$/);
    if(caseRead&&method==='GET') {
      const c=await this.object(caseRead[1],a,'case');if(c.owner!==a.id&&c.subject_user_id!==a.id)fail(404,'NOT_FOUND','Дело не найдено');
      const {internal_notes,...visible}=c;return visible;
    }
    const caseUpdate=path.match(/^\/cases\/([^/]+)\/(messages|appeals)$/);
    if(caseUpdate&&method==='GET'&&caseUpdate[2]==='messages') {
      const c=await this.object(caseUpdate[1],a,'case');if(c.owner!==a.id&&c.subject_user_id!==a.id)fail(404,'NOT_FOUND','Дело не найдено');
      return this.list((await this.store.all('case_message',a.country)).filter(x=>x.case_id===c.id&&!x.internal),q);
    }
    if(caseUpdate&&method==='POST') {
      const c=await this.object(caseUpdate[1],a,'case');if(c.owner!==a.id&&c.subject_user_id!==a.id)fail(404,'NOT_FOUND','Дело не найдено');
      if(caseUpdate[2]==='appeals') {
        if(c.subject_user_id!==a.id||!['resolved','restricted'].includes(c.status))fail(409,'STATE_CONFLICT','Апелляция недоступна');
        this.version(c,b);const result=await this.store.put({...c,status:'appealed',appeal_reason:text(b,'reason',10,3000),version:c.version+1});return result;
      }
      return this.store.put(this.record('case_message',a,{case_id:c.id,text:text(b,'text',1,3000),upload_ids:b.upload_ids?await this.safeUploads(a,b.upload_ids,'chat'):[]}));
    }
    if(path==='/billing/offers'&&method==='GET')return this.commerce.offers(a.country);
    if(['/billing/verify-purchase','/billing/restore'].includes(path)&&method==='POST')return this.commerce.verify(a.id,a.country,String(b.provider),text(b,'transaction_reference',1,10000));
    if(path==='/me/subscriptions'&&method==='GET')return {items:(await this.store.all('subscription',a.country)).filter(x=>x.owner===a.id)};
    if(path==='/billing/refund-requests'&&method==='POST')return this.store.put(this.record('refund_request',a,{subscription_id:text(b,'subscription_id',36,36),reason:text(b,'reason',5,1000),status:'requested'}));
    if(path==='/ads/reward-sessions'&&method==='POST')return this.commerce.rewardSession(a.id,a.country,b);
    const reward=path.match(/^\/ads\/reward-sessions\/([^/]+)$/);if(reward&&method==='GET')return this.object(reward[1],a,'ad_session',true);
    if(path==='/me/referrals'&&method==='GET')return this.growth.referrals(a.id,a.country);
    if(path==='/referrals/attribute'&&method==='POST')return this.growth.attribute(a.id,a.country,text(b,'code',1,50));
    const redeem=path.match(/^\/me\/referral-rewards\/([^/]+)\/redeem$/);if(redeem&&method==='POST')return this.growth.redeem(a.id,a.country,redeem[1]);
    if(path==='/boost-offers'&&method==='GET'){await this.entitlement(a,'search_full');return {items:(await this.store.all('price_version',a.country)).filter(x=>x.status==='effective'&&x.payload.product_type==='boost').map(x=>({id:x.id,...x.payload})),placements:(await this.store.all('placement_policy',a.country)).filter(x=>x.status==='effective')};}
    if(path==='/boost-reservations'&&method==='POST'){const target=await this.object(String(b.target_id),a,undefined,true);await this.entitlement(a,'search_full',target.kind==='contractor');return this.growth.reserveBoost(a.id,a.country,b);}
    if(path==='/boost-purchases/verify'&&method==='POST')return this.growth.verifyBoost(a.id,a.country,b);
    if(path==='/me/boosts'&&method==='GET')return this.list((await this.store.all('boost',a.country)).filter(x=>x.owner===a.id),q);
    if(path==='/uploads/initiate'&&method==='POST') {
      if(!['avatar','portfolio','order','chat','identity','brand'].includes(b.purpose))fail(400,'VALIDATION_ERROR','Недопустимая цель загрузки');
      if(b.purpose==='identity'){const verification=await this.object(String(b.verification_id),a,'verification',true);if(!['draft','rejected'].includes(verification.status))fail(409,'STATE_CONFLICT','Заявка не принимает файлы');}
      if(b.purpose==='brand')await this.staff(a,'brand_owner');
      const limit=(b.purpose==='chat'?settings.upload_chat_mb:settings.upload_image_mb)*1024*1024;
      if(!Number.isInteger(b.size)||b.size<1||b.size>limit)fail(413,'FILE_TOO_LARGE','Файл слишком большой');
      if(!['image/jpeg','image/png','application/pdf'].includes(b.mime)||b.mime==='application/pdf'&& !['chat','identity'].includes(b.purpose))fail(422,'POLICY_REJECTED','Формат не разрешён');
      const r=this.record('upload',a,{purpose:b.purpose,...(b.purpose==='identity'?{verification_id:b.verification_id}:{}),mime:b.mime,size:b.size,status:'initiated',expires_at:new Date(Date.now()+86400000).toISOString()});await this.store.put(r);
      return {...r,upload_url:'/api/v1/uploads/'+r.id+'/content',method:'PUT'};
    }
    const upload=path.match(/^\/uploads\/([^/]+)\/(content|finalize|download|download-url|metadata)$/);
    if(upload) {
      const u=await this.object(upload[1],a,'upload');
      if(q.variant!==undefined&&!['original','preview'].includes(q.variant))fail(400,'VALIDATION_ERROR','Проверьте вариант файла');
      if(!['download','download-url','metadata'].includes(upload[2])&&u.owner!==a.id)fail(404,'NOT_FOUND','Файл не найден');
      if(upload[2]==='metadata'&&method==='GET'){if(u.owner!==a.id)await this.authorizeFile(u,a,q);return {id:u.id,mime:u.mime,size:u.size,status:u.status,version:u.version,failure_code:u.failure_code};}
      if(upload[2]==='content'&&method==='PUT') {
        if(!Buffer.isBuffer(b)||b.length!==u.size)fail(400,'VALIDATION_ERROR','Размер файла не совпадает');
        if(u.status!=='initiated'&&!(u.status==='uploaded'&&u.content_hash===digest(b.toString('base64'))))fail(409,'STATE_CONFLICT','Загрузка уже завершена');
        if(u.expires_at<=new Date().toISOString())fail(409,'STATE_CONFLICT','Загрузка истекла');
        const magic=b.subarray(0,8);const valid=u.mime==='image/jpeg'?magic[0]===255&&magic[1]===216&&magic[2]===255:u.mime==='image/png'?magic.equals(Buffer.from([137,80,78,71,13,10,26,10])):magic.subarray(0,5).toString()==='%PDF-';
        if(!valid)fail(422,'POLICY_REJECTED','Содержимое не соответствует формату');
        await this.files.write(u.id,b);return this.store.put({...u,status:'uploaded',content_hash:digest(b.toString('base64')),version:u.version+1});
      }
      if(upload[2]==='finalize'&&method==='POST') {
        if(u.status==='clean')return u;
        if(u.expires_at<=new Date().toISOString())fail(409,'STATE_CONFLICT','Загрузка истекла');
        if(!['uploaded','processing','scanning'].includes(u.status))fail(409,'STATE_CONFLICT','Файл не загружен');
        if(!this.providers.scanner)fail(503,'SCANNER_UNAVAILABLE','Антивирус и база сигнатур ещё не настроены. Файл остаётся закрытым.');
        if(u.mime==='application/pdf'&&!this.providers.pdfSanitizer)fail(503,'PDF_SANITIZER_UNAVAILABLE','Проверка активных элементов PDF ещё не настроена');
        if(u.status!=='uploaded')return u;
        return this.store.put({...u,status:'processing',version:u.version+1});
      }
      if(upload[2]==='download'&&method==='GET') {
        await this.authorizeFile(u,a,q);
        if(u.purpose==='export')return {download_stream:await this.files.readStream(u.id),download_size:u.stored_size??u.size,mime:u.mime};
        return {download_buffer:await this.files.read(q.variant==='preview'&&u.preview_file_id?u.preview_file_id:u.id),mime:u.mime};
      }
      if(upload[2]==='download-url'&&method==='GET') {
        await this.authorizeFile(u,a,q);const token=randomBytes(32).toString('base64url');
        const ticket=this.record('download_ticket',a,{upload_id:u.id,token_hash:digest(token),family:a.family,reason:q.reason,variant:q.variant??'original',status:'active',expires_at:new Date(Date.now()+5*60000).toISOString()});await this.store.put(ticket);
        return {url:'/api/v1/private-files/'+u.id+'?token='+token,expires_at:ticket.expires_at,one_use:true};
      }
    }
    if(path.startsWith('/admin/')) {
      const section=path.split('/')[2];
      const permission=({audit:'auditor','support-threads':'support','recovery-threads':'support',verifications:'verification_reviewer',portfolio:'content',contractors:'content','price-versions':'billing','monetization-configs':'billing',promotions:'billing','referral-campaigns':'campaign','push-campaigns':'campaign','moderation-dictionaries':'moderator_manager','ranking-configs':'content','placement-policies':'promotion','brand-icons':'brand_owner',cases:'moderator','privacy-requests':'privacy',blacklist:'senior_moderator'} as Record<string,string>)[section]??'administrator';
      await this.staff(a,permission);
      const kinds:Record<string,string>={users:'user',orders:'order','support-threads':'support',cases:'case',audit:'audit',blacklist:'blacklist',portfolio:'portfolio',contractors:'contractor','privacy-requests':'privacy','monetization-configs':'monetization_config','price-versions':'price_version','categories':'category','push-campaigns':'push_campaign','referral-campaigns':'referral_campaign','moderation-dictionaries':'dictionary','ranking-configs':'ranking_config','promotions':'promotion','placement-policies':'placement_policy','verification-policies':'verification_policy','retention-policies':'retention_policy',verifications:'verification'};
      if(path==='/admin/dashboard'&&method==='GET')return {users:(await this.store.all('user',a.country)).filter(u=>!u.staff_permissions?.length).length,orders:(await this.store.all('order',a.country)).length,support:(await this.store.all('support',a.country)).filter(x=>x.status!=='resolved').length,country:a.country,mode:'development',checkout_enabled:false};
      if(path==='/admin/boost-grants'&&method==='POST'){await this.staff(a,'promotion');const reason=text(b,'reason',10,1000);const result=await this.growth.adminBoost(a.id,a.country,{...b,reason});await this.audit(a,'boost.admin_grant',result.id,reason);return result;}
      if(path==='/admin/boost-reports'&&method==='GET'){await this.staff(a,'promotion');return this.list(await this.store.all('boost',a.country),q);}
      if(path==='/admin/runtime-settings'&&method==='GET')return {settings:await this.settings(a.country),items:await this.store.all('runtime_settings',a.country)};
      if(path==='/admin/entitlement-grants'&&method==='POST') {
        await this.staff(a,'billing');const owner=await this.object(String(b.user_id),a,'user');
        const allowed=['search_full','publish_order','select_offer','send_offer','publish_profile'];
        if(!Array.isArray(b.capabilities)||!b.capabilities.length||b.capabilities.some((c:string)=>!allowed.includes(c)))fail(400,'VALIDATION_ERROR','Проверьте набор прав');
        const end=Date.parse(String(b.valid_until));if(!Number.isFinite(end)||end<=Date.now()||end>Date.now()+30*86400000)fail(400,'VALIDATION_ERROR','Нужно конечное право не дольше 30 дней');
        const r=this.record('compensation_request',a,{user_id:owner.id,capabilities:b.capabilities,valid_until:new Date(end).toISOString(),reason:text(b,'reason',10,1000),status:'draft'});await this.store.put(r);await this.audit(a,'compensation.draft',r.id,r.reason);return r;
      }
      const compensation=path.match(/^\/admin\/entitlement-grants\/([^/]+)\/approve$/);
      if(compensation&&method==='POST') {
        await this.staff(a,'billing');const r=await this.object(compensation[1],a,'compensation_request');this.version(r,b);if(r.owner===a.id)fail(403,'SECOND_APPROVAL_REQUIRED','Нужно независимое подтверждение');
        if(r.status!=='draft'||r.valid_until<=new Date().toISOString())fail(409,'STATE_CONFLICT','Запрос уже обработан или истёк');
        const grant=this.record('grant',{id:r.user_id,country:a.country},{source:'admin_compensation',source_id:r.id,capabilities:r.capabilities,valid_until:r.valid_until,approval_actor:a.id,reason:r.reason});await this.store.put(grant);
        const result=await this.store.put({...r,status:'approved',grant_id:grant.id,approved_by:a.id,version:r.version+1});await this.audit(a,'compensation.approved',r.id,text(b,'reason',10,1000));return result;
      }
      if(path==='/admin/runtime-settings'&&method==='POST') {
        try{validateSettings({...await this.settings(a.country),...b.settings});}catch(e:any){fail(400,'VALIDATION_ERROR',e.message);}
        const old=(await this.store.all('runtime_settings',a.country)).find(x=>x.status==='effective');if(old)this.version(old,b);
        const result=await this.store.put({...old??this.record('runtime_settings',a),payload:{...await this.settings(a.country),...b.settings},status:'effective',version:old?old.version+1:1});await this.audit(a,'settings.changed',result.id,text(b,'reason',10,1000));return result;
      }
      const contentDecision=path.match(/^\/admin\/(portfolio|contractors)\/([^/]+)\/decision$/);
      if(contentDecision&&method==='POST') {
        const r=await this.object(contentDecision[2],a,contentDecision[1]==='portfolio'?'portfolio':'contractor');this.version(r,b);
        if(!['pending_review','pending_moderation'].includes(editableContent(r).status))fail(409,'STATE_CONFLICT','Материал не ожидает проверки');
        if(!['approve','reject'].includes(b.decision))fail(400,'VALIDATION_ERROR','Выберите approve или reject');
        const owner=(await this.store.get(r.owner))!;if(b.decision==='approve'&&owner.status!=='active')fail(403,'FORBIDDEN','Новые действия исполнителя ограничены');if(b.decision==='approve'&&owner.verification!=='passed')fail(403,'VERIFICATION_REQUIRED','Проверка исполнителя не действует');
        const reason=text(b,'reason',10,1000);
        if(['published','paused'].includes(r.status)&&r.draft&&b.decision==='approve')await this.store.put(this.record('content_revision',{id:r.owner,country:r.country},{source_id:r.id,source_kind:r.kind,source_version:r.published_version??r.version,content:publicContent(r),status:'archived'}));
        const decided={...editableContent(r),status:b.decision==='approve'?(r.status==='paused'?'paused':'published'):'rejected',moderation_status:b.decision==='approve'?'approved':'rejected',reviewer_id:a.id,reason,version:r.version+1};
        const result=await this.store.put(['published','paused'].includes(r.status)&&b.decision==='reject'?{...r,draft:{...r.draft,status:'rejected',reason,reviewer_id:a.id},version:r.version+1}:{...decided,draft:undefined,public_status:undefined,...(b.decision==='approve'?{published_at:new Date().toISOString(),published_version:r.version+1}:{})});await this.audit(a,'content.'+b.decision,r.id,reason);return editableContent(result);
      }
      const blacklistDecision=path.match(/^\/admin\/blacklist\/([^/]+)\/decision$/);
      if(blacklistDecision&&method==='POST') {
        const r=await this.object(blacklistDecision[1],a,'blacklist');this.version(r,b);if(!['release','extend','overturn'].includes(b.decision))fail(400,'VALIDATION_ERROR','Недопустимое решение');
        const reason=text(b,'reason',10,1000),end=Date.parse(String(b.ends_at));if(b.decision==='extend'&&(!Number.isFinite(end)||end<=Date.now()))fail(400,'VALIDATION_ERROR','Нужен конечный срок');
        const result=await this.store.put({...r,status:b.decision==='extend'?'active':b.decision==='overturn'?'overturned':'released',ends_at:b.decision==='extend'?new Date(end).toISOString():r.ends_at,reason,version:r.version+1});await this.audit(a,'blacklist.'+b.decision,r.id,reason);return result;
      }
      if(path==='/admin/brand-icons'&&method==='POST')return this.branding.version(a.id,a.country,String(b.upload_id),b.crop);
      const brand=path.match(/^\/admin\/brand-icons\/([^/]+)\/(approve|generate)$/);
      if(brand&&method==='POST') {
        const r=await this.object(brand[1],a,'brand_icon');this.version(r,b);
        if(brand[2]==='approve') {
          if(r.owner===a.id)fail(403,'SECOND_APPROVAL_REQUIRED','Нужно второе подтверждение');const result=await this.store.put({...r,status:'approved',approved_by:a.id,version:r.version+1});await this.audit(a,'brand.approved',r.id,text(b,'reason',10,1000));return result;
        }
        const result=await this.branding.generate(r);await this.audit(a,'brand.generated',r.id,text(b,'reason',10,1000));return result;
      }
      if(path==='/admin/legal/documents'&&method==='GET')return {items:await this.store.all('legal_document',a.country)};
      if(path==='/admin/legal/documents'&&method==='POST') {
        const content=text(b,'content',50,100000);const r=this.record('legal_document',a,{type:text(b,'type',2,50),locale:text(b,'locale',2,5),content,hash:digest(content),status:'draft'});await this.store.put(r);await this.audit(a,'legal.draft',r.id,text(b,'reason',5,1000));return r;
      }
      const legalPublish=path.match(/^\/admin\/legal\/documents\/([^/]+)\/publish$/);
      if(legalPublish&&method==='POST'){const r=await this.object(legalPublish[1],a,'legal_document');this.version(r,b);if(r.owner===a.id)fail(403,'SECOND_APPROVAL_REQUIRED','Нужно подтверждение другого уполномоченного сотрудника');const result=await this.store.put({...r,status:'published',published_at:new Date().toISOString(),version:r.version+1});await this.audit(a,'legal.published',r.id,text(b,'reason',5,1000));return result;}
      const vd=path.match(/^\/admin\/verifications\/([^/]+)\/decision$/);
      if(vd&&method==='POST') {
        const r=await this.object(vd[1],a,'verification');this.version(r,b);if(r.status!=='pending_review'||b.document_revision!==r.document_revision)fail(409,'STATE_CONFLICT','Ревизия документа изменилась');
        if(!['passed','rejected','expired'].includes(b.decision))fail(400,'VALIDATION_ERROR','Недопустимое решение');const reason=text(b,'reason',10,1000);
        const end=Date.parse(String(b.expires_at));if(b.decision==='passed'&&(!Number.isFinite(end)||end<=Date.now()))fail(400,'VALIDATION_ERROR','Нужен срок действующей проверки');
        const u=(await this.store.get(r.owner))!;await this.store.put({...u,verification:b.decision,version:u.version+1});
        const result=await this.store.put({...r,status:b.decision,expires_at:b.decision==='passed'?new Date(end).toISOString():null,reason,reviewer_id:a.id,decided_at:new Date().toISOString(),version:r.version+1});await this.audit(a,'verification.'+b.decision,r.id,reason);if(b.decision==='passed')await this.growth.qualify(r.owner,a.country,'executor_verified',r.id);return {...result,document_refs:undefined};
      }
      if(method==='GET'&&kinds[section]&&path.split('/').length===3)return this.list((await this.store.all(kinds[section],a.country)).filter(x=>section!=='users'||!x.staff_permissions?.length).map(x=>section==='users'?{...safeUser(x),version:x.version,status:x.status}:section==='verifications'?{...x,document_refs:undefined}:['portfolio','contractors'].includes(section)?editableContent(x):x),q);
      const reviewDetail=path.match(/^\/admin\/(orders|portfolio|contractors|verifications|support-threads|privacy-requests)\/([^/]+)$/);
      if(reviewDetail&&method==='GET') {
        const kind=reviewDetail[1]==='contractors'?'contractor':kinds[reviewDetail[1]];
        const r=await this.object(reviewDetail[2],a,kind);
        if(reviewDetail[1]==='verifications') {
          const {document_refs,...safe}=r;
          if(q.include_documents==='true') {
            await this.staff(a,'identity_view');const reason=text(q,'reason',10,1000);
            await this.audit(a,'verification.documents_read',r.id,reason);
            return {...safe,document_refs};
          }
          return safe;
        }
        return ['portfolio','contractors'].includes(reviewDetail[1])?editableContent(r):r;
      }
      const userDetail=path.match(/^\/admin\/users\/([^/]+)$/);
      const securityEvents=path.match(/^\/admin\/users\/([^/]+)\/security-events$/);
      if(securityEvents&&method==='GET') {
        await this.staff(a,'security');const u=await this.object(securityEvents[1],a,'user');if(!q.reason||String(q.reason).length<10)fail(400,'VALIDATION_ERROR','Укажите служебную причину');
        await this.audit(a,'security.events_read',u.id,String(q.reason));return this.list((await this.store.all('security_event',a.country)).filter(x=>x.owner===u.id),q);
      }
      if(userDetail&&method==='GET'){
        const u=await this.object(userDetail[1],a,'user');const result:any={...safeUser(u),status:u.status,version:u.version};
        if(q.include_phone==='true'){await this.staff(a,'phone_view');if(!q.reason||String(q.reason).length<10)fail(400,'VALIDATION_ERROR','Нужна причина раскрытия телефона');await this.audit(a,'user.phone_read',u.id,String(q.reason));result.phone=u.phone;result.phone_status='unverified';}
        return result;
      }
      if(path==='/admin/recovery-threads'&&method==='GET')return this.list((await this.store.all('recovery',a.country)).map(({capability_hash,...r})=>r),q);
      const recoveryDetail=path.match(/^\/admin\/recovery-threads\/([^/]+)$/);
      if(recoveryDetail&&method==='GET'){const {capability_hash,...safe}=await this.object(recoveryDetail[1],a,'recovery');return safe;}
      const recoveryStaff=path.match(/^\/admin\/recovery-threads\/([^/]+)\/(assign|messages)$/);
      if(recoveryStaff) {
        const r=await this.object(recoveryStaff[1],a,'recovery');
        if(recoveryStaff[2]==='assign'&&method==='POST'){this.version(r,b);const result=await this.store.put({...r,assignee_id:a.id,status:'assigned',version:r.version+1});await this.audit(a,'recovery.assigned',r.id,text(b,'reason',10,1000));const {capability_hash,...safe}=result;return safe;}
        if(r.assignee_id!==a.id)fail(403,'FORBIDDEN','Обращение не назначено вам');
        if(method==='GET')return {items:(await this.store.all('recovery_message',a.country)).filter(x=>x.thread_id===r.id)};
        if(method==='POST') {
          const previous=(await this.store.all('recovery_message',a.country)).filter(x=>x.thread_id===r.id);const m=this.record('recovery_message',a,{thread_id:r.id,text:text(b,'text',1,3000),sequence:previous.length+1});await this.store.put(m);await this.audit(a,'recovery.replied',r.id,'Ответ сотрудника поддержки');return m;
        }
      }
      const supportNote=path.match(/^\/admin\/support-threads\/([^/]+)\/internal-notes$/);
      if(supportNote) {
        await this.staff(a,'support_internal');const t=await this.object(supportNote[1],a,'support');
        if(method==='GET')return this.list((await this.store.all('support_note',a.country)).filter(n=>n.thread_id===t.id),q);
        if(method==='POST'){const r=this.record('support_note',a,{thread_id:t.id,text:text(b,'text',1,3000)});await this.store.put(r);await this.audit(a,'support.internal_note',t.id,'Добавлена внутренняя заметка');return r;}
      }
      const supportCommand=path.match(/^\/admin\/support-threads\/([^/]+)\/(messages|commands)$/);
      if(supportCommand) {
        const t=await this.object(supportCommand[1],a,'support');
        if(supportCommand[2]==='messages') {
          if(!a.user.staff_permissions.includes('support'))fail(403,'FORBIDDEN','Требуется право поддержки');
          if(t.assignee_id!==a.id)fail(403,'FORBIDDEN','Обращение не назначено вам');
          return this.messages(t,a,method,b,q,'support_message');
        }
        if(method==='POST') {
          this.version(t,b);
          const states:Record<string,string>={assign:'assigned',resolve:'resolved',wait_user:'waiting_user',wait_support:'waiting_support',reopen:'assigned'};
          if(!states[b.command])fail(400,'VALIDATION_ERROR','Недопустимая команда');
          if(b.command!=='assign'&&t.assignee_id!==a.id)fail(403,'FORBIDDEN','Обращение не назначено вам');
          if(b.command==='reopen'&&t.status!=='resolved')fail(409,'STATE_CONFLICT','Обращение не закрыто');
          if(b.command==='resolve'&&b.reopen_until!==undefined&&(!Number.isFinite(Date.parse(b.reopen_until))||Date.parse(b.reopen_until)<=Date.now()))fail(400,'VALIDATION_ERROR','Проверьте срок повторного открытия');
          const result=await this.store.put({...t,status:states[b.command],assignee_id:a.id,...(b.command==='resolve'?{resolved_at:new Date().toISOString(),reopen_until:b.reopen_until??null}:{}),version:t.version+1});await this.audit(a,'support.'+b.command,t.id,text(b,'reason',5,1000));return result;
        }
      }
      const blacklist=path.match(/^\/admin\/users\/([^/]+)\/blacklist$/);
      if(blacklist&&method==='POST') {
        if(!a.user.staff_permissions.includes('senior_moderator'))fail(403,'FORBIDDEN','Требуется старший модератор');
        const u=await this.object(blacklist[1],a,'user');this.version(u,b);
        const c=await this.object(String(b.case_id),a,'case');
        const ends=Date.parse(String(b.ends_at));if(!Number.isFinite(ends)||ends<=Date.now())fail(400,'VALIDATION_ERROR','Задайте конечный срок');
        const r=this.record('blacklist',a,{user_id:u.id,case_id:c.id,scope:'new_business',reason:text(b,'reason',10,1000),status:'active',ends_at:new Date(ends).toISOString()});
        await this.store.put(r);await this.store.put({...u,status:'restricted',version:u.version+1});await this.audit(a,'blacklist.created',u.id,r.reason);await this.notify(u.id,a,'sanction.created',r.id);return r;
      }
      const configKinds=['monetization-configs','price-versions','categories','push-campaigns','referral-campaigns','moderation-dictionaries','ranking-configs','promotions','placement-policies','verification-policies','retention-policies'];
      if(configKinds.includes(section)&&method==='POST'&&path.split('/').length===3) {
        if(section==='moderation-dictionaries'){try{validateRules(b.payload?.rules);}catch(e:any){fail(400,'VALIDATION_ERROR',e.message);}}
        const r=this.record(kinds[section],a,{title:text(b,'title',3,120),status:'draft',payload:b.payload??{}});
        await this.store.put(r);await this.audit(a,section+'.draft',r.id,text(b,'reason',5,1000));return r;
      }
      const dictionaryCommand=path.match(/^\/admin\/moderation-dictionaries\/([^/]+)\/(validate|preview|publish)$/);
      if(dictionaryCommand&&method==='POST') {
        const d=await this.object(dictionaryCommand[1],a,'dictionary');try{validateRules(d.payload.rules);}catch(e:any){fail(400,'VALIDATION_ERROR',e.message);}
        if(dictionaryCommand[2]!=='publish')return {valid:true,version:d.version,rules:d.payload.rules.length,retroactive:false};
        this.version(d,b);if(d.owner===a.id)fail(403,'SECOND_APPROVAL_REQUIRED','Публикацию подтверждает другой сотрудник');
        const result=await this.store.put({...d,status:'published',published_at:new Date().toISOString(),version:d.version+1});await this.audit(a,'dictionary.published',d.id,text(b,'reason',10,1000));return result;
      }
      const hold=path.match(/^\/admin\/auto-holds\/([^/]+)\/decision$/);
      if(hold&&method==='POST') {
        const h=await this.object(hold[1],a,'auto_hold');this.version(h,b);const reason=text(b,'reason',10,1000);
        if(!['release','extend'].includes(b.decision))fail(400,'VALIDATION_ERROR','Решение release либо extend');
        const end=Date.parse(String(b.ends_at));if(b.decision==='extend'&&(!Number.isFinite(end)||end<=Date.now()))fail(400,'VALIDATION_ERROR','Задайте конечный срок');
        const result=await this.store.put({...h,status:b.decision==='release'?'released':'active',expires_at:b.decision==='extend'?new Date(end).toISOString():h.expires_at,reason,version:h.version+1});await this.audit(a,'hold.'+b.decision,h.id,reason);return result;
      }
      const staffCase=path.match(/^\/admin\/cases\/([^/]+)(?:\/(messages))?$/);
      if(staffCase&&['GET','POST'].includes(method)){
        const c=await this.object(staffCase[1],a,'case');
        if(!staffCase[2]&&method==='GET')return c;
        if(staffCase[2]){
          if(method==='GET')return this.list((await this.store.all('case_message',a.country)).filter(m=>m.case_id===c.id),q);
          const reason=text(b,'reason',10,1000);const m=await this.store.put(this.record('case_message',a,{case_id:c.id,text:text(b,'text',1,3000),internal:false,upload_ids:[]}));
          await this.audit(a,'case.message_created',c.id,reason);await this.notify(c.owner,a,'case.message.created',c.id);return m;
        }
      }
      const caseDecision=path.match(/^\/admin\/cases\/([^/]+)\/(resolve|appeal-decision)$/);
      if(caseDecision&&method==='POST') {
        const c=await this.object(caseDecision[1],a,'case');this.version(c,b);if(caseDecision[2]==='appeal-decision'&&(!a.user.staff_permissions.includes('senior_moderator')||c.decision_actor===a.id))fail(403,'FORBIDDEN','Нужен независимый старший модератор');
        const reason=text(b,'reason',10,1000);if(!['no_violation','content_removed','sanction_upheld','overturned'].includes(b.decision))fail(400,'VALIDATION_ERROR','Недопустимое решение');
        const r=await this.store.put({...c,status:'resolved',decision:b.decision,decision_actor:a.id,reason,version:c.version+1});await this.audit(a,'case.'+b.decision,c.id,reason);return r;
      }
      const configurationCommand=path.match(/^\/admin\/([^/]+)\/([^/]+)\/(validate|preview|publish)$/);
      if(configurationCommand&&configKinds.includes(section)&&method==='POST') {
        const r=await this.object(configurationCommand[2],a,kinds[section]);
        if(configurationCommand[3]!=='publish')return this.configuration.validate(r);
        const result=await this.configuration.publish(r,a.id,b.expected_version);await this.audit(a,section+'.published',r.id,text(b,'reason',10,1000));return result;
      }
      const configurationStop=path.match(/^\/admin\/([^/]+)\/([^/]+)\/(stop|cancel|rollback)$/);
      if(configurationStop&&configKinds.includes(section)&&method==='POST') {
        const r=await this.object(configurationStop[2],a,kinds[section]);this.version(r,b);const reason=text(b,'reason',10,1000);
        if(configurationStop[3]==='rollback'){const draft=this.record(r.kind,a,{title:r.title,payload:r.payload,status:'draft',rollback_of:r.id});await this.store.put(draft);await this.audit(a,section+'.rollback_draft',draft.id,reason);return draft;}
        const result=await this.store.put({...r,status:'stopped',version:r.version+1});await this.audit(a,section+'.stopped',r.id,reason);return result;
      }
      fail(404,'NOT_FOUND','Команда ещё не реализована');
    }
    fail(404,'NOT_FOUND','Маршрут не найден');
  }
  private async reauth(a:Actor,b:any) {
    const c=(await this.store.db.query<any>('SELECT password_hash FROM credentials WHERE user_id=$1',[a.id])).rows[0];
    if(!c||!await verify(c.password_hash,String(b.current_password??'')))fail(401,'INVALID_CREDENTIALS','Подтвердите текущий пароль');
  }
  private pageLimit(q:any) {const limit=q.limit===undefined?20:Number(q.limit);if(!Number.isInteger(limit)||limit<1||limit>100)fail(400,'VALIDATION_ERROR','limit должен быть от 1 до 100');return limit;}
  private filterHash(q:any) {return digest(JSON.stringify(Object.fromEntries(Object.entries(q).filter(([k])=>!['cursor','limit'].includes(k)).sort(([a],[b])=>a.localeCompare(b)))));}
  private async cursor(q:any):Promise<string|undefined> {
    if(!q.cursor)return undefined;
    try {
      const [payload,signature]=String(q.cursor).split('.');if(!payload||!signature||String(q.cursor).length>1000)throw Error();
      if(signature!==await this.files.requestDigest(payload))throw Error();const decoded=JSON.parse(Buffer.from(payload,'base64url').toString());
      if(decoded.filter_hash!==this.filterHash(q)||decoded.expires_at<=new Date().toISOString()||!/^[-0-9a-f]{36}$/.test(decoded.after))throw Error();return decoded.after;
    }catch {return fail(400,'VALIDATION_ERROR','Cursor недействителен или относится к другим фильтрам',{restart_required:true});}
  }
  private async nextCursor(id:string,q:any) {
    const payload=Buffer.from(JSON.stringify({after:id,filter_hash:this.filterHash(q),expires_at:new Date(Date.now()+86400000).toISOString()})).toString('base64url');return payload+'.'+await this.files.requestDigest(payload);
  }
  private async page(kind:string,a:Actor,q:any,options:{owner?:string;participant?:string;executor?:string;statuses?:string[];publicActor?:string}={}) {
    const limit=this.pageLimit(q),after=await this.cursor(q);
    const selected=await this.store.select(kind,a.country,{...options,limit:limit+1,after,city:q.city,category:q.category_id,search:q.q,sourceId:q.source_id});
    const items=selected.slice(0,limit).map(x=>options.publicActor&&kind==='order'?{...x,exact_address:undefined}:options.publicActor&&kind==='contractor'?publicContent(x):x);return {items,meta:{next_cursor:selected.length>limit?await this.nextCursor(items.at(-1)!.id,q):null}};
  }
  private async portfolioPage(records:RecordData[],q:any) {
    const sorted=records.filter(r=>(!q.category_id||r.category_id===q.category_id)&&(!q.q||[r.title,r.description].join(' ').toLowerCase().includes(String(q.q).toLowerCase()))).sort((x,y)=>(x.position??0)-(y.position??0)||x.id.localeCompare(y.id));
    const scoped={...q,_portfolio_order:digest(JSON.stringify(sorted.map(r=>[r.id,r.position??0,r.published_version??r.version])))};
    const after=await this.cursor(scoped),start=after?sorted.findIndex(r=>r.id===after)+1:0,limit=this.pageLimit(q),batch=sorted.slice(start,start+limit);
    return {items:batch,meta:{next_cursor:start+batch.length<sorted.length?await this.nextCursor(batch.at(-1)!.id,scoped):null}};
  }
  private async list(items:any[],q:any) {
    const limit=this.pageLimit(q),after=await this.cursor(q);
    const filtered=items.filter(x=>(!after||x.id>after)&&(!q.status||x.status===q.status)&&(!q.city||x.city===q.city)&&(!q.category_id||x.category_id===q.category_id)&&(!q.q||[x.id,x.title,x.display_name,x.subject,x.action,x.reason].filter(Boolean).join(' ').toLowerCase().includes(String(q.q).toLowerCase()))).sort((a,b)=>a.id.localeCompare(b.id));
    const page=filtered.slice(0,limit);return {items:page,meta:{next_cursor:filtered.length>limit?await this.nextCursor(page.at(-1).id,q):null,total:filtered.length}};
  }
  private async messages(c:RecordData,a:Actor,method:string,b:any,q:any,kind:string) {
    const watermark=new Date().toISOString();
    const all=(await this.store.all(kind,a.country)).filter(x=>x.thread_id===c.id).sort((x,y)=>x.sequence-y.sequence);
    if(method==='GET') {
      for(const key of ['after_sequence','before_sequence'])if(q[key]!==undefined&&(!Number.isSafeInteger(Number(q[key]))||Number(q[key])<0))fail(400,'VALIDATION_ERROR','Проверьте границу истории');
      if(q.updated_since!==undefined&&!Number.isFinite(Date.parse(q.updated_since)))fail(400,'VALIDATION_ERROR','Проверьте время обновления');
      const render=(m:RecordData)=>{
      const recipients=(c.members??[]).filter((id:string)=>id!==m.owner);
      const read=recipients.length&&recipients.every((id:string)=>(c.read_sequences?.[id]??0)>=m.sequence);
      const delivered=recipients.length&&recipients.every((id:string)=>(c.delivered_sequences?.[id]??0)>=m.sequence);
      const hidden=m.moderation_status==='quarantined'&&m.owner!==a.id;
      return {...m,...(m.tombstone||hidden?{text:'',upload_ids:[]}:{}),hidden,delivery_state:m.moderation_status==='quarantined'?'quarantined':read?'read':delivered?'delivered':'sent'};
      };
      const visible=all.filter(m=>m.moderation_status!=='quarantined'||m.owner===a.id);
      const selected=q.after_sequence!==undefined?visible.filter(m=>m.sequence>Number(q.after_sequence)).slice(0,100):visible.filter(m=>q.before_sequence===undefined||m.sequence<Number(q.before_sequence)).slice(-100);
      const updates=q.updated_since?all.filter(m=>m.edited_at&&m.edited_at>=q.updated_since):[];
      return {items:selected.map(render),updates:updates.slice(0,100).map(render),meta:{server_time:watermark,updates_truncated:updates.length>100,has_more:selected.length>0&&visible.some(m=>m.sequence<selected[0].sequence)}};
    }
    if(method!=='POST')fail(404,'NOT_FOUND','Маршрут не найден');
    if(c.status==='closed')fail(409,'STATE_CONFLICT','Чат закрыт для новых сообщений');
    if(c.kind==='support'&&c.status==='resolved'&&(!c.reopen_until||c.reopen_until<=new Date().toISOString()))fail(409,'STATE_CONFLICT','Обращение закрыто. Можно создать новое.');
    if(c.kind==='conversation') {
      for(const other of c.members)if(other!==a.id&&await this.blocked(a,other))fail(403,'PAIR_BLOCKED','Прямой контакт ограничен. Поддержка доступна.');
      if(c.status==='open'){const o=await this.object(c.order_id,a,'order');if(o.status!=='open')fail(409,'STATE_CONFLICT','Заказ закрыт');await this.entitlement(a,'search_full');}
    }
    const uploadIds=b.upload_ids?await this.safeUploads(a,b.upload_ids,'chat'):[];
    const clientId=text(b,'client_message_id',36,36),message=text(b,'text',uploadIds.length?0:1,3000);
    const duplicate=(await this.store.all(kind,a.country)).find(x=>x.client_message_id===clientId&&x.owner===a.id);
    if(duplicate){if(duplicate.text!==message||duplicate.thread_id!==c.id||JSON.stringify(duplicate.upload_ids??[])!==JSON.stringify(uploadIds))fail(409,'IDEMPOTENCY_CONFLICT','ID сообщения использован для другого содержания или чата');return duplicate;}
    const m=this.record(kind,a,{thread_id:c.id,sequence:all.length+1,client_message_id:clientId,text:message,delivery_state:'sent',upload_ids:uploadIds});await this.store.put(m);
    if(c.kind==='support')await this.store.put({...c,status:c.status==='new'?'new':a.id===c.owner?'waiting_support':'waiting_user',last_activity:new Date().toISOString(),version:c.version+1});
    if(m.moderation_status!=='quarantined')for(const recipient of c.members??[c.owner])if(recipient!==a.id)await this.notify(recipient,a,kind==='message'?'message.created':'support.message.created',c.id);
    return m;
  }
  private async notify(owner:string,a:Pick<Actor,'id'|'country'>,type:string,target:string) {
    const notification=this.record('notification',{id:owner,country:a.country},{type,target_id:target,read:false});await this.store.put(notification);
    await this.store.db.query('INSERT INTO events(event_id,recipient_id,country,data) VALUES($1,$2,$3,$4)',[notification.id,owner,a.country,JSON.stringify({event_id:notification.id,type,aggregate_id:target,occurred_at:notification.created_at})]);
    await this.store.put(this.record('outbox',a,{type,target_id:target,recipient_id:owner,event_id:notification.id,status:'pending',attempts:0}));
    // Subscribers queue their authorized read behind this transaction; nothing is sent before commit.
    this.events.emit(owner);
  }
  private async audit(a:Actor,action:string,target:string,reason:string) {
    return this.store.put(this.record('audit',a,{actor_id:a.id,action,target_id:target,reason,occurred_at:new Date().toISOString()}));
  }
  private async exclusive<T>(run:()=>Promise<T>) {const pending=this.queue.then(run,run);this.queue=pending.catch(()=>{});return pending;}
  async deliverOutbox() {
    if(!this.providers.push)return {sent:0,blocked:'push_provider_unavailable'};
    const pending=await this.exclusive(async()=>{
      const result=await this.store.db.query<{data:RecordData}>("SELECT data FROM records WHERE kind='outbox' AND data->>'status' IN('pending','retry') AND (data->>'next_attempt_at' IS NULL OR data->>'next_attempt_at'<=$1) ORDER BY id LIMIT 20",[new Date().toISOString()]);
      return result.rows.map(r=>r.data);
    });
    let sent=0;
    for(const entry of pending) {
      const delivery=await this.exclusive(async()=>{
        const current=await this.store.get(entry.id);if(!current||!['pending','retry'].includes(current.status))return;
        const user=await this.store.get(entry.recipient_id);
        if(!user||user.status==='deleted'){await this.store.put({...current,status:'suppressed',version:current.version+1});return;}
        const preference=entry.type.startsWith('message.')?'chat':entry.type.startsWith('marketing.')?'marketing':'service';
        if(user.notification_preferences?.[preference]===false||preference==='marketing'&&user.notification_preferences?.marketing!==true){await this.store.put({...current,status:'suppressed',version:current.version+1});return;}
        const quiet=user.notification_preferences?.quiet_hours;
        if(quiet){const clock=new Intl.DateTimeFormat('en-GB',{timeZone:quiet.time_zone,hour:'2-digit',minute:'2-digit',hour12:false}).format(new Date());const within=quiet.start<quiet.end?clock>=quiet.start&&clock<quiet.end:clock>=quiet.start||clock<quiet.end;if(within){await this.store.put({...current,status:'retry',next_attempt_at:new Date(Date.now()+60000).toISOString(),version:current.version+1});return;}}
        const tokens=(await this.store.all('push_token',entry.country)).filter(t=>t.owner===user.id&&t.status==='active');
        if(!tokens.length){await this.store.put({...current,status:'waiting_token',version:current.version+1});return;}
        await this.store.put({...current,status:'processing',version:current.version+1});return {current,tokens};
      });
      if(!delivery)continue;
      try {
        const ids:string[]=[];
        for(const token of delivery.tokens){const result=await Promise.race([this.providers.push.send(token.token,{event_id:entry.event_id,title:'JOBA',body:'Новое событие в приложении'}),new Promise<never>((_,reject)=>{const timer=setTimeout(()=>reject(Error('Push timeout')),10000);timer.unref();})]);ids.push(result.provider_message_id);}
        await this.exclusive(async()=>{const r=(await this.store.get(entry.id))!;await this.store.put({...r,status:'sent',provider_message_ids:ids,sent_at:new Date().toISOString(),version:r.version+1});});sent++;
      }catch {
        await this.exclusive(async()=>{const r=(await this.store.get(entry.id))!,attempts=(r.attempts??0)+1;await this.store.put({...r,status:attempts>=5?'dead_letter':'retry',attempts,next_attempt_at:new Date(Date.now()+Math.min(3600000,2**attempts*1000)).toISOString(),failure_code:'PUSH_PROVIDER_ERROR',version:r.version+1});});
      }
    }
    return {sent};
  }
  private async safeUploads(a:Actor,ids:any,purpose:string,max=10) {
    if(!Array.isArray(ids)||ids.length>max||new Set(ids).size!==ids.length)fail(400,'VALIDATION_ERROR','Проверьте список файлов');
    for(const id of ids){const u=await this.object(String(id),a,'upload',true);if(u.status!=='clean'||u.purpose!==purpose)fail(422,'UNSAFE_UPLOAD','Файл ещё не проверен или имеет другое назначение');}
    return ids;
  }
  private async authorizeFile(u:RecordData,a:Actor,q:any) {
    if(u.status!=='clean'||u.purpose==='export'&&u.expires_at<=new Date().toISOString())fail(404,'NOT_FOUND','Файл недоступен');
    if(u.purpose==='identity') {
      await this.staff(a,'identity_view');if(!q.reason||String(q.reason).length<10)fail(400,'VALIDATION_ERROR','Требуется служебная причина просмотра');await this.audit(a,'identity.sensitive_read',u.id,String(q.reason));
    }else if(u.owner!==a.id) {
      const related=(await this.store.all('message',a.country)).find(m=>!m.tombstone&&m.moderation_status!=='quarantined'&&m.upload_ids?.includes(u.id));const c=related?await this.store.get(related.thread_id):undefined;
      if(c?.members.includes(a.id))return;
      const supportMessage=(await this.store.all('support_message',a.country)).find(m=>!m.tombstone&&m.moderation_status!=='quarantined'&&m.upload_ids?.includes(u.id));
      const support=supportMessage?await this.store.get(supportMessage.thread_id):undefined;
      if(support?.owner===a.id)return;
      if(support?.assignee_id===a.id){await this.staff(a,'support');return;}
      if(u.purpose==='portfolio') {
        if(a.mfa&&(a.user.staff_permissions?.includes('content')||a.user.staff_permissions?.includes('administrator'))) {
          const projects=await this.store.all('portfolio',a.country),profiles=await this.store.all('contractor',a.country);
          const linked=[...projects,...profiles].some(r=>r.owner===u.owner&&r.status!=='archived'&&[...r.photos??[],...r.gallery_ids??[],...r.draft?.photos??[],...r.draft?.gallery_ids??[]].includes(u.id));
          if(linked){await this.staff(a,'content');const reason=text(q,'reason',10,1000);await this.audit(a,'content.media_read',u.id,reason);return;}
        }
        const project=(await this.store.all('portfolio',a.country)).find(p=>p.status==='published'&&!['quarantined','hidden','rejected'].includes(p.moderation_status)&&p.photos?.includes(u.id));
        const profile=(await this.store.all('contractor',a.country)).find(p=>p.owner===u.owner&&p.status==='published'&&!['quarantined','hidden','rejected'].includes(p.moderation_status)&&(project||p.gallery_ids?.includes(u.id)));
        const owner=profile?await this.store.get(profile.owner):undefined;
        if(profile&&owner?.status==='active'&&owner.verification==='passed'&&!await this.blocked(a,profile.owner)){await this.entitlement(a,'search_full');return;}
      }
      if(u.purpose==='order') {
        const order=(await this.store.all('order',a.country)).find(o=>o.upload_ids?.includes(u.id));
        if(order&&[order.owner,order.executor_id].includes(a.id))return;
        const owner=order?await this.store.get(order.owner):undefined;
        if(owner?.status==='active'&&order?.expires_at>new Date().toISOString()&&order?.status==='open'&&!['quarantined','hidden','rejected'].includes(order.moderation_status)&&!await this.blocked(a,order.owner)){await this.entitlement(a,'search_full',true);return;}
      }
      if(u.purpose==='avatar') {
        const user=await this.store.get(u.owner);if(user?.status==='active'&&user.avatar_id===u.id&&!await this.blocked(a,u.owner)){await this.entitlement(a,'search_full');return;}
      }
      fail(404,'NOT_FOUND','Файл недоступен');
    }
  }
  private async blocked(a:Actor,other:string) {
    return (await this.store.all('pair_block',a.country)).some(x=>x.status==='active'&&(x.owner===a.id&&x.target_id===other||x.owner===other&&x.target_id===a.id));
  }
  private async settings(country:string) {
    return readSettings(this.store,country);
  }
  private async promotionGrant(a:Actor) {
    const now=new Date().toISOString();
    const promotion=(await this.store.all('promotion',a.country)).find(p=>p.status==='effective'&&p.preview?.promo_end_exclusive>now&&(!p.payload.valid_from||p.payload.valid_from<=now));
    if(!promotion)return;
    const existing=(await this.store.all('grant',a.country)).find(g=>g.owner===a.id&&g.source_id===promotion.id);if(existing)return;
    await this.store.put(this.record('grant',a,{source:'subscription_promotion',source_id:promotion.id,valid_until:promotion.preview.promo_end_exclusive,capabilities:['search_full','publish_order','select_offer','send_offer','publish_profile'],terms_snapshot:promotion.preview}));
  }
  private async processUpload(id:string):Promise<any>{
    const running=this.uploadTasks.get(id);if(running)return running;
    const task=this.runUpload(id).finally(()=>{if(this.uploadTasks.get(id)===task)this.uploadTasks.delete(id);});this.uploadTasks.set(id,task);return task;
  }
  private async runUpload(id:string):Promise<any>{
    if(this.scanSlots>0)this.scanSlots--;else await new Promise<void>(resolve=>this.scanWaiters.push(resolve));
    try{
      const upload:any=await this.exclusive(async()=>{
        await this.store.db.exec('BEGIN');try{
          await this.store.db.query('SELECT id FROM records WHERE id=$1 FOR UPDATE',[id]);
          const current=await this.store.get(id);if(!current||current.kind!=='upload')fail(404,'NOT_FOUND','Файл не найден');
          if(!['processing','scanning'].includes(current!.status)||current!.status==='scanning'&&current!.scan_lease_until>new Date().toISOString()||current!.next_attempt_at>new Date().toISOString()){await this.store.db.exec('COMMIT');return {...current,claimed:false};}
          if(!this.providers.scanner){await this.store.db.exec('COMMIT');return {...current,claimed:false,failure_code:'SCANNER_UNAVAILABLE'};}
          const claimed=await this.store.put({...current!,status:'scanning',scan_nonce:randomUUID(),scan_lease_until:new Date(Date.now()+120000).toISOString(),version:current!.version+1});await this.store.db.exec('COMMIT');return {...claimed,claimed:true};
        }catch(error){await this.store.db.exec('ROLLBACK');throw error;}
      });
      if(!upload.claimed)return upload;
      let state='clean',failure:string|null=null,clean:Buffer|undefined,previewId:string|undefined;
      try{
        const raw=await this.files.read(id);let verdict:string;
        try{verdict=await this.providers.scanner!.scan(raw,upload.mime);}catch{throw Error('SCANNER_UNAVAILABLE');}
        if(verdict==='infected')state='infected';else if(verdict!=='clean')throw Error('SCANNER_UNAVAILABLE');
        else if(upload.mime==='application/pdf'){
          if(!this.providers.pdfSanitizer)throw Error('PDF_SANITIZER_UNAVAILABLE');
          try{clean=await this.providers.pdfSanitizer.sanitize(raw);}catch{throw Error('PDF_POLICY_REJECTED');}
        }else{try{const image=sharp(raw,{limitInputPixels:25000000}),metadata=await image.metadata();if(metadata.format!==(upload.mime==='image/png'?'png':'jpeg'))throw Error('Unexpected image format');clean=await image.rotate().jpeg().toBuffer();}catch{throw Error('IMAGE_POLICY_REJECTED');}}
        if(clean){await this.files.write(id,clean);if(upload.mime!=='application/pdf'){const preview=await sharp(clean).resize({width:960,withoutEnlargement:true}).jpeg({quality:80}).toBuffer();previewId=randomUUID();await this.files.write(previewId,preview);}}
      }catch(error:any){failure=['SCANNER_UNAVAILABLE','PDF_SANITIZER_UNAVAILABLE','PDF_POLICY_REJECTED','IMAGE_POLICY_REJECTED'].includes(error.message)?error.message:'FILE_PROCESSING_UNAVAILABLE';state=['SCANNER_UNAVAILABLE','PDF_SANITIZER_UNAVAILABLE','FILE_PROCESSING_UNAVAILABLE'].includes(failure!)?'processing':'rejected';}
      return this.exclusive(async()=>{
        await this.store.db.exec('BEGIN');try{
          await this.store.db.query('SELECT id FROM records WHERE id=$1 FOR UPDATE',[id]);
          const current=await this.store.get(id);
          if(!current||current.scan_nonce!==upload.scan_nonce||current.status!=='scanning'){await this.store.db.exec('COMMIT');return current??{id,status:'expired'};}
          const attempts=(current.scan_attempts??0)+1;
          const result=await this.store.put({...current,status:state==='processing'&&attempts>=5?'rejected':state,failure_code:failure,scan_attempts:attempts,next_attempt_at:state==='processing'?new Date(Date.now()+Math.min(3600000,2**attempts*1000)).toISOString():null,scan_lease_until:null,mime:clean&&current.mime!=='application/pdf'?'image/jpeg':current.mime,stored_size:clean?.length??current.stored_size,...(previewId?{preview_file_id:previewId}:{}),version:current.version+1});
          await this.store.db.exec('COMMIT');return result;
        }catch(error){await this.store.db.exec('ROLLBACK');throw error;}
      });
    }finally{const next=this.scanWaiters.shift();if(next)next();else this.scanSlots++;}
  }
  async processPendingUploads(){
    const uploads=await this.exclusive(async()=>(await this.store.all('upload')).filter(u=>u.status==='processing'&&(!u.next_attempt_at||u.next_attempt_at<=new Date().toISOString())||u.status==='scanning'&&u.scan_lease_until<=new Date().toISOString()).slice(0,2));
    await Promise.all(uploads.map(u=>this.processUpload(u.id)));
  }
  private async processExport(job:RecordData,now:Date){
    const file=this.record('upload',{id:job.owner,country:job.country},{purpose:'export',mime:'application/zip',status:'clean',expires_at:new Date(now.getTime()+7*86400000).toISOString()});
    try{
      const snapshot=await this.exclusive(()=>exportSnapshot(this.store,job.owner,job.country));
      const size=await writeExport(this.files,file.id,snapshot,now.toISOString());
      const committed=await this.exclusive(async()=>{
        const current=await this.store.get(job.id),owner=await this.store.get(job.owner);
        if(current?.status!=='processing'||current.version!==job.version||owner?.status==='deleted')return false;
        await this.store.db.exec('BEGIN');try{
          await this.store.put({...file,size,stored_size:size});
          await this.store.put({...current,status:'completed',upload_id:file.id,completed_at:new Date().toISOString(),lease_expires_at:null,version:current.version+1});
          await this.notify(job.owner,{id:job.owner,country:job.country},'privacy.export.ready',job.id);
          await this.store.db.exec('COMMIT');return true;
        }catch(error){await this.store.db.exec('ROLLBACK');throw error;}
      });
      if(!committed)await this.files.remove(file.id);
    }catch{
      await this.files.remove(file.id);
      await this.exclusive(async()=>{const current=await this.store.get(job.id);if(current?.status!=='processing'||current.version!==job.version)return;
        const attempts=(current.attempts??0)+1;await this.store.put({...current,status:attempts>=5?'failed':'requested',attempts,failure_code:'EXPORT_RETRY_REQUIRED',next_attempt_at:new Date(Date.now()+Math.min(3600000,2**attempts*60000)).toISOString(),lease_expires_at:null,version:current.version+1});});
    }
  }
  async maintenance(now=new Date()) {
    const exportJobs:RecordData[]=[];
    const run=async()=>{
      await this.store.db.exec('BEGIN');
      try {
        for(const r of await this.store.all('order'))if(r.status==='open'&&r.expires_at<=now.toISOString())await this.store.put({...r,status:'expired',version:r.version+1});
        for(const r of await this.store.all('verification'))if(r.status==='passed'&&r.expires_at&&r.expires_at<=now.toISOString()) {
          await this.store.put({...r,status:'expired',version:r.version+1});const u=await this.store.get(r.owner);if(u)await this.store.put({...u,verification:'expired',version:u.version+1});
        }
        for(const r of await this.store.all('boost')) {
          if(['reserved','payment_pending'].includes(r.status)&&r.reservation_expires_at<=now.toISOString()){await this.store.put({...r,status:'expired',version:r.version+1});continue;}
          if(['active','paused','scheduled'].includes(r.status)&&r.ends_at<=now.toISOString()){await this.store.put({...r,status:'expired',version:r.version+1});continue;}
          if(r.status==='active'){const target=await this.store.get(r.target_id),owner=await this.store.get(r.owner);if(!target||!['open','published'].includes(target.status)||owner?.status!=='active'||target.kind==='contractor'&&owner.verification!=='passed')await this.store.put({...r,status:'paused',pause_reason:'target_ineligible',version:r.version+1});}
        }
        for(const r of await this.store.all('review'))if(r.status==='sealed'&&r.publish_after<=now.toISOString()) {
          const disputes=(await this.store.all('case',r.country)).filter(c=>c.target_id===r.order_id&&!['resolved','closed'].includes(c.status));
          if(!disputes.length)await this.store.put({...r,status:'published',version:r.version+1});
        }
        for(const kind of ['cancel_request','amendment','ad_session','recovery','auto_hold','blacklist'])for(const r of await this.store.all(kind)) {
          const end=r.expires_at??r.ends_at;if(end&&end<=now.toISOString()&&['pending','new','active'].includes(r.status))await this.store.put({...r,status:'expired',version:r.version+1});
        }
        for(const u of await this.store.all('user'))if(u.status==='restricted') {
          const active=(await this.store.all('blacklist',u.country)).some(x=>x.user_id===u.id&&x.status==='active')||(await this.store.all('auto_hold',u.country)).some(x=>x.user_id===u.id&&x.status==='active');
          if(!active)await this.store.put({...u,status:'active',version:u.version+1});
        }
        for(const r of await this.store.all('privacy'))if(r.type==='export'&&((r.status==='requested'&&(!r.next_attempt_at||r.next_attempt_at<=now.toISOString()))||(r.status==='processing'&&r.lease_expires_at<=now.toISOString()))) {
          const job=await this.store.put({...r,status:'processing',lease_expires_at:new Date(now.getTime()+3600000).toISOString(),version:r.version+1});exportJobs.push(job);
        }
        for(const r of await this.store.all('privacy'))if(['requested','awaiting_retention_policy'].includes(r.status)&&r.type==='delete') {
          const policy=(await this.store.all('retention_policy',r.country)).find(x=>x.status==='effective');
          if(!policy){if(r.status==='requested')await this.store.put({...r,status:'awaiting_retention_policy',version:r.version+1});continue;}
          const u=await this.store.get(r.owner);if(u)await this.store.put({...u,phone:null,display_name:'Удалённый пользователь',city:'',status:'deleted',version:u.version+1});
          await this.store.db.query('DELETE FROM credentials WHERE user_id=$1',[r.owner]);await this.store.db.query('UPDATE tokens SET revoked=true WHERE user_id=$1',[r.owner]);
          await this.store.db.query('DELETE FROM idempotency WHERE scope LIKE $1',[r.owner+':%']);
          for(const kind of ['contractor','portfolio'])for(const x of await this.store.all(kind,r.country))if(x.owner===r.owner)await this.store.put({...x,status:'archived',description:'',title:'',version:x.version+1});
          await this.store.put({...r,status:'limited_retention',reason:'История заказов и обязательные записи сохраняются по опубликованной политике',policy_id:policy.id,completed_at:now.toISOString(),version:r.version+1});
        }
        await this.store.db.query("DELETE FROM rate_limits WHERE window_start<CURRENT_TIMESTAMP-INTERVAL '1 day'");
        await this.store.db.exec('COMMIT');
      }catch(e){await this.store.db.exec('ROLLBACK');throw e;}
    };
    const promise=this.queue.then(run,run);this.queue=promise.catch(()=>{});await promise;
    for(const job of exportJobs)await this.processExport(job,now);
  }
}
