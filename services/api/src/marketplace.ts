import {refreshWorkFileProgress} from './work-file-retention';
import {processDeletionCategories} from './deletion-worker';
import {holdSnapshot} from './legal-holds';
import {deletionPlan,anonymizeProfile,validateRetentionCategories} from './deletion-plan';
import {Refunds} from './refunds';
import {monetizationPayload} from './monetization-payload';
import {placementPolicyPayload,placementPromises} from './placement-policy';
import {referralPolicy} from './referral-policy';
import {categoryId,categoryPayload} from './category-payload';
import {pricePayload} from './price-payload';
import {countryEnabled} from './country-access';
import {bannerCampaigns} from './banner-campaigns';
import {accountRestrictionJobs} from './account-restriction-jobs';
import {normalizePushPayload,validatePushCampaign,pushPreview,queuePushCampaigns,cancelPushCampaign,claimCampaignMessage,testCampaign,refreshPushCampaign} from './push-campaigns';
import {promotedListings,promotedPlacements} from './promoted-listings';
import {planFileRetention,purgedUpload} from './retention';
import {adminReports} from './admin-reports';
import {boostPresentation} from './boost-presentation';
import {productAnalytics} from './product-analytics';
import {rankingParameters,rankingPayload} from './ranking';
import {accountDecisions,securityEventSummary} from './staff-account';
import {currentLegalDocuments} from './legal-documents';
import {freezeTarget,visibleCase,resolveEffects,contentHash,targetSnapshot} from './case-evidence';
import {editableContent,publicContent,editContent,submitContent} from './content-revisions';
import {accountOverview} from './account-overview';
import {contractorPresentation} from './contractor-presentation';
import {orderBucket} from './order-buckets';
import {operationsOverview,operationJob} from './operations-overview';
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
import { Moderation, dictionaryPayload,validateRules, TEXT_SURFACES, matchesRule } from './moderation';
import { Configuration,normalizePromotionPayload } from './configuration';
import { Growth } from './growth';
import { Branding } from './branding';
import { DEFAULT_SETTINGS,validateSettings,readSettings } from './settings';
import { seedReferenceData,referenceId } from './reference-data';
import { attributes,timeWindow } from './validation';
import {offerTerms,offerPolicy,offerExpired,presentOffer,offerPeople,offerOrderSnapshot} from './offer-terms';
import { exportSnapshot,writeExport } from './privacy-export';
import { profileFields } from './contractor-profile';
import { EventEmitter } from 'node:events';

const digest = (s: string) => createHash('sha256').update(s).digest('hex');
const countries: Record<string, {currency: string; locales: string[]; cities: string[]}> = {
  KZ: {currency:'KZT',locales:['ru','kk'],cities:['Алматы','Астана','Шымкент']},
  KG: {currency:'KGS',locales:['ru'],cities:['Бишкек','Ош']},
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
  readonly refunds:Refunds;
  readonly files: PrivateFiles;
  readonly configuration:Configuration;
  readonly growth:Growth;
  readonly branding:Branding;
  private queue: Promise<any> = Promise.resolve();
  constructor(store = new Store(), providers = new Providers(), files = new PrivateFiles()) {
    this.store=store;this.providers=providers;this.commerce=new Commerce(store,providers);this.refunds=new Refunds(store,providers);this.files=files;
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
  private async categories(country:string):Promise<RecordData[]>{return (await this.store.all('category',country)).filter(r=>r.status==='effective').map((r):RecordData=>({...r,record_id:r.id,id:categoryId(r)}));}
  private categorySnapshot(category:RecordData,locale='ru'){return {id:category.id,version_id:category.record_id??category.id,title:category.payload.labels?.[locale]??category.payload.labels?.ru??category.title,labels:category.payload.labels,schema:category.payload.schema??{properties:{},required:[]}};}
  private async entitlement(a: Actor, capability: string, verified=false, consume=true) {
    if(['publish_order','select_offer','send_offer','publish_profile'].includes(capability)) {
      const control=(await this.store.all('country_control',a.country)).find(r=>r.status==='effective');
      if(control?.payload.stop_new_business)fail(503,'COUNTRY_BUSINESS_PAUSED','Новые действия в этой стране временно приостановлены. Чат, завершение заказов и поддержка доступны.');
    }
    if(a.user.status!=='active')fail(403,'FORBIDDEN','Новые действия ограничены. Поддержка доступна.');
    if(verified&&!a.user.roles.includes('executor'))fail(403,'EXECUTOR_ROLE_REQUIRED','Настройте роль исполнителя');
    if(verified&&a.user.verification!=='passed')fail(403,'VERIFICATION_REQUIRED','Требуется проверка документа исполнителя');
    if(['publish_order','select_offer','send_offer','publish_profile'].includes(capability)) {
      const current=currentLegalDocuments(await this.store.all('legal_document',a.country),a.country,a.user.locale??'ru').filter(d=>['privacy','privacy_policy','terms','terms_of_use'].includes(d.type));
      const checked=new Set<string>();
      for(const document of current) {
        const type=['privacy','privacy_policy'].includes(document.type)?'privacy':'terms';if(checked.has(type))continue;checked.add(type);
        const consent=(await this.store.db.query<any>("SELECT data FROM records WHERE kind='consent' AND country=$1 AND owner=$2 AND data->>'document_id'=$3 ORDER BY (data->>'sequence')::integer DESC LIMIT 1",[a.country,a.id,document.id])).rows[0]?.data;
        if(!consent?.accepted||consent.document_hash!==document.hash||document.minimum_age===18&&consent.age_confirmed!==true)fail(403,'CONSENT_REQUIRED','Примите текущую версию условий и политики конфиденциальности',{document_id:document.id});
      }
    }
    if(capability==='send_offer'){const profile=(await this.store.all('contractor',a.country)).find(r=>r.owner===a.id);if(profile?.status==='paused'||profile?.availability==='paused')fail(403,'FORBIDDEN','Приём новых предложений приостановлен');}
    // Customer actions are free even when the same account also has an executor role.
    if(['publish_order','select_offer'].includes(capability)||capability==='search_full'&&!verified&&a.user.active_role!=='executor')return;
    await this.promotionGrant(a);
    const grants=(await this.store.select('grant',a.country,{owner:a.id,limit:1000})).filter(r=>r.owner===a.id && r.valid_until>new Date().toISOString() && r.capabilities.includes(capability)&&(r.balance===undefined||r.balance>0));
    if(!grants.length)fail(403,'ENTITLEMENT_REQUIRED','Нужен действующий доступ',{capability});
    const selected=grants.find(g=>g.balance===undefined)??grants[0];
    if(consume&&selected.balance!==undefined&&['publish_order','send_offer','select_offer','publish_profile'].includes(capability)) {
      await this.store.put({...selected,balance:selected.balance-1,version:selected.version+1});
      await this.store.put(this.record('entitlement_consumption',a,{grant_id:selected.id,capability,consumed_at:new Date().toISOString()}));
    }
  }
  private async staff(a: Actor, permission: string) {
    const has=a.user.staff_permissions?.includes(permission)||(!['identity_view','verification_reviewer','bulk_restrict'].includes(permission)&&a.user.staff_permissions?.includes('administrator'));
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
    if(path==='/public/config'&&method==='GET') {
      const controls=await this.store.all('country_control');
      return {countries:Object.entries(countries).map(([code,c])=>{
        const control=controls.find(r=>r.country===code&&r.status==='effective');
        return {code,name:({KZ:'Казахстан',KG:'Кыргызстан',RU:'Россия',BY:'Беларусь'} as Record<string,string>)[code],...c,launch_status:'unverified',checkout_enabled:false,
          active:countryEnabled(code)&&(control?.payload.registration_enabled??true)&&!(control?.payload.stop_new_business??false),registration_enabled:countryEnabled(code)&&(control?.payload.registration_enabled??true),stop_new_business:!countryEnabled(code)||(control?.payload.stop_new_business??false)};
      }),subscription_enabled:true,subscription_scope:'executor',customer_access:'free',banner_ads_enabled:false,rewarded_access_enabled:false,minimum_supported_version:'0.1.0',mode:'development',server_time:new Date().toISOString()};
    }
    if(path==='/legal/documents'&&method==='GET') {
      if(!countries[q.country??'KZ']||q.locale&&!['ru','kk','sr','be'].includes(q.locale))fail(400,'VALIDATION_ERROR','Проверьте страну и язык');
      const versions=(await this.store.all('legal_document',q.country??'KZ')).filter(x=>x.status==='published'&&(!q.locale||x.locale===q.locale)).sort((a,b)=>String(b.published_at??b.created_at).localeCompare(String(a.published_at??a.created_at))||b.id.localeCompare(a.id));
      const seen=new Set<string>(),visible=q.required==='true'?currentLegalDocuments(await this.store.all('legal_document',q.country??'KZ'),q.country??'KZ',q.locale??'ru'):q.all_versions==='true'?versions:versions.filter(d=>{const key=d.type+':'+d.locale;if(seen.has(key))return false;seen.add(key);return true;});
      return {items:visible.map(({id,country,type,locale,content,hash,version,created_at,published_at,minimum_age})=>({id,country,type,locale,content,hash,version,created_at,published_at,minimum_age}))};
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
      if(!countryEnabled(country))fail(403,'COUNTRY_DISABLED','Выбран неверный региональный endpoint');
      const control=(await this.store.all('country_control',country)).find(r=>r.status==='effective');
      if(control?.payload.registration_enabled===false)fail(503,'COUNTRY_DISABLED','Регистрация в этой стране временно приостановлена');
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
      if(!countryEnabled(b.country))fail(401,'INVALID_CREDENTIALS','Неверный номер или пароль');
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
    if(path==='/me/overview'&&method==='GET')return accountOverview(this.store,a.id,a.country);
    if(path==='/me/restrictions'&&method==='GET'){
      const now=new Date().toISOString();
      const rows=await db.query<{data:RecordData}>("SELECT data FROM records WHERE kind=ANY($1::text[]) AND country=$2 AND data->>'user_id'=$3 AND data->>'status'='active' AND (COALESCE(data->>'ends_at',data->>'expires_at') IS NULL OR COALESCE(data->>'ends_at',data->>'expires_at')>$4) ORDER BY data->>'created_at' DESC,id DESC",[['blacklist','auto_hold'],a.country,a.id,now]);
      const restrictions=[];
      for(const {data:r} of rows.rows){
        let incident=r.case_id?await this.store.get(r.case_id):undefined;
        if(incident?.reporter_private&&incident.owner!==a.id)incident=(await db.query<{data:RecordData}>("SELECT data FROM records WHERE kind='case' AND country=$1 AND owner=$2 AND data->>'source_private_case_id'=$3 ORDER BY data->>'created_at' DESC,id DESC LIMIT 1",[a.country,a.id,incident.id])).rows[0]?.data;
        const visible=incident?.kind==='case'&&incident.country===a.country&&(incident.owner===a.id||!incident.reporter_private&&incident.subject_user_id===a.id)?incident:undefined;
        const appeal=visible?.subject_user_id===a.id&&(visible.status==='restricted'||visible.status==='resolved'&&['content_removed','sanction_upheld'].includes(visible.decision));
        restrictions.push({id:r.id,type:r.kind==='auto_hold'?'automatic_review':'new_business',ends_at:r.ends_at??r.expires_at??null,reason:visible&&(visible.public_reason||visible.source_private_case_id)?visible.public_reason??visible.description:'Проверка содержания',...(visible?{case_id:visible.id,case_status:visible.status,can_appeal:!!appeal}:{can_appeal:false})});
      }
      return {items:restrictions,meta:{account_status:a.user.status,restricted:a.user.status!=='active',server_time:now}};
    }

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
    if(path==='/me/sessions'&&method==='GET')return {items:(await db.query('SELECT DISTINCT family,expires_at FROM tokens WHERE user_id=$1 AND kind=\'refresh\' AND country=$2 AND expires_at>now() AND NOT revoked AND NOT used ORDER BY expires_at DESC',[a.id,a.country])).rows.map(r=>({...r,current:r.family===a.family}))};
    const revokeSession=path.match(/^\/me\/sessions\/([^/]+)$/);
    if(revokeSession&&method==='DELETE'){
      if(!/^[0-9a-f]{8}-[0-9a-f]{4}-[1-8][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i.test(revokeSession[1]))fail(400,'VALIDATION_ERROR','Проверьте ID сессии');
      const updated=await db.query('UPDATE tokens SET revoked=true WHERE user_id=$1 AND country=$2 AND family=$3 RETURNING family',[a.id,a.country,revokeSession[1]]);
      if(!updated.rows.length)fail(404,'NOT_FOUND','Сессия не найдена');
      await this.store.put(this.record('security_event',a,{event:'session.revoked',session_family:revokeSession[1],ip,occurred_at:new Date().toISOString()}));return {revoked:true};
    }
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
    if(path==='/catalog/categories'&&method==='GET')return {items:(await this.categories(a.country)).map(x=>({id:x.id,name:x.payload.labels?.[q.locale??a.user.locale??'ru']??x.payload.labels?.ru??x.title,labels:x.payload.labels,schema:x.payload.schema??{properties:{},required:[]},parent_id:x.payload.parent_id??null,icon:x.payload.icon??'briefcase',version_id:x.record_id,version:x.version}))};
    if(path==='/contractors/map'&&method==='GET'){
      await this.entitlement(a,'search_full');const near=q.near_lat!==undefined||q.near_lon!==undefined?{latitude:Number(q.near_lat),longitude:Number(q.near_lon),radius:Number(q.radius_km??50)}:undefined;if(near&&(!Number.isFinite(near.latitude)||Math.abs(near.latitude)>90||!Number.isFinite(near.longitude)||Math.abs(near.longitude)>180||!Number.isFinite(near.radius)||near.radius<=0||near.radius>500))fail(400,'VALIDATION_ERROR','Проверьте координаты и радиус');const candidates=await this.store.select('contractor',a.country,{publicActor:a.id,statuses:['published'],city:near?undefined:q.city,category:q.category_id,near,limit:100});
      const rows=candidates.filter(r=>r.public_location&&Number.isFinite(r.public_location.latitude)&&Number.isFinite(r.public_location.longitude));
      return {items:await contractorPresentation(this.store,a.country,rows),meta:{approximate:true,map_provider_configured:false}};
    }
    if(path==='/geo/cities'&&method==='GET')return {items:countries[a.country].cities.filter(c=>!q.q||c.toLowerCase().includes(String(q.q).toLowerCase())).map(name=>({id:referenceId(`joba:city:${a.country}:${name}`),name,country:a.country}))};
    if(path==='/me/monetization-config'&&method==='GET') {
      const config=(await this.store.all('monetization_config',a.country)).find(x=>x.status==='effective');
      const usage=(await db.query<{used:string;last:string|null}>("SELECT count(*) AS used,max(data->>'created_at') AS last FROM records WHERE kind='ad_session' AND country=$1 AND owner=$2 AND left(data->>'created_at',10)=$3",[a.country,a.id,new Date().toISOString().slice(0,10)])).rows[0];
      const usedToday=Number(usage.used),dailyCap=config?.payload.daily_cap??5;
      const last=usage.last?Date.parse(usage.last):0;
      const cooldownUntil=last?new Date(last+(config?.payload.cooldown_seconds??300)*1000).toISOString():null;
      return {banner_ads_enabled:false,rewarded_access_enabled:false,...config?.payload,reward_provider_ready:this.providers.rewards.has(config?.payload.provider),reward_usage:{used_today:usedToday,daily_cap:dailyCap,remaining_today:Math.max(0,dailyCap-usedToday),cooldown_until:cooldownUntil},version:config?.version??1,effective_at:config?.published_at??null,expires_at:new Date(Date.now()+settings.config_ttl_seconds*1000).toISOString(),server_time:new Date().toISOString(),checkout_enabled:false,subscription_enabled:a.user.active_role==='executor'&&config?.payload.subscription_enabled!==false,subscription_scope:'executor',country_gate:'unverified',offers:a.user.active_role==='executor'&&config?.payload.subscription_enabled!==false?(await this.commerce.offers(a.country)).items:[]};
    }
    if(path==='/me/entitlements'&&method==='GET'){await this.promotionGrant(a);return {items:(await this.store.all('grant',a.country)).filter(x=>x.owner===a.id)};}
    if(path==='/me/verification'&&method==='GET') {
      const policy=(await this.store.all('verification_policy',a.country)).filter(x=>x.status==='effective').sort((x,y)=>String(y.published_at??y.created_at).localeCompare(String(x.published_at??x.created_at))||y.id.localeCompare(x.id))[0];
      const consent=policy?(await this.store.all('consent',a.country)).filter(x=>x.owner===a.id&&x.document_id===policy!.payload.document_id).sort((x,y)=>(y.sequence??0)-(x.sequence??0)||y.created_at.localeCompare(x.created_at))[0]:null;
      const document=policy?await this.store.get(policy!.payload.document_id):null;
      return {status:a.user.verification,policy:policy&&document?.kind==='legal_document'&&document.country===a.country&&document.status==='published'?{id:policy.id,version:policy.version,document_types:policy.payload.document_types,required_pages:policy.payload.required_pages??{},document_id:policy.payload.document_id,consent_accepted:consent?.accepted===true&&consent.document_hash===document.hash}:null,items:(await this.store.all('verification',a.country)).filter(x=>x.owner===a.id).map(({document_refs,reviewer_id,...r})=>r)};
    }
    if(path==='/me/verification-sessions'&&method==='POST') {
      const policy=(await this.store.all('verification_policy',a.country)).filter(x=>x.status==='effective').sort((x,y)=>String(y.published_at??y.created_at).localeCompare(String(x.published_at??x.created_at))||y.id.localeCompare(x.id))[0];
      if(!policy)fail(503,'COUNTRY_FLOW_UNAPPROVED','Типы документов и основание проверки для страны не утверждены');
      const consent=(await this.store.all('consent',a.country)).filter(x=>x.owner===a.id&&x.document_id===policy!.payload.document_id).sort((x,y)=>(y.sequence??0)-(x.sequence??0)||y.created_at.localeCompare(x.created_at))[0];
      const document=await this.store.get(policy!.payload.document_id);
      if(!document||document.kind!=='legal_document'||document.country!==a.country||document.status!=='published')fail(503,'COUNTRY_FLOW_UNAPPROVED','Правовое основание проверки недоступно');
      if(!consent?.accepted||consent.document_hash!==document!.hash)fail(403,'CONSENT_REQUIRED','Требуется согласие на проверку документа');
      if(!policy!.payload.document_types.includes(b.document_type))fail(400,'VALIDATION_ERROR','Тип документа не разрешён');
      return this.store.put(this.record('verification',a,{status:'draft',document_type:b.document_type,policy_id:policy!.id,policy_version:policy!.version,document_revision:1,required_pages:policy!.payload.required_pages?.[b.document_type]??['Документ'],document_refs:[]}));
    }
    const verificationSubmit=path.match(/^\/me\/verification-sessions\/([^/]+)\/submit$/);
    if(verificationSubmit&&method==='POST') {
      const r=await this.object(verificationSubmit[1],a,'verification',true);this.version(r,b);
      if(!['draft','rejected'].includes(r.status))fail(409,'STATE_CONFLICT','Заявка уже отправлена');
      const policy=await this.store.get(r.policy_id);
      if(!policy||policy.country!==a.country||policy.status!=='effective'||policy.version!==r.policy_version)fail(409,'POLICY_CHANGED','Правила проверки изменились. Создайте новую заявку.');
      const document=await this.store.get(policy!.payload.document_id);
      const consent=(await this.store.all('consent',a.country)).filter(x=>x.owner===a.id&&x.document_id===policy!.payload.document_id).sort((x,y)=>(y.sequence??0)-(x.sequence??0)||y.created_at.localeCompare(x.created_at))[0];
      if(!document||document.country!==a.country||document.status!=='published'||!consent?.accepted||consent.document_hash!==document.hash)fail(403,'CONSENT_REQUIRED','Требуется актуальное согласие на проверку документа');
      const uploads=await this.safeUploads(a,b.upload_ids,'identity');if(uploads.length!==(r.required_pages??['Документ']).length)fail(400,'VALIDATION_ERROR','Загрузите все утверждённые стороны или страницы документа');
      for(const id of uploads){const upload=await this.store.get(id);if(upload?.verification_id!==r.id)fail(422,'POLICY_REJECTED','Документ загружен для другой заявки');}
      await this.store.put({...a.user,verification:'pending_review',version:a.user.version+1});
      return this.store.put({...r,status:'pending_review',document_refs:uploads,document_revision:r.document_revision+1,version:r.version+1});
    }
    if(path==='/me/consents'&&method==='POST') {
      const d=await this.object(String(b.document_id),a,'legal_document');
      if(d.status!=='published'||b.document_hash!==d.hash)fail(409,'LEGAL_VERSION_CHANGED','Версия документа изменилась');
      if(typeof b.accepted!=='boolean')fail(400,'VALIDATION_ERROR','Требуется явное согласие');
      if(b.age_confirmed!==undefined&&typeof b.age_confirmed!=='boolean')fail(400,'VALIDATION_ERROR','Проверьте возрастное подтверждение');
      if(b.accepted===true&&d.minimum_age===18&&b.age_confirmed!==true)fail(422,'AGE_CONFIRMATION_REQUIRED','Подтвердите возрастной допуск');
      if(b.age_confirmed===true&&!['terms','terms_of_use'].includes(d.type))fail(400,'VALIDATION_ERROR','Возрастное подтверждение связано с пользовательским соглашением');
      const count=(await db.query<any>("SELECT COALESCE(MAX((data->>'sequence')::integer),0) AS max FROM records WHERE kind='consent' AND owner=$1 AND country=$2",[a.id,a.country])).rows[0].max;
      return this.store.put(this.record('consent',a,{document_id:d.id,document_version:d.version,document_hash:d.hash,accepted:b.accepted,...(b.age_confirmed!==undefined?{age_confirmed:b.age_confirmed,age_declaration:'18_or_older'}:{}),sequence:Number(count)+1}));
    }
    if(path==='/me/legal-holds'&&method==='GET'){const page=await this.page('legal_hold',a,q,{subjectUser:a.id});return {...page,items:page.items.map(r=>({id:r.id,status:r.status,fields:r.fields,basis:r.basis,review_at:r.review_at,created_at:r.created_at}))};}
    if(path==='/me/consents'&&method==='GET')return {items:(await this.store.all('consent',a.country)).filter(x=>x.owner===a.id).sort((x,y)=>(y.sequence??0)-(x.sequence??0))};
    if(path==='/me/contractor-profile'&&method==='GET'){const profile=(await db.query<{data:RecordData}>("SELECT data FROM records WHERE kind='contractor' AND country=$1 AND owner=$2 LIMIT 1",[a.country,a.id])).rows[0]?.data;return {profile:profile?{...editableContent(profile),public_visible:profile.status==='published'&&!['hidden','quarantined','rejected'].includes(profile.moderation_status)&&a.user.status==='active'&&a.user.verification==='passed'}:null};}
    if(path==='/me/contractor-profile/public-location'&&method==='PATCH'){
      const p=(await this.store.select('contractor',a.country,{owner:a.id,limit:1}))[0];if(!p)fail(404,'NOT_FOUND','Профиль не найден');this.version(p,b);
      if(typeof b.enabled!=='boolean')fail(400,'VALIDATION_ERROR','Подтвердите видимость зоны');
      if(!b.enabled)return this.store.put({...p,public_location:null,...(p.draft?{draft:{...p.draft,public_location:null}}:{}),version:p.version+1});
      const lat=b.location?.latitude,lon=b.location?.longitude;
      if(!Number.isFinite(lat)||Math.abs(lat)>90||!Number.isFinite(lon)||Math.abs(lon)>180)fail(400,'VALIDATION_ERROR','Проверьте зону обслуживания');
      const staged=editContent(p,{public_location:{latitude:Math.round(lat*100)/100,longitude:Math.round(lon*100)/100,approximate:true}});return this.store.put(staged);
    }
    if(path==='/me/contractor-profile'&&method==='PUT') {
      const old=(await this.store.all('contractor',a.country)).find(x=>x.owner===a.id);if(old)this.version(old,b);
      const title=text(b,'title',5,100),description=text(b,'description',20,3000),city=text(b,'city',2,100);
      const categories=(await this.categories(a.country));
      const category=categories.find(c=>c.id===b.category_id||c.legacy_id===b.category_id);if(!category)fail(400,'VALIDATION_ERROR','Категория недоступна');
      let fields:any;try{fields=profileFields({...b,category_id:category!.id},old?editableContent(old):old,countries[a.country].currency,new Set(categories.map(c=>c.id)));}catch(e:any){fail(400,'VALIDATION_ERROR','Проверьте поле '+e.message,{field:e.message});}
      const uploads=b.gallery_ids===undefined?(old?editableContent(old).gallery_ids??[]:[]):await this.safeUploads(a,b.gallery_ids,'portfolio',20);
      if(uploads.length>20)fail(400,'VALIDATION_ERROR','Не более 20 фотографий');
      if(!a.user.roles.includes('executor'))await this.store.put({...a.user,roles:[...a.user.roles,'executor'],version:a.user.version+1});
      let publicLocation=old?editableContent(old).public_location:undefined;
      if(b.public_location!==undefined){if(b.public_location===null)publicLocation=null;else{const lat=b.public_location.latitude,lon=b.public_location.longitude;if(!Number.isFinite(lat)||Math.abs(lat)>90||!Number.isFinite(lon)||Math.abs(lon)>180)fail(400,'VALIDATION_ERROR','Проверьте зону обслуживания');publicLocation={latitude:Math.round(lat*100)/100,longitude:Math.round(lon*100)/100,approximate:true};}}
      const changes={...fields,title,description,city,gallery_ids:uploads,public_location:publicLocation};const staged=old?editContent(old,changes):{...this.record('contractor',a),...changes,status:'draft'};
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
      const category=(await this.categories(a.country)).find(c=>(c.id===b.category_id||c.legacy_id===b.category_id)&&c.status==='effective');if(!category)fail(400,'VALIDATION_ERROR','Категория недоступна');
      let orderId:string|null=null;if(b.order_id){const order=await this.object(String(b.order_id),a,'order');if(order.status!=='completed'||order.executor_id!==a.id)fail(422,'POLICY_REJECTED','Можно связать только заказ, выполненный вами');orderId=order.id;}
      return this.store.put(this.record('portfolio',a,{title:text(b,'title',5,120),description:text(b,'description',0,3000),category_id:category!.id,order_id:orderId,rights_confirmed:b.rights_confirmed===true,status:'draft',position:projects.length,photos:[]}));
    }
    const portfolio=path.match(/^\/me\/portfolio-projects\/([^/]+)(?:\/(submit))?$/);
    if(portfolio) {
      const stored=await this.object(portfolio[1],a,'portfolio',true),p=editableContent(stored);if(method==='GET'){const order=p.order_id?await this.store.get(p.order_id):undefined;const category=p.category_id?await this.store.get(p.category_id):undefined;const profile=(await db.query<{data:RecordData}>("SELECT data FROM records WHERE kind='contractor' AND country=$1 AND owner=$2 LIMIT 1",[a.country,a.id])).rows[0]?.data;const publicVisible=stored.status==='published'&&!['hidden','quarantined','rejected'].includes(stored.moderation_status)&&profile?.status==='published'&&!['hidden','quarantined','rejected'].includes(profile.moderation_status)&&a.user.status==='active'&&a.user.verification==='passed';return {...p,public_visible:publicVisible,category_name:category?.kind==='category'&&category.country===a.country?category.name:undefined,linked_completed_order:order?.kind==='order'&&order.country===a.country&&order.status==='completed'&&order.executor_id===a.id};}this.version(stored,b);
      if(method==='DELETE')return this.store.put({...stored,draft:undefined,status:'archived',version:stored.version+1});
      if(method==='PATCH') {
        const photos=b.upload_ids?await this.safeUploads(a,b.upload_ids,'portfolio'):p.photos;
        if(photos.length>settings.portfolio_photos)fail(422,'LIMIT_EXCEEDED','Превышен лимит фотографий');
        if(b.cover_id&&!photos.includes(b.cover_id))fail(400,'VALIDATION_ERROR','Обложка должна быть фотографией проекта');
        const category=(await this.categories(a.country)).find(c=>(c.id===(b.category_id??p.category_id)||c.legacy_id===(b.category_id??p.category_id))&&c.status==='effective');if(!category)fail(400,'VALIDATION_ERROR','Категория недоступна');
        const cover=b.cover_id??(photos.includes(p.cover_id)?p.cover_id:photos[0]),extra:any={};
        if(b.rights_confirmed!==undefined){if(typeof b.rights_confirmed!=='boolean')fail(400,'VALIDATION_ERROR','Подтвердите права на материалы');extra.rights_confirmed=b.rights_confirmed;}
        if(b.order_id!==undefined){if(b.order_id===null)extra.order_id=null;else{const order=await this.object(String(b.order_id),a,'order');if(order.status!=='completed'||order.executor_id!==a.id)fail(422,'POLICY_REJECTED','Можно связать только заказ, выполненный вами');extra.order_id=order.id;}}
        return this.store.put(editContent(stored,{...extra,title:b.title===undefined?p.title:text(b,'title',5,120),description:b.description===undefined?p.description:text(b,'description',0,3000),category_id:category!.id,photos,cover_id:cover})).then(editableContent);
      }
      if(portfolio[2]==='submit'){await this.entitlement(a,'publish_profile',true);if(!p.photos.length||p.rights_confirmed!==true)fail(422,'POLICY_REJECTED','Нужна проверенная фотография и подтверждение прав на материалы');if(!['draft','rejected'].includes(p.status))fail(409,'STATE_CONFLICT','Нет черновика для проверки');return this.store.put(submitContent(stored)).then(editableContent);}
    }
    if(path==='/contractors'&&method==='GET'){await this.entitlement(a,'search_full');return this.page('contractor',a,q,{statuses:['published'],publicActor:a.id});}
    const contractor=path.match(/^\/contractors\/([^/]+)(?:\/(portfolio)(?:\/([^/]+))?)?$/);
    if(contractor&&method==='GET'){
      await this.entitlement(a,'search_full');const p=await this.object(contractor[1],a,'contractor'),owner=await this.store.get(p.owner);
      if(owner?.country!==a.country||owner.status!=='active'||owner.verification!=='passed'||p.status!=='published'||['quarantined','hidden','rejected'].includes(p.moderation_status)||await this.blocked(a,p.owner))fail(404,'NOT_FOUND','Профиль не найден');
      if(!contractor[2])return (await contractorPresentation(this.store,a.country,[p]))[0];
      const candidate=contractor[3]?await this.store.get(contractor[3]):undefined;
      if(contractor[3]&&(!candidate||candidate.kind!=='portfolio'||candidate.country!==a.country||candidate.owner!==p.owner||candidate.status!=='published'||['quarantined','hidden','rejected'].includes(candidate.moderation_status)))fail(404,'NOT_FOUND','Проект недоступен');
      const projects=contractor[3]?[candidate!]:(await this.store.db.query<{data:RecordData}>("SELECT data FROM records WHERE kind='portfolio' AND country=$1 AND owner=$2 AND data->>'status'='published' AND COALESCE(data->>'moderation_status','') NOT IN ('quarantined','hidden','rejected')",[a.country,p.owner])).rows.map(row=>row.data);

      const page=contractor[3]?undefined:await this.portfolioPage(projects,q);
      const visible:RecordData[]=await Promise.all((page?.items??projects).map(async project=>{
        const order=project.order_id?await this.store.get(project.order_id):undefined;
        const linked=order?.kind==='order'&&order.country===a.country&&order.status==='completed'&&order.executor_id===project.owner;
        return {...publicContent(project),order_id:undefined,linked_completed_order:linked,source:linked?'joba_completed':'self_reported'};
      }));if(contractor[3]){const category=visible[0].category_id?await this.store.get(visible[0].category_id):undefined;return {...visible[0],category_name:category?.kind==='category'&&category.country===a.country?category.name:undefined,contractor_id:p.id,contractor_name:owner!.display_name,contractor_avatar_id:owner!.avatar_id};}return {...page!,items:visible};
    }
    const publicCustomer=path.match(/^\/customers\/([^/]+)$/);
    if(publicCustomer&&method==='GET') {
      await this.entitlement(a,'search_full');const u=await this.object(publicCustomer[1],a,'user');if(u.status!=='active'||u.staff_permissions?.length||await this.blocked(a,u.id))fail(404,'NOT_FOUND','Профиль недоступен');
      const reviews=(await this.store.all('review',a.country)).filter(r=>r.target_id===u.id&&r.status==='published'&&r.moderation_status!=='quarantined');
      return {...safeUser(u),city_source:'self_reported',completed_orders:(await this.store.all('order',a.country)).filter(o=>o.owner===u.id&&o.status==='completed').length,rating:{count:reviews.length,average:reviews.length?reviews.reduce((sum,r)=>sum+r.rating,0)/reviews.length:null}};
    }
    const publicReviews=path.match(/^\/users\/([^/]+)\/reviews$/);
    if(publicReviews&&method==='GET'){const target=await this.object(publicReviews[1],a,'user');if(target.id!==a.id){await this.entitlement(a,'search_full');if(target.status!=='active'||target.staff_permissions?.length||await this.blocked(a,target.id))fail(404,'NOT_FOUND','Профиль недоступен');}return this.list((await this.store.all('review',a.country)).filter(r=>r.target_id===publicReviews[1]&&r.status==='published'&&!['quarantined','hidden','rejected'].includes(r.moderation_status)),q);}
    if(path==='/orders'&&method==='POST') {
      const budget=b.budget?b.budget.mode==='negotiable'?null:b.budget.amount_minor:(b.budget_amount??null);
      if(budget!==null && (!Number.isSafeInteger(budget)||budget<0))fail(400,'VALIDATION_ERROR','Бюджет должен быть целым числом в минимальных единицах валюты либо null');
      if(b.country&&b.country!==a.country||b.budget?.currency&&b.budget.currency!==countries[a.country].currency)fail(400,'VALIDATION_ERROR','Страна и валюта не совпадают с регионом');
      if(!['onsite','remote','hybrid'].includes(b.work_mode??'onsite'))fail(400,'VALIDATION_ERROR','Проверьте формат работы');
      const category=(await this.categories(a.country)).find(c=>(c.id===b.category_id||c.legacy_id===b.category_id)&&c.status==='effective');if(!category)fail(400,'VALIDATION_ERROR','Категория недоступна');
      const city=b.city??countries[a.country].cities.find(name=>referenceId(`joba:city:${a.country}:${name}`)===b.city_id);if(typeof city!=='string'||city.length<2||city.length>100)fail(400,'VALIDATION_ERROR','Город недоступен');
      const uploads=b.upload_ids?await this.safeUploads(a,b.upload_ids,'order'):[];
      return this.store.put(this.record('order',a,{title:text(b,'title',5,120),description:text(b,'description',20,5000),category_id:category!.id,category_snapshot:{id:category!.id,version_id:category!.record_id,title:category!.payload.labels?.[a.user.locale??'ru']??category!.payload.labels?.ru??category!.title,labels:category!.payload.labels,schema:category!.payload.schema??{properties:{},required:[]}},city,budget_amount:budget,currency:countries[a.country].currency,status:'draft',revision:1,upload_ids:uploads,work_mode:b.work_mode??'onsite',attributes:attributes(category!.payload.schema,b.attributes),time_window:timeWindow(b.time_window)}));
    }
    if(path==='/me/orders'&&method==='GET'){
      const page=await this.page('order',a,q,{owner:a.id,statuses:orderBucket(q.bucket)});
      const hasAny=(await this.store.db.query<{exists:boolean}>("SELECT EXISTS(SELECT 1 FROM records WHERE kind='order' AND country=$1 AND owner=$2) AS exists",[a.country,a.id])).rows[0].exists;
      return {...page,meta:{...page.meta,has_any:hasAny}};
    }
    if(path==='/me/completed-orders'&&method==='GET'){if(q.role&&!['customer','executor'].includes(q.role))fail(400,'VALIDATION_ERROR','Проверьте роль');return this.page('order',a,q,{...(q.role==='executor'?{executor:a.id}:q.role==='customer'?{owner:a.id}:{participant:a.id}),statuses:['completed']});}
    if(path==='/me/assigned-orders'&&method==='GET')return this.page('order',a,q,{executor:a.id,statuses:orderBucket(q.bucket)});
    if(path==='/me/offers'&&method==='GET')return this.list((await this.store.all('offer',a.country)).filter(x=>x.owner===a.id).map(x=>presentOffer(x,settings.offer_expiry_hours)),q);
    if(path==='/me/order-change-requests'&&method==='GET')return this.list([...(await this.store.all('cancel_request',a.country)),...(await this.store.all('amendment',a.country))].filter(x=>x.owner===a.id||x.recipient_id===a.id),q);
    if(path==='/orders'&&method==='GET'){await this.entitlement(a,'search_full',true);return this.page('order',a,q,{statuses:['open'],publicActor:a.id});}
    const om=path.match(/^\/orders\/([^/]+)(?:\/(publish|cancel|complete|offers|select|start|extend|clone|invites|cancel-requests|amendments|request-revision|confirm-completion))?$/);
    if(om) {
      const o=await this.object(om[1],a,'order');const action=om[2];
      const participant=o.owner===a.id||o.executor_id===a.id;
      if(!participant&&(o.status!=='open'||['quarantined','hidden','rejected'].includes(o.moderation_status)||o.expires_at<=new Date().toISOString()||await this.blocked(a,o.owner)))fail(404,'NOT_FOUND','Заказ не найден');
      if(!participant)await this.entitlement(a,'search_full',true);
      if(method==='GET'&&!action){
        const customer=await this.store.get(o.owner),executor=o.executor_id?await this.store.get(o.executor_id):undefined;
        const assignment=participant&&o.assignment_id?await this.store.get(o.assignment_id):undefined;
        const review=participant?(await db.query<{data:RecordData}>("SELECT data FROM records WHERE kind='review' AND country=$1 AND owner=$2 AND data->>'order_id'=$3 LIMIT 1",[a.country,a.id,o.id])).rows[0]?.data:undefined;
        const person=(user:RecordData|undefined)=>user?{id:user.id,display_name:user.display_name,avatar_id:user.avatar_id,city:user.city}:null;
        return {...(participant?o:publicContent(o)),exact_address:participant?o.exact_address:undefined,customer:person(customer),executor:participant?person(executor):undefined,conversation_id:assignment?.conversation_id,my_review:review,offer_policy:offerPolicy(o,settings.offer_expiry_hours)};
      }
      if(method==='GET'&&action==='offers'){if(o.owner!==a.id)fail(404,'NOT_FOUND','Заказ не найден');return {items:await offerPeople(this.store,a.country,(await this.store.all('offer',a.country)).filter(x=>x.order_id===o.id).map(x=>presentOffer(x,settings.offer_expiry_hours,new Date(),o)))};}
      if(action==='offers'&&method==='POST') {
        await this.entitlement(a,'send_offer',true);if(o.owner===a.id||o.status!=='open')fail(409,'STATE_CONFLICT','Нельзя откликнуться на заказ');
        if(await this.blocked(a,o.owner))fail(404,'NOT_FOUND','Заказ недоступен');
        if(b.acknowledged_revision!==o.revision)fail(409,'REVISION_NOT_ACKNOWLEDGED','Условия заказа изменились');
        if(!Number.isSafeInteger(b.amount)||b.amount<0)fail(400,'VALIDATION_ERROR','Проверьте цену');
        const previous=(await this.store.all('offer',a.country)).filter(x=>x.order_id===o.id&&x.owner===a.id&&x.status==='active');
        if(previous.some(x=>!offerExpired(x,settings.offer_expiry_hours)))fail(409,'STATE_CONFLICT','Отклик уже отправлен');
        for(const old of previous){await this.store.put({...old,status:'expired',version:old.version+1});const chat=await this.store.get(old.conversation_id);if(chat?.status==='open')await this.store.put({...chat,status:'closed',version:chat.version+1});}

        const offer=this.record('offer',a,{order_id:o.id,text:text(b,'text',1,3000),amount:b.amount,currency:o.currency,acknowledged_revision:o.revision,acknowledged_order:offerOrderSnapshot(o),status:'active',...offerTerms(o,b,settings.offer_expiry_hours)});
        const chat=this.record('conversation',a,{order_id:o.id,offer_id:offer.id,members:[o.owner,a.id],status:'open'});offer.conversation_id=chat.id;
        await this.store.put(chat);await this.store.put(offer);await this.notify(o.owner,a,'offer.created',o.id);return offer;
      }
      if(action==='invites'&&method==='POST') {
        if(o.owner!==a.id)fail(404,'NOT_FOUND','Заказ не найден');await this.entitlement(a,'publish_order',false,false);
        await db.query('SELECT pg_advisory_xact_lock(hashtextextended($1,0))',['invites:'+a.country+':'+a.id]);
        if(o.status!=='open'||o.expires_at<=new Date().toISOString()||['quarantined','hidden','rejected'].includes(o.moderation_status))fail(409,'STATE_CONFLICT','Заказ закрыт');
        const p=await this.object(String(b.contractor_id),a,'contractor'),owner=await this.store.get(p.owner);if(owner?.status!=='active'||owner.verification!=='passed'||await this.blocked(a,p.owner)||p.owner===a.id||p.status!=='published'||p.availability==='paused')fail(422,'POLICY_REJECTED','Исполнитель недоступен');
        await this.entitlement({...a,id:owner!.id,user:owner!},'send_offer',true,false);
        const now=new Date();
        const active=(await db.query("SELECT id FROM records WHERE kind='invite' AND country=$1 AND data->>'order_id'=$2 AND data->>'recipient_id'=$3 AND data->>'status'='pending' AND (data->>'expires_at' IS NULL OR (data->>'expires_at')::timestamptz > CURRENT_TIMESTAMP) LIMIT 1",[a.country,o.id,p.owner])).rows;
        if(active.length)fail(409,'STATE_CONFLICT','Исполнителю уже отправлено приглашение');
        const midnight=new Date(now);midnight.setUTCHours(0,0,0,0);
        const daily=(await db.query<{total:string}>("SELECT count(*) AS total FROM records WHERE kind='invite' AND country=$1 AND owner=$2 AND data->>'created_at'>=$3",[a.country,a.id,midnight.toISOString()])).rows[0];
        if(Number(daily.total)>=settings.invite_daily_limit)fail(429,'RATE_LIMITED','Достигнут суточный лимит приглашений');
        const i=this.record('invite',a,{order_id:o.id,recipient_id:p.owner,status:'pending',order_revision:o.revision,message:b.message===undefined?'':text(b,'message',0,2000),expires_at:new Date(now.getTime()+settings.invite_expiry_hours*3600000).toISOString()});await this.store.put(i);await this.notify(p.owner,a,'invite.created',i.id);return i;
      }
      if(['cancel-requests','amendments'].includes(action??'')&&method==='POST') {
        if(!participant)fail(404,'NOT_FOUND','Заказ не найден');this.version(o,b);
        if(!['assigned','in_progress','completion_requested'].includes(o.status))fail(409,'STATE_CONFLICT','Изменение недоступно');
        const kind=action==='amendments'?'amendment':'cancel_request';
        if((await this.store.all(kind,a.country)).some(x=>x.order_id===o.id&&x.status==='pending'))fail(409,'STATE_CONFLICT','Уже есть ожидающий запрос');
        const data:any={order_id:o.id,recipient_id:o.owner===a.id?o.executor_id:o.owner,status:'pending',order_version:o.version,reason:text(b,'reason',5,1000),expires_at:new Date(Date.now()+settings.offer_expiry_hours*3600000).toISOString()};
        if(kind==='amendment'){if(!Number.isSafeInteger(b.amount)||b.amount<0)fail(400,'VALIDATION_ERROR','Проверьте сумму');data.amount=b.amount;data.description=text(b,'description',20,5000);if(b.time_window!==undefined)data.time_window=timeWindow(b.time_window);}
        const r=this.record(kind,a,data);await this.store.put(r);await this.notify(data.recipient_id,a,kind+'.created',r.id);return r;
      }
      if(o.owner!==a.id && !['complete','start'].includes(action??''))fail(404,'NOT_FOUND','Заказ не найден');this.version(o,b);
      if(action==='publish'&&method==='POST'){await this.entitlement(a,'publish_order');if(o.status!=='draft')fail(409,'STATE_CONFLICT','Заказ уже опубликован');const category=(await this.categories(a.country)).find(c=>c.id===o.category_id);if(!category)fail(422,'CATEGORY_UNAVAILABLE','Выберите доступную категорию');const snapshot=o.category_snapshot??this.categorySnapshot(category!,a.user.locale);attributes(snapshot.schema,o.attributes??{});return this.store.put({...o,category_snapshot:snapshot,status:'open',revision:o.revision+1,version:o.version+1,published_at:new Date().toISOString(),expires_at:new Date(Date.now()+settings.order_expiry_days*86400000).toISOString()});}
      if(action==='extend'&&method==='POST'){await this.entitlement(a,'publish_order');const expires=Date.parse(String(b.expires_at));if(o.status!=='open'||Date.parse(o.expires_at)<=Date.now()||!Number.isFinite(expires)||expires<=Date.now()||expires>Date.now()+settings.order_expiry_max_days*86400000)fail(409,'STATE_CONFLICT','Недопустимый срок продления');return this.store.put({...o,expires_at:new Date(expires).toISOString(),version:o.version+1});}
      if(action==='clone'&&method==='POST'){await this.entitlement(a,'publish_order');const category=(await this.categories(a.country)).find(c=>c.id===o.category_id);if(!category)fail(422,'CATEGORY_UNAVAILABLE','Выберите доступную категорию');return this.store.put(this.record('order',a,{title:o.title,description:o.description,category_id:o.category_id,category_snapshot:this.categorySnapshot(category!,a.user.locale),attributes:o.attributes??{},work_mode:o.work_mode??'onsite',time_window:o.time_window,city:o.city,budget_amount:o.budget_amount,currency:o.currency,status:'draft',revision:1,upload_ids:[]}));}
      if(method==='PATCH'&&!action) {
        if(!['draft','open'].includes(o.status))fail(409,'STATE_CONFLICT','Редактирование недоступно');
        const unchangedCategory=b.category_id===undefined||b.category_id===o.category_id,originalCategory=unchangedCategory?await this.store.get(o.category_id):undefined;const category=(await this.categories(a.country)).find(c=>c.id===(b.category_id??o.category_id))??(unchangedCategory&&originalCategory?.country===a.country&&originalCategory.kind==='category'?{...originalCategory,id:categoryId(originalCategory),record_id:originalCategory.id}:undefined);if(!category)fail(400,'VALIDATION_ERROR','Категория недоступна');const snapshot=unchangedCategory?(o.category_snapshot??{id:category!.id,version_id:originalCategory?.id??category!.record_id,title:originalCategory?.payload.labels?.ru??originalCategory?.title??category!.title,labels:originalCategory?.payload.labels??category!.payload.labels,schema:originalCategory?.payload.schema??category!.payload.schema??{properties:{},required:[]}}):{id:category!.id,version_id:category!.record_id,title:category!.payload.labels?.[a.user.locale??'ru']??category!.payload.labels?.ru??category!.title,labels:category!.payload.labels,schema:category!.payload.schema??{properties:{},required:[]}};
        const changes:any={title:b.title===undefined?o.title:text(b,'title',5,120),description:b.description===undefined?o.description:text(b,'description',20,5000),category_id:category!.id,category_snapshot:snapshot,attributes:attributes(snapshot.schema,b.attributes??o.attributes)};
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
        if(offerExpired(offer,settings.offer_expiry_hours))fail(409,'OFFER_EXPIRED','Срок отклика истёк. Попросите исполнителя отправить новый.');
        const executor=await this.store.get(offer.owner);if(!executor||executor.verification!=='passed'||executor.status!=='active')fail(409,'STATE_CONFLICT','Исполнитель больше недоступен');
        for(const x of (await this.store.all('offer',a.country)).filter(x=>x.order_id===o.id&&x.status==='active')) {
          await this.store.put({...x,status:x.id===offer.id?'selected':offerExpired(x,settings.offer_expiry_hours)?'expired':'not_selected',version:x.version+1});
          const c=await this.store.get(x.conversation_id);if(c)await this.store.put({...c,status:x.id===offer.id?'working':'closed',version:c.version+1});
        }
        const assignment=this.record('assignment',a,{order_id:o.id,customer_id:a.id,executor_id:offer.owner,conversation_id:offer.conversation_id,order_snapshot:o,offer_snapshot:offer,status:'active'});await this.store.put(assignment);
        const updated={...o,status:'assigned',assignment_id:assignment.id,executor_id:offer.owner,selected_offer_id:offer.id,agreed_amount:offer.amount,agreed_start_at:offer.proposed_start_at,agreed_start_local:offer.proposed_start_local,agreed_duration_minutes:offer.duration_minutes,agreed_time_zone:offer.time_zone,version:o.version+1};await this.store.put(updated);await this.notify(offer.owner,a,'order.selected',o.id);return updated;
      }
      if(action==='start'&&method==='POST'){if(o.executor_id!==a.id||o.status!=='assigned')fail(409,'STATE_CONFLICT','Начало работы недоступно');return this.store.put({...o,status:'in_progress',started_at:new Date().toISOString(),version:o.version+1});}
      if(action==='complete'&&method==='POST'){
        if(o.executor_id!==a.id||o.status!=='in_progress')fail(409,'STATE_CONFLICT','Завершение недоступно');
        const completion_note=b.note===undefined||b.note===''?'':text(b,'note',1,3000);
        const completion_upload_ids=b.upload_ids===undefined?[]:await this.safeUploads(a,b.upload_ids,'order',8);
        const result=await this.store.put({...o,status:'completion_requested',completion_note,completion_upload_ids,completion_requested_at:new Date().toISOString(),version:o.version+1});
        await this.notify(o.owner,a,'order.completion_requested',o.id);return result;
      }
      if(action==='confirm-completion'&&method==='POST'){if(o.status!=='completion_requested')fail(409,'STATE_CONFLICT','Исполнитель не запросил завершение');const result=await this.store.put({...o,status:'completed',completed_at:new Date().toISOString(),version:o.version+1});await this.growth.qualify(o.owner,a.country,'completed_order',o.id);await this.growth.qualify(o.executor_id,a.country,'completed_order',o.id);return result;}
      if(action==='request-revision'&&method==='POST'){if(o.status!=='completion_requested')fail(409,'STATE_CONFLICT','Доработка недоступна');return this.store.put({...o,status:'in_progress',revision_reason:text(b,'reason',5,1000),revision_upload_ids:b.upload_ids?await this.safeUploads(a,b.upload_ids,'order'):[],revision_time_window:b.time_window===undefined?undefined:timeWindow(b.time_window),version:o.version+1});}
      if(action==='cancel'&&method==='POST'){if(!['draft','open'].includes(o.status))fail(409,'STATE_CONFLICT','Активный заказ требует разрешения через поддержку');return this.store.put({...o,status:'cancelled',cancelled_at:new Date().toISOString(),reason:text(b,'reason',5,1000),version:o.version+1});}
    }
    const responseCommand=path.match(/^\/(cancel-requests|amendments)\/([^/]+)\/respond$/);
    if(responseCommand&&method==='POST') {
      const kind=responseCommand[1]==='amendments'?'amendment':'cancel_request',r=await this.object(responseCommand[2],a,kind);
      if(r.recipient_id!==a.id)fail(404,'NOT_FOUND','Запрос не найден');this.version(r,b);
      if(r.status!=='pending'||r.expires_at<=new Date().toISOString())fail(409,'STATE_CONFLICT','Запрос больше не действует');
      if(!['accept','reject'].includes(b.decision))fail(400,'VALIDATION_ERROR','Выберите accept или reject');
      const o=await this.object(r.order_id,a,'order');if(o.version!==r.order_version)fail(409,'STATE_CONFLICT','Заказ изменился');
      if(b.decision==='accept')await this.store.put({...o,...(kind==='amendment'?{agreed_amount:r.amount,description:r.description,...(r.time_window?{time_window:r.time_window}:{}),revision:o.revision+1}:{status:'cancelled',cancelled_at:new Date().toISOString()}),version:o.version+1});
      const result=await this.store.put({...r,status:b.decision==='accept'?'accepted':'rejected',version:r.version+1});await this.notify(r.owner,a,kind+'.'+result.status,r.id);return result;
    }
    const offerCommand=path.match(/^\/offers\/([^/]+)(?:\/(acknowledge|withdraw))?$/);
    if(offerCommand) {
      if(method==='GET'&&!offerCommand[2]) {
        const offer=await this.object(offerCommand[1],a,'offer'),order=await this.object(offer.order_id,a,'order');
        if(offer.owner!==a.id&&order.owner!==a.id)fail(404,'NOT_FOUND','Отклик не найден');
        return {...presentOffer(offer,settings.offer_expiry_hours,new Date(),order),order:{...order,offer_policy:offerPolicy(order,settings.offer_expiry_hours),exact_address:order.owner===a.id||order.executor_id===a.id?order.exact_address:undefined},executor:(await offerPeople(this.store,a.country,[offer]))[0].executor};
      }
      const f=await this.object(offerCommand[1],a,'offer',true);this.version(f,b);
      if(f.status!=='active')fail(409,'STATE_CONFLICT','Отклик больше не активен');
      if(offerCommand[2]!=='withdraw'&&offerExpired(f,settings.offer_expiry_hours))fail(409,'OFFER_EXPIRED','Срок отклика истёк. Отправьте новый отклик.');
      const o=await this.object(f.order_id,a,'order');if(o.status!=='open')fail(409,'STATE_CONFLICT','Заказ закрыт');
      if(offerCommand[2]==='withdraw'&&method==='POST'){const c=await this.store.get(f.conversation_id);if(c)await this.store.put({...c,status:'closed',version:c.version+1});return this.store.put({...f,status:'withdrawn',version:f.version+1});}
      await this.entitlement(a,'send_offer',true);
      if(offerCommand[2]==='acknowledge'&&method==='POST'){if(b.order_revision!==o.revision)fail(409,'REVISION_NOT_ACKNOWLEDGED','Условия изменились');return this.store.put({...f,acknowledged_revision:o.revision,acknowledged_order:offerOrderSnapshot(o),version:f.version+1});}
      if(method==='PATCH'){if(!Number.isSafeInteger(b.amount)||b.amount<0)fail(400,'VALIDATION_ERROR','Проверьте цену');if(b.acknowledged_revision!==undefined&&b.acknowledged_revision!==o.revision)fail(409,'REVISION_NOT_ACKNOWLEDGED','Условия изменились');return this.store.put({...f,text:text(b,'text',1,3000),amount:b.amount,...offerTerms(o,b,settings.offer_expiry_hours,new Date(),f),...(b.acknowledged_revision!==undefined?{acknowledged_revision:o.revision,acknowledged_order:offerOrderSnapshot(o)}:{}),version:f.version+1});}
    }
    if(path==='/me/order-invites'&&method==='GET'){
      if(q.status&&!['pending','accepted','declined','expired','revoked'].includes(q.status))fail(400,'VALIDATION_ERROR','Неизвестный статус приглашения');
      const result=await this.page('invite',a,q,{recipient:a.id,inviteState:q.status});
      result.items=result.items.map(x=>({...x,status:x.status==='pending'&&x.expires_at&&x.expires_at<=new Date().toISOString()?'expired':x.status}));
      result.items=await Promise.all(result.items.map(async i=>{
        const order=await this.store.get(i.order_id),sender=await this.store.get(i.owner);
        const visible=order?.country===a.country&&sender?.status==='active'&&!await this.blocked(a,i.owner)&&!['quarantined','hidden','rejected'].includes(order?.moderation_status);
        return {...i,customer:visible?{display_name:sender?.display_name,avatar_id:sender?.avatar_id}:null,order:visible?{title:order?.title,city:order?.city,budget_amount:order?.budget_amount,currency:order?.currency,time_window:order?.time_window}:null};
      }));return result;
    }
    const inviteCommand=path.match(/^\/order-invites\/([^/]+)\/(respond|revoke)$/);
    if(inviteCommand&&method==='POST') {
      const r=await this.object(inviteCommand[1],a,'invite');if((inviteCommand[2]==='respond'?r.recipient_id:r.owner)!==a.id)fail(404,'NOT_FOUND','Приглашение не найдено');this.version(r,b);
      if(r.status!=='pending'||r.expires_at&&r.expires_at<=new Date().toISOString())fail(409,'STATE_CONFLICT','Приглашение обработано или срок истёк');
      if(inviteCommand[2]==='revoke')return this.store.put({...r,status:'revoked',version:r.version+1});
      if(!['accept','decline'].includes(b.decision))fail(400,'VALIDATION_ERROR','Выберите accept или decline');
      if(b.decision==='accept'){
        const o=await this.object(r.order_id,a,'order'),sender=await this.store.get(r.owner);
        if(o.status!=='open'||o.expires_at<=new Date().toISOString()||['quarantined','hidden','rejected'].includes(o.moderation_status)||o.revision!==r.order_revision)fail(409,'STATE_CONFLICT','Заказ закрыт или условия изменились');
        if(!sender||sender.status!=='active'||await this.blocked(a,r.owner))fail(404,'NOT_FOUND','Приглашение недоступно');
        await this.entitlement({...a,id:sender!.id,user:sender!},'publish_order',false,false);
        await this.entitlement(a,'send_offer',true,false);
      }return this.store.put({...r,status:b.decision==='accept'?'accepted':'declined',version:r.version+1});
    }
    const workDetail=path.match(/^\/(order-invites|cancel-requests|amendments|conversations)\/([^/]+)$/);
    if(workDetail&&method==='GET'){
      const kind=({'order-invites':'invite','cancel-requests':'cancel_request',amendments:'amendment',conversations:'conversation'} as any)[workDetail[1]],r=await this.object(workDetail[2],a,kind);
      if(r.owner!==a.id&&r.recipient_id!==a.id&&!r.members?.includes(a.id))fail(404,'NOT_FOUND','Запись не найдена');
      if(kind==='conversation'){
        const order=r.order_id?await this.store.get(r.order_id):null;
        let blocked=['closed','frozen','restricted'].includes(r.status),blocked_reason=blocked?(r.status==='closed'?'conversation_closed':'safety_restriction'):null;
        if(['open','closed'].includes(r.status)&&r.offer_id){const offer=await this.store.get(r.offer_id);if(offer&&offerExpired(offer,settings.offer_expiry_hours)){blocked=true;blocked_reason='offer_expired';}}
        for(const member of r.members)if(member!==a.id&&await this.blocked(a,member)){blocked=true;blocked_reason='pair_blocked';}
        const peerId=r.members.find((id:string)=>id!==a.id),peer=peerId?await this.store.get(peerId):null;
        const visiblePeer=peer?.kind==='user'&&peer.country===a.country;
        return {id:r.id,status:r.status,order_id:r.order_id,order_title:order?.title??'',
          order_status:order?.status,order_amount:order?.agreed_amount??order?.budget_amount,currency:order?.currency,
          peer:visiblePeer?{id:peer.id,display_name:peer.display_name,avatar_id:peer.avatar_id}:null,blocked,blocked_reason};
      }
      return r;
    }
    if(path==='/me/conversations'&&method==='GET'){
      const page=await this.page('conversation',a,q,{member:a.id});if(!page.items.length)return page;
      const summaries=await db.query<{id:string;peer:any;order_title:string;order_status:string;last_message:any;unread_count:string}>(`
        SELECT c.id,jsonb_build_object('id',peer.id,'display_name',peer.data->>'display_name','avatar_id',peer.data->>'avatar_id') AS peer,
          o.data->>'title' AS order_title,o.data->>'status' AS order_status,last_message.data AS last_message,
          (SELECT count(*) FROM records m WHERE m.kind='message' AND m.country=c.country AND m.data->>'thread_id'=c.id::text AND m.owner<>$3
            AND (m.data->>'sequence')::int>COALESCE((c.data->'read_sequences'->>$3)::int,0)
            AND COALESCE(m.data->>'moderation_status','') NOT IN('quarantined','hidden','rejected') AND COALESCE(m.data->>'tombstone','false')<>'true') AS unread_count
        FROM records c
        LEFT JOIN records o ON o.id::text=c.data->>'order_id' AND o.kind='order' AND o.country=c.country
        LEFT JOIN LATERAL(SELECT u.id,u.data FROM records u WHERE u.kind='user' AND u.country=c.country AND u.id::text<>$3 AND COALESCE(c.data->'members','[]'::jsonb) ? u.id::text ORDER BY u.id LIMIT 1)peer ON true
        LEFT JOIN LATERAL(SELECT m.data FROM records m WHERE m.kind='message' AND m.country=c.country AND m.data->>'thread_id'=c.id::text
          AND (COALESCE(m.data->>'moderation_status','') NOT IN('quarantined','hidden','rejected') OR m.owner=$3)
          ORDER BY (m.data->>'sequence')::int DESC LIMIT 1)last_message ON true
        WHERE c.id=ANY($1::uuid[]) AND c.country=$2 AND c.kind='conversation' AND COALESCE(c.data->'members','[]'::jsonb) ? $3`,[page.items.map(c=>c.id),a.country,a.id]);
      return {...page,items:page.items.map(c=>{const summary=summaries.rows.find(r=>r.id===c.id)!,m=summary.last_message;
        const hidden=m&&(['hidden','rejected'].includes(m.moderation_status)||m.moderation_status==='quarantined'&&m.owner!==a.id);
        return {id:c.id,status:c.status,order_id:c.order_id,order_title:summary.order_title,order_status:summary.order_status,peer:summary.peer?.id?summary.peer:null,
          unread_count:Number(summary.unread_count),last_message:m?{text:m.tombstone||hidden?'':String(m.text??'').slice(0,200),created_at:m.created_at,tombstone:m.tombstone===true,hidden,has_attachments:!hidden&&!m.tombstone&&!!m.upload_ids?.length}:null};})};
    }
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
    if(path==='/support/threads'&&method==='POST'){
      const subject=text(b,'subject',5,120);
      const topics=['orders','account','payment','technical','other'];
      if(b.topic!==undefined&&!topics.includes(b.topic))fail(400,'VALIDATION_ERROR','Выберите тему обращения');
      let orderId:string|undefined;
      if(b.order_id){const order=await this.object(String(b.order_id),a,'order');if(![order.owner,order.executor_id].includes(a.id))fail(404,'NOT_FOUND','Заказ не найден');orderId=order.id;}
      const uploads=b.upload_ids===undefined?[]:await this.safeUploads(a,b.upload_ids,'chat');
      const initial=b.text===undefined?undefined:text(b,'text',1,3000);
      if(uploads.length&&!initial)fail(400,'VALIDATION_ERROR','Опишите вопрос для поддержки');
      const thread=await this.store.put(this.record('support',a,{subject,status:'new',members:[a.id],...(b.topic?{topic:b.topic}:{}),...(orderId?{order_id:orderId}:{})}));
      if(initial!==undefined)await this.messages(thread,a,'POST',{text:initial,upload_ids:uploads,client_message_id:randomUUID()},{},'support_message');
      return thread;
    }
    const sm=path.match(/^\/support\/threads\/([^/]+)\/messages$/);
    if(sm){const t=await this.object(sm[1],a,'support',true);return this.messages(t,a,method,b,q,'support_message');}
    if(path==='/reviews'&&method==='POST') {
      const o=await this.object(String(b.order_id),a,'order');if(o.status!=='completed'||![o.owner,o.executor_id].includes(a.id))fail(403,'FORBIDDEN','Отзыв доступен только участнику завершённого заказа');
      if(!Number.isInteger(b.rating)||b.rating<1||b.rating>5)fail(400,'VALIDATION_ERROR','Оценка от 1 до 5');
      if((await this.store.all('review',a.country)).some(x=>x.order_id===o.id&&x.owner===a.id))fail(409,'STATE_CONFLICT','Отзыв уже оставлен');
      const r=this.record('review',a,{order_id:o.id,target_id:o.owner===a.id?o.executor_id:o.owner,rating:b.rating,text:text(b,'text',0,2000),status:'sealed',publish_after:new Date(Date.parse(o.completed_at)+settings.review_blind_days*86400000).toISOString()});await this.store.put(r);
      const all=(await this.store.all('review',a.country)).filter(x=>x.order_id===o.id);
      const disputed=(await this.store.all('case',a.country)).some(c=>c.target_id===o.id&&!['resolved','closed'].includes(c.status));
      const publish=all.length===2&&!disputed&&!all.some(x=>['quarantined','hidden','rejected'].includes(x.moderation_status));
      if(publish)for(const x of all)await this.store.put({...x,status:'published',published_at:new Date().toISOString(),version:x.version+1});return (await this.store.get(r.id))!;
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
    if(path==='/me/push-tokens'&&method==='POST'){
      if(!['ios','android','web'].includes(b.platform))fail(400,'VALIDATION_ERROR','Проверьте платформу');const value=text(b,'token',10,4096);
      await db.query('SELECT pg_advisory_xact_lock(hashtextextended($1,0))',['push-token:'+createHash('sha256').update(value).digest('hex')]);
      const previous=(await db.query<{data:RecordData}>("SELECT data FROM records WHERE kind='push_token' AND data->>'token'=$1 AND data->>'status'='active'",[value])).rows.map(r=>r.data);
      const own=previous.find(p=>p.owner===a.id&&p.country===a.country);
      for(const p of previous)if(p.id!==own?.id)await this.store.put({...p,status:'revoked',token:'',version:p.version+1});
      const result=await this.store.put({...own??this.record('push_token',a),token:value,platform:b.platform,session_family:a.family,environment:b.environment==='production'?'production':'sandbox',status:'active',version:own?own.version+1:1});
      for(const {data:r} of (await db.query<{data:RecordData}>("SELECT data FROM records WHERE kind='outbox' AND country=$1 AND data->>'recipient_id'=$2 AND data->>'status'='waiting_token'",[a.country,a.id])).rows)await this.store.put({...r,status:'pending',version:r.version+1});
      const {token,...safe}=result;return safe;
    }
    const pushToken=path.match(/^\/me\/push-tokens\/([^/]+)$/);if(pushToken&&method==='DELETE'){const r=await this.object(pushToken[1],a,'push_token',true);return this.store.put({...r,status:'revoked',token:'',version:r.version+1}).then(({token,...r})=>r);}
    const votes=path.match(/^\/listing-votes\/(orders|services)\/([^/]+)$/);
    if(votes&&['PUT','DELETE'].includes(method)) {
      await this.entitlement(a,'search_full',votes[1]==='orders');const target=await this.object(votes[2],a,votes[1]==='orders'?'order':'contractor');
      const owner=await this.store.get(target.owner);
      if(['quarantined','hidden','rejected'].includes(target.moderation_status)||owner?.kind!=='user'||owner.country!==a.country||owner.status!=='active'||target.kind==='contractor'&&owner.verification!=='passed'||target.kind==='order'&&!(target.expires_at>new Date().toISOString())||await this.blocked(a,target.owner))fail(404,'NOT_FOUND','Карточка недоступна');
      if(target.owner===a.id)fail(403,'FORBIDDEN','Нельзя голосовать за свою карточку');
      if(!['open','published'].includes(target.status))fail(409,'STATE_CONFLICT','Карточка недоступна');
      if(method==='DELETE'){await db.query('DELETE FROM votes WHERE voter=$1 AND target=$2',[a.id,target.id]);return {removed:true};}
      if(![-1,1].includes(b.value))fail(400,'VALIDATION_ERROR','Голос: 1 либо -1');
      await db.query('INSERT INTO votes(voter,target,value) VALUES($1,$2,$3) ON CONFLICT(voter,target) DO UPDATE SET value=excluded.value,created_at=now()',[a.id,target.id,b.value]);return {target_id:target.id,value:b.value};
    }
    if(path==='/top-listings'&&method==='GET') {
      if(q.target_type!==undefined&&!['orders','services'].includes(q.target_type)||q.sort!==undefined&&!['popular','new'].includes(q.sort)||q.country!==undefined&&q.country!==a.country||['city','category_id'].some(key=>q[key]!==undefined&&(typeof q[key]!=='string'||q[key].length>100)))fail(400,'VALIDATION_ERROR','Проверьте тип, страну и фильтры Топа');
      const kind=q.target_type==='orders'?'order':'contractor';await this.entitlement(a,'search_full',kind==='order');
      const config=(await this.store.all('ranking_config',a.country)).find(r=>r.status==='effective');
      const parameters=rankingParameters(config?.payload??{window_days:settings.ranking_window_days,dislike_weight:settings.ranking_dislike_weight,age_days:settings.ranking_age_days});
      const candidates=await this.store.select(kind,a.country,{statuses:[kind==='order'?'open':'published'],publicActor:a.id,city:q.city,category:q.category_id,limit:100,ranking:{...parameters,sort:q.sort??'popular'}});
      const items=kind==='contractor'?await contractorPresentation(this.store,a.country,candidates):candidates.map(row=>({...publicContent(row),exact_address:undefined}));
      return {items,promotions:[],meta:{algorithm_version:config?.version??1,algorithm_id:config?.id??null,parameters,sort:q.sort??'popular',calculated_at:new Date().toISOString()}};
    }
    const reviews=path.match(/^\/(customers|contractors)\/([^/]+)\/reviews$/);
    if(reviews&&method==='GET'){await this.entitlement(a,'search_full');return this.list((await this.store.all('review',a.country)).filter(x=>x.target_id===reviews[2]&&x.status==='published'&&!['quarantined','hidden','rejected'].includes(x.moderation_status)),q);}
    if(path==='/me/deletion-preview'&&method==='GET'){
      const active=(await this.store.select('order',a.country,{participant:a.id,statuses:['assigned','in_progress','completion_requested'],limit:1000})).length;
      return {active_orders:active,subscription_relevant:a.user.active_role==='executor'&&(await this.store.select('subscription',a.country,{owner:a.id,limit:1000})).some(s=>['active','grace','canceled_at_period_end'].includes(s.status)),policy_ready:(await this.store.all('retention_policy',a.country)).some(p=>p.status==='effective'),grace_hours:settings.deletion_grace_hours,retention_plan:await deletionPlan(this.store,a.id,a.country,(await this.store.all('retention_policy',a.country)).find(p=>p.status==='effective'),new Date())};
    }
    if(path==='/me/processing-consents'&&method==='GET')return (await this.store.select('processing_consent',a.country,{owner:a.id,limit:1}))[0]??{version:0,marketing:false,ad_personalization:false,optional_analytics:false};
    if(path==='/me/processing-consents'&&method==='POST'){
      const keys=['marketing','ad_personalization','optional_analytics'];if(keys.some(k=>typeof b[k]!=='boolean'))fail(400,'VALIDATION_ERROR','Проверьте выбор согласий');
      const old=(await this.store.select('processing_consent',a.country,{owner:a.id,limit:1}))[0];if(b.expected_version!==(old?.version??0))fail(409,'STATE_CONFLICT','Согласия изменились. Обновите данные');
      const doc=currentLegalDocuments(await this.store.all('legal_document',a.country),a.country,a.user.locale??'ru').find(d=>['privacy','privacy_policy'].includes(d.type));
      if(keys.some(k=>b[k])&&!doc)fail(403,'CONSENT_REQUIRED','Для согласия нужна опубликованная политика конфиденциальности');
      const values=Object.fromEntries(keys.map(k=>[k,b[k]])),r={...(old??this.record('processing_consent',a)),...values,document_id:doc?.id??null,document_hash:doc?.hash??null,updated_at:new Date().toISOString(),version:(old?.version??0)+1};
      await this.store.put(this.record('processing_consent_event',a,{...values,document_id:r.document_id,document_hash:r.document_hash}));return this.store.put(r);
    }
    if(path==='/me/privacy-requests'&&method==='POST'){await this.reauth(a,b);if(!['export','delete'].includes(b.type))fail(400,'VALIDATION_ERROR','Выберите тип запроса');if(b.type==='delete'){const previous=(await this.store.select('privacy',a.country,{owner:a.id,statuses:['requested','scheduled','awaiting_retention_policy','awaiting_resolution'],limit:100})).find(r=>r.type==='delete');if(previous)return previous;}return this.store.put(this.record('privacy',a,{type:b.type,status:'requested'}));}
    if(path==='/me/privacy-requests'&&method==='GET')return {items:(await this.store.all('privacy',a.country)).filter(x=>x.owner===a.id)};
    const privacy=path.match(/^\/me\/privacy-requests\/([^/]+)$/);if(privacy&&method==='GET'){
      const r=await this.object(privacy[1],a,'privacy',true);if(r.type!=='export')return r;
      const file=r.upload_id?await this.store.get(r.upload_id):undefined;
      const owned=file?.kind==='upload'&&file.purpose==='export'&&file.owner===a.id&&file.country===a.country;
      return {...r,download_available:!!(r.status==='completed'&&owned&&file.status==='clean'&&file.expires_at>new Date().toISOString()),download_expires_at:owned?file.expires_at:null};
    }
    const privacyCancel=path.match(/^\/me\/privacy-requests\/([^/]+)\/cancel$/);
    if(privacyCancel&&method==='POST') {
      const r=await this.object(privacyCancel[1],a,'privacy',true);this.version(r,b);
      if(!['requested','awaiting_retention_policy','scheduled','awaiting_resolution'].includes(r.status))fail(409,'STATE_CONFLICT','Обработка уже началась');
      return this.store.put({...r,status:'cancelled',version:r.version+1});
    }
    if(path==='/cases'&&method==='POST'){
      const type=text(b,'target_type',1,30);
      if(!['order','contractor','user','message'].includes(type))fail(400,'VALIDATION_ERROR','Выберите доступный тип объекта');
      const target=await this.object(text(b,'target_id',1,100),a,type);
      let visible=target.owner===a.id;const subject=target.kind==='user'?target.id:target.owner;
      if(type==='order'){
        const owner=await this.store.get(target.owner);
        visible=visible||target.executor_id===a.id||owner?.status==='active'&&target.status==='open'&&target.expires_at>new Date().toISOString()&&!['quarantined','hidden','rejected'].includes(target.moderation_status)&&!await this.blocked(a,target.owner);
      }
      if(type==='contractor'){
        const owner=await this.store.get(target.owner);
        visible=visible||target.status==='published'&&owner?.status==='active'&&owner.verification==='passed'&&!['quarantined','hidden','rejected'].includes(target.moderation_status)&&!await this.blocked(a,target.owner);
      }
      if(type==='message'){
        const conversation=await this.store.get(target.thread_id);
        visible=conversation?.kind==='conversation'&&conversation.country===a.country&&conversation.members?.includes(a.id);
      }
      if(type==='user'){
        visible=target.id===a.id||(await this.store.all('conversation',a.country)).some(c=>c.members?.includes(a.id)&&c.members?.includes(target.id))||(await this.store.all('order',a.country)).some(o=>[o.owner,o.executor_id].includes(a.id)&&[o.owner,o.executor_id].includes(target.id));
      }
      if(!visible)fail(404,'NOT_FOUND','Объект недоступен для обращения');
      const reason=text(b,'reason_code',1,50);if(!['agreement','spam','fraud','content','other','harassment','unsafe','privacy'].includes(reason))fail(400,'VALIDATION_ERROR','Выберите причину обращения');
      const existing=(await this.store.all('case',a.country)).find(c=>c.owner===a.id&&c.target_id===target.id&&!['resolved','closed','dismissed'].includes(c.status));
      if(existing)fail(409,'STATE_CONFLICT','По этому объекту уже есть открытое обращение',{case_id:existing.id});
      return this.store.put(this.record('case',a,{target_type:type,target_id:target.id,...freezeTarget(target,target.owner===a.id&&target.draft?'draft':'public'),subject_user_id:subject,reporter_private:true,upload_ids:b.upload_ids?await this.safeUploads(a,b.upload_ids,'chat'):[],reason_code:reason,description:text(b,'description',10,3000),status:'new'})).then(visibleCase);
    }
    if(path==='/me/cases/overview'&&method==='GET'){
      const count=(await db.query<{open_count:string;resolved_count:string}>("SELECT count(*) FILTER(WHERE data->>'status' NOT IN ('resolved','closed','dismissed')) AS open_count,count(*) FILTER(WHERE data->>'status' IN ('resolved','closed','dismissed')) AS resolved_count FROM records WHERE kind='case' AND country=$1 AND (owner=$2 OR data->>'subject_user_id'=$2 AND COALESCE(data->>'reporter_private','false')<>'true')",[a.country,a.id])).rows[0];
      return {open:Number(count.open_count),resolved:Number(count.resolved_count)};
    }
    if(path==='/me/cases'&&method==='GET'){
      if(q.bucket&&!['open','resolved'].includes(q.bucket))fail(400,'VALIDATION_ERROR','Неизвестный раздел обращений');
      const result=await this.page('case',a,q,{caseActor:a.id,caseBucket:q.bucket,statuses:q.status?[q.status]:undefined});
      result.items=result.items.map(visibleCase);return result;
    }
    const caseRead=path.match(/^\/cases\/([^/]+)$/);
    if(caseRead&&method==='GET') {
      const c=await this.object(caseRead[1],a,'case');if(c.owner!==a.id&&(c.reporter_private||c.subject_user_id!==a.id))fail(404,'NOT_FOUND','Дело не найдено');
      return visibleCase(c);
    }
    const caseUpdate=path.match(/^\/cases\/([^/]+)\/(messages|appeals)$/);
    if(caseUpdate&&method==='GET'&&caseUpdate[2]==='messages') {
      const c=await this.object(caseUpdate[1],a,'case');if(c.owner!==a.id&&(c.reporter_private||c.subject_user_id!==a.id))fail(404,'NOT_FOUND','Дело не найдено');
      return this.list((await this.store.all('case_message',a.country)).filter(x=>x.case_id===c.id&&!x.internal),q);
    }
    if(caseUpdate&&method==='POST') {
      const c=await this.object(caseUpdate[1],a,'case');if(c.owner!==a.id&&(c.reporter_private||c.subject_user_id!==a.id))fail(404,'NOT_FOUND','Дело не найдено');
      if(caseUpdate[2]==='appeals') {
        if(c.subject_user_id!==a.id||!['resolved','restricted'].includes(c.status)||c.status==='resolved'&&!['content_removed','sanction_upheld'].includes(c.decision))fail(409,'STATE_CONFLICT','Апелляция недоступна');
        this.version(c,b);const result=await this.store.put({...c,status:'appealed',appeal_reason:text(b,'reason',10,3000),appeal_upload_ids:b.upload_ids===undefined?[]:await this.safeUploads(a,b.upload_ids,'chat'),appeal_submitted_at:new Date().toISOString(),version:c.version+1});return result;
      }
      return this.store.put(this.record('case_message',a,{case_id:c.id,text:text(b,'text',1,3000),upload_ids:b.upload_ids?await this.safeUploads(a,b.upload_ids,'chat'):[]}));
    }
    if(path==='/billing/offers'&&method==='GET')return a.user.active_role==='executor'?this.commerce.offers(a.country):{items:[]};
    if(['/billing/verify-purchase','/billing/restore'].includes(path)&&method==='POST'){if(path==='/billing/verify-purchase'&&a.user.active_role!=='executor')fail(403,'EXECUTOR_ROLE_REQUIRED','Подписка доступна только исполнителю');return this.commerce.verify(a.id,a.country,String(b.provider),text(b,'transaction_reference',1,10000));}
    const purchaseCheck=path.match(/^\/me\/purchase-checks\/([^/]+)$/);if(purchaseCheck&&method==='GET'){const r=await this.object(purchaseCheck[1],a,'purchase_check',true);return {id:r.id,status:r.status,subscription_id:r.subscription_id??null};}
    const ownSubscription=path.match(/^\/me\/subscriptions\/([^/]+)$/);if(ownSubscription&&method==='GET'){const r=await this.object(ownSubscription[1],a,'subscription',true);return {id:r.id,provider:r.provider,product_id:r.product_id,status:r.status,valid_until:r.valid_until,price:r.price_snapshot?{amount_minor:r.price_snapshot.amount_minor,currency:r.price_snapshot.currency,period:r.price_snapshot.period}:null};}
    if(path==='/me/subscriptions'&&method==='GET')return {items:(await this.store.all('subscription',a.country)).filter(x=>x.owner===a.id).map(r=>({id:r.id,provider:r.provider,product_id:r.product_id,status:r.status,valid_until:r.valid_until,price:r.price_snapshot?{amount_minor:r.price_snapshot.amount_minor,currency:r.price_snapshot.currency,period:r.price_snapshot.period}:null}))};
    if(path==='/billing/refundable-payments'&&method==='GET'){
      const limit=this.pageLimit(q),after=await this.cursor(q);
      const rows=await this.store.db.query<{data:RecordData}>("SELECT data FROM records WHERE kind='payment_transaction' AND country=$1 AND owner=$2 AND data->>'state'='active' AND data->>'operation' IN ('purchase','renewal') AND CASE WHEN jsonb_typeof(data->'cash_amount_minor')='number' THEN (data->>'cash_amount_minor')::numeric ELSE 0 END>0 AND ($3::uuid IS NULL OR id>$3) ORDER BY id LIMIT $4",[a.country,a.id,after??null,limit+1]);
      const batch=rows.rows.slice(0,limit).map(x=>x.data),balances=await this.refunds.balances(batch);
      return {items:batch.map((p,i)=>({id:p.id,created_at:p.created_at,amount_minor:p.amount_minor,currency:p.currency,benefit:p.benefit,balance:balances[i]})),meta:{next_cursor:rows.rows.length>limit?await this.nextCursor(batch.at(-1)!.id,q):null}};
    }
    if(path==='/billing/refund-requests'&&method==='GET'){
      const page=await this.page('refund_request',a,q,{owner:a.id});return {...page,items:page.items.map((r:any)=>({id:r.id,payment_id:r.payment_id??null,subscription_id:r.subscription_id??null,amount_minor:r.amount_minor??null,currency:r.currency??null,status:r.status,reason:r.reason,created_at:r.created_at,version:r.version,access_action:r.access_action??null}))};
    }
    const ownRefund=path.match(/^\/billing\/refund-requests\/([^/]+)\/cancel$/);
    if(ownRefund&&method==='POST'){const r=await this.object(ownRefund[1],a,'refund_request',true);this.version(r,b);return this.refunds.command(r,a.id,'cancel',text(b,'reason',5,1000));}
    if(path==='/billing/refund-requests'&&method==='POST'){
      if(b.payment_id)return this.refunds.create(a.id,a.country,text(b,'payment_id',36,36),b.amount_minor,text(b,'reason',5,1000));
      const subscription=await this.object(text(b,'subscription_id',36,36),a,'subscription',true);
      return this.store.put(this.record('refund_request',a,{subscription_id:subscription.id,reason:text(b,'reason',5,1000),status:'requested'}));
    }
    if(path==='/ads/reward-sessions'&&method==='POST')return this.commerce.rewardSession(a.id,a.country,b);
    const reward=path.match(/^\/ads\/reward-sessions\/([^/]+)$/);if(reward&&method==='GET'){const r=await this.object(reward[1],a,'ad_session',true),grant=(await this.store.select('grant',a.country,{owner:a.id,sourceId:r.id,limit:1}))[0];return {id:r.id,status:r.status,expires_at:r.expires_at,grant:grant?{valid_until:grant.valid_until,balance:grant.balance,capabilities:grant.capabilities}:null};}
    const outcome=path.match(/^\/ads\/reward-sessions\/([^/]+)\/outcome$/);if(outcome&&method==='POST'){const r=await this.object(outcome[1],a,'ad_session',true);if(!['completed','no_fill'].includes(b.outcome))fail(400,'VALIDATION_ERROR','Проверьте исход просмотра');if(r.status!=='pending')return {id:r.id,status:r.status};return this.store.put({...r,...(b.outcome==='no_fill'?{status:'no_fill'}:{client_completed_at:new Date().toISOString()}),version:r.version+1});}
    if(path==='/me/referrals'&&method==='GET')return this.growth.referrals(a.id,a.country);
    if(path==='/referrals/attribute'&&method==='POST')return this.growth.attribute(a.id,a.country,text(b,'code',1,50));
    const redeem=path.match(/^\/me\/referral-rewards\/([^/]+)\/redeem$/);if(redeem&&method==='POST')return this.growth.redeem(a.id,a.country,redeem[1]);
    if(path==='/promoted-listings'&&method==='GET'){const placement=String(q.placement_id??'');if(!promotedPlacements.includes(placement))fail(400,'VALIDATION_ERROR','Неизвестное размещение');await this.entitlement(a,'search_full',placement.includes('.orders.'));return promotedListings(this.store,a.country,a.id,placement,q);}
    if(path==='/boost-offers'&&method==='GET'){await this.entitlement(a,'search_full');return {items:(await this.store.all('price_version',a.country)).filter(x=>x.status==='effective'&&x.payload.product_type==='boost').map(x=>({id:x.id,...x.payload})),placements:(await this.store.all('placement_policy',a.country)).filter(x=>x.status==='effective')};}
    if(path==='/boost-reservations'&&method==='POST'){const target=await this.object(String(b.target_id),a,undefined,true);await this.entitlement(a,'search_full',target.kind==='contractor');return this.growth.reserveBoost(a.id,a.country,b);}
    if(path==='/boost-purchases/verify'&&method==='POST')return this.growth.verifyBoost(a.id,a.country,b);
    if(path==='/me/boosts'&&method==='GET'){
      if(q.bucket!==undefined&&!['active','history'].includes(q.bucket))fail(400,'VALIDATION_ERROR','Выберите раздел размещений');
      const page=await this.page('boost',a,q,{owner:a.id,boostBucket:q.bucket});return {...page,items:await boostPresentation(this.store,a.country,page.items)};
    }
    const ownBoost=path.match(/^\/me\/boosts\/([^/]+)$/);if(ownBoost&&method==='GET')return (await boostPresentation(this.store,a.country,[await this.object(ownBoost[1],a,'boost',true)]))[0];
    const cropUpload=path.match(/^\/uploads\/([^/]+)\/crop$/);if(cropUpload&&method==='POST'){
      const source=await this.object(cropUpload[1],a,'upload',true);
      if(source.purpose!=='portfolio'||source.status!=='clean'||!source.mime.startsWith('image/')||b.mode!=='square')fail(422,'POLICY_REJECTED','Обрезка недоступна');
      const bytes=await this.files.read(source.id),image=sharp(bytes,{limitInputPixels:25000000}).rotate(),meta=await image.metadata();
      const width=meta.autoOrient?.width??meta.width!,height=meta.autoOrient?.height??meta.height!,size=Math.min(width,height);
      const cropped=await image.extract({left:Math.floor((width-size)/2),top:Math.floor((height-size)/2),width:size,height:size}).jpeg({quality:90}).toBuffer();
      const file=this.record('upload',a,{purpose:'portfolio',mime:'image/jpeg',status:'clean',size:cropped.length,stored_size:cropped.length,derived_from:source.id});
      try{await this.files.write(file.id,cropped);return await this.store.put(file);}catch(e){await this.files.remove(file.id);throw e;}
    }
    if(path==='/uploads/initiate'&&method==='POST') {
      if(!['avatar','portfolio','order','chat','identity','brand','banner'].includes(b.purpose))fail(400,'VALIDATION_ERROR','Недопустимая цель загрузки');
      if(b.purpose==='banner'){await this.staff(a,'campaign');if(!['image/png','image/jpeg'].includes(b.mime)||b.size>5*1024*1024)fail(422,'POLICY_REJECTED','Нужен PNG или JPEG до 5 MB');}
      if(b.purpose==='brand'){await this.staff(a,'content');if(b.mime!=='image/png'||b.size>5*1024*1024)fail(422,'POLICY_REJECTED','Нужен PNG до 5 MB');}
      if(b.purpose==='identity'){const verification=await this.object(String(b.verification_id),a,'verification',true);if(!['draft','rejected'].includes(verification.status))fail(409,'STATE_CONFLICT','Заявка не принимает файлы');}
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
      if(path==='/admin/search'&&method==='GET') {
        if(!a.mfa||a.user.status!=='active'||!a.user.staff_permissions?.length)fail(403,'FORBIDDEN','Требуется служебный вход с MFA');
        const admin=a.user.staff_permissions.includes('administrator'),permissions=a.user.staff_permissions;
        const allowed=[...(admin?['user','order']:[]),...(admin||permissions.includes('moderator')?['case']:[]),
          ...(admin||permissions.includes('support')?['support']:[]),...(permissions.includes('verification_reviewer')?['verification']:[])];
        const query=text({q:q.q??''},'q',0,120);
        if(q.kind&&!allowed.includes(q.kind))fail(403,'FORBIDDEN','Тип записи недоступен этой роли');
        if(query.length<2)return {items:[],kinds:allowed};
        const pattern='%'+query.replace(/[\\%_]/g,'\\$&')+'%';
        const rows=(await db.query<{data:RecordData}>(`SELECT data FROM records WHERE country=$1 AND kind=ANY($2::text[])
          AND (kind<>'user' OR COALESCE(jsonb_array_length(data->'staff_permissions'),0)=0)
          AND (id::text ILIKE $3 OR data->>'display_name' ILIKE $3 OR data->>'title' ILIKE $3 OR data->>'subject' ILIKE $3 OR data->>'reason_code' ILIKE $3)
          ORDER BY id LIMIT 20`,[a.country,q.kind?[q.kind]:allowed,pattern])).rows;
        return {kinds:allowed,items:rows.map(({data:r})=>({id:r.id,kind:r.kind,country:r.country,status:r.status,
          title:r.display_name??r.title??r.subject??r.reason_code??r.document_type??r.id}))};
      }
      if(section==='brand-icons'&&method==='GET'){
        if(!a.mfa||a.user.status!=='active'||!a.user.staff_permissions?.some((p:string)=>['content','brand_owner','release','administrator'].includes(p)))fail(403,'FORBIDDEN','Нужны служебные права брендинга и MFA');
        const match=path.match(/^\/admin\/brand-icons\/([^/]+)(?:\/(preview|source|bundle))?$/);
        if(!match)return this.page('brand_icon',a,q);
        const record=await this.object(match[1],a,'brand_icon');
        if(!match[2])return record;
        if(match[2]==='source'){const upload=await this.object(record.source_upload_id,a,'upload');if(upload.purpose!=='brand'||upload.status!=='clean'||!['image/png','image/jpeg'].includes(upload.mime))fail(404,'NOT_FOUND','Исходник недоступен');return {download_buffer:await this.files.read(upload.id),mime:upload.mime};}
        if(match[2]==='preview')return {download_buffer:await this.branding.preview(record,String(q.mask??'ios')),mime:'image/png'};
        if(record.status!=='generated'||!record.bundle_file_id)fail(409,'STATE_CONFLICT','Пакет ещё не сформирован');
        await this.audit(a,'brand.bundle_read',record.id,text(q,'reason',10,1000));
        return {download_stream:await this.files.readStream(record.bundle_file_id),download_size:record.bundle_size,download_filename:'joba-icons.zip',mime:'application/zip'};
      }
      const permission=({categories:'content','category-tree':'content','banner-campaigns':'campaign','account-restriction-jobs':'bulk_restrict','security-events':'security','legal-holds':'privacy','push-test-accounts':'campaign',languages:'content',bulk:'content',revenue:'billing',audit:'auditor','support-threads':'support','recovery-threads':'support',verifications:'verification_reviewer',portfolio:'content',contractors:'content','price-versions':'billing','monetization-configs':'billing','monetization-summary':'billing','payment-transactions':'billing','refund-requests':'billing',promotions:'billing','referral-campaigns':'campaign','push-campaigns':'campaign','moderation-dictionaries':'moderator_manager','ranking-configs':'content','boost-grants':'promotion','boost-reports':'promotion','placement-policies':'promotion','brand-icons':path.endsWith('/approve')?'brand_owner':path.endsWith('/generate')?'release':'content',cases:'moderator','privacy-requests':'privacy',blacklist:'senior_moderator'} as Record<string,string>)[section]??'administrator';
      await this.staff(a,permission);
      if(section==='account-restriction-jobs'){const result=await accountRestrictionJobs(this.store,a,method,path,b,{audit:(action,id,reason)=>this.audit(a,action,id,reason),notify:(user,id)=>this.notify(user,a,'case.updated',id)});if(result!==undefined)return result;}
      if(section==='banner-campaigns'){if(path==='/admin/banner-campaigns'&&method==='GET')return this.page('banner_campaign',a,q,{statuses:q.status?[String(q.status)]:undefined});const result=await bannerCampaigns(this.store,a,method,path,b,{object:id=>this.object(id,a,'banner_campaign'),record:data=>this.record('banner_campaign',a,data),audit:(action,id,reason)=>this.audit(a,action,id,reason)});if(result!==undefined)return result;}
      if(path==='/admin/category-tree'&&method==='GET')return {items:(await this.categories(a.country)).map(r=>({id:r.id,version_id:r.record_id,title:r.title,parent_id:r.payload.parent_id??null,labels:r.payload.labels,icon:r.payload.icon??'briefcase'}))};
      const report=await adminReports(this.store,a.country,method,path,q);if(report!==undefined)return report;
      if(path==='/admin/bulk/preview'&&method==='POST'){
        if(!['pause_contractors','resume_contractors'].includes(b.action)||!Array.isArray(b.ids)||b.ids.length<1||b.ids.length>100||new Set(b.ids).size!==b.ids.length||b.ids.some((id:any)=>typeof id!=='string'||!/^[0-9a-f-]{36}$/i.test(id)))fail(400,'VALIDATION_ERROR','Выберите от 1 до 100 уникальных профилей и действие');
        const reason=text(b,'reason',10,1000),snapshot=[];
        for(const id of b.ids){const target=await this.object(id,a,'contractor');snapshot.push({id:target.id,version:target.version,status:target.status});}
        const job=this.record('bulk_job',a,{status:'previewed',action:b.action,reason,snapshot,expires_at:new Date(Date.now()+600000).toISOString(),processed:0,results:[]});await this.store.put(job);await this.audit(a,'bulk.preview',job.id,reason);return job;
      }
      const bulk=path.match(/^\/admin\/bulk\/([^/]+)(?:\/(execute))?$/);
      if(bulk){const job=await this.object(bulk[1],a,'bulk_job',true);if(method==='GET'&&!bulk[2])return job;
        if(method==='POST'&&bulk[2]==='execute'){
          this.version(job,b);if(b.confirm!==true||job.status!=='previewed'||job.expires_at<=new Date().toISOString())fail(409,'STATE_CONFLICT','Подтверждение недоступно. Создайте новый предпросмотр');
          const reason=text(b,'reason',10,1000),results=[];
          for(const item of job.snapshot){
            const target=await this.store.get(item.id);let code:string|undefined;
            if(!target||target.country!==a.country||target.kind!=='contractor')code='NOT_FOUND';
            else if(target.version!==item.version)code='STATE_CONFLICT';
            else if(job.action==='pause_contractors'&&target.status!=='published'||job.action==='resume_contractors'&&target.status!=='paused')code='STATE_CONFLICT';
            else if(job.action==='resume_contractors'){
              const owner=await this.store.get(target.owner);if(!owner||owner.status!=='active'||owner.verification!=='passed'||['hidden','quarantined','rejected'].includes(target.moderation_status))code='POLICY_REJECTED';
            }
            if(code){results.push({id:item.id,status:'skipped',code});continue;}
            await this.store.put({...target!,status:job.action==='pause_contractors'?'paused':'published',version:target!.version+1});results.push({id:item.id,status:'applied'});
          }
          const updated=await this.store.put({...job,status:'completed',processed:results.length,results,completed_at:new Date().toISOString(),version:job.version+1});await this.audit(a,'bulk.executed',job.id,reason);return updated;
        }
      }
      if(path==='/admin/legal-holds'&&method==='GET'){const result=await this.page('legal_hold',a,q);await this.audit(a,'privacy.holds_read','legal_hold','Просмотр оснований и конкретных удержанных данных');return result;}
      if(path==='/admin/legal-holds'&&method==='POST'){
        const target=await this.object(String(b.target_id),a),snapshot=await holdSnapshot(this.store,target,b.fields);
        const review=Date.parse(String(b.review_at));if(!Number.isFinite(review)||review<=Date.now()||review>Date.now()+366*86400000)fail(400,'VALIDATION_ERROR','Дата пересмотра должна быть в пределах года');
        const hold=this.record('legal_hold',a,{target_id:target.id,subject_user_id:target.owner,...snapshot,basis:text(b,'basis',10,1000),reason:text(b,'reason',10,1000),review_at:new Date(review).toISOString(),status:'active'});await this.store.put(hold);await this.audit(a,'privacy.hold_created',hold.id,hold.reason);await this.notify(target.owner,a,'privacy.hold.created',hold.id);const {field_snapshot,...result}=hold;return result;
      }
      const holdRelease=path.match(/^\/admin\/legal-holds\/([^/]+)\/release$/);
      if(holdRelease&&method==='POST'){const hold=await this.object(holdRelease[1],a,'legal_hold');this.version(hold,b);if(hold.status!=='active')fail(409,'STATE_CONFLICT','Удержание уже закрыто');const reason=text(b,'reason',10,1000);const result=await this.store.put({...hold,status:'released',field_snapshot:undefined,release_reason:reason,released_by:a.id,released_at:new Date().toISOString(),version:hold.version+1});await this.audit(a,'privacy.hold_released',hold.id,reason);await this.notify(hold.subject_user_id,a,'privacy.hold.released',hold.id);return result;}
      const kinds:Record<string,string>={users:'user',orders:'order','support-threads':'support',cases:'case',audit:'audit',blacklist:'blacklist',portfolio:'portfolio',contractors:'contractor','privacy-requests':'privacy','monetization-configs':'monetization_config','price-versions':'price_version','categories':'category','push-campaigns':'push_campaign','referral-campaigns':'referral_campaign','moderation-dictionaries':'dictionary','ranking-configs':'ranking_config','promotions':'promotion','placement-policies':'placement_policy','verification-policies':'verification_policy','retention-policies':'retention_policy','country-controls':'country_control',verifications:'verification'};
      if(path==='/admin/analytics'&&method==='GET'){const days=q.days===undefined?7:Number(q.days);if(![7,30,90].includes(days))fail(400,'VALIDATION_ERROR','Выберите период 7, 30 или 90 дней');return productAnalytics(this.store,a.country,days);}
      if(path==='/admin/dashboard'&&method==='GET') {
        const days=q.days===undefined?7:Number(q.days);if(![7,30,90].includes(days))fail(400,'VALIDATION_ERROR','Выберите период 7, 30 или 90 дней');
        return operationsOverview(this.store,a.country,days);
      }
      if(path==='/admin/security-events'&&method==='GET') {
        const page=await this.page('security_event',a,q);
        return {...page,items:page.items.map(securityEventSummary)};
      }
      if(path==='/admin/jobs'&&method==='GET') {
        const records=(await Promise.all(['upload','privacy','outbox','webhook_inbox'].map(kind=>this.store.all(kind,a.country)))).flat()
          .filter(record=>record.kind!=='privacy'||record.type==='export');
        if(q.scheduled!==undefined&&!['true','false'].includes(q.scheduled))fail(400,'VALIDATION_ERROR','Проверьте фильтр расписания');
        const scheduled=records.filter(r=>['pending','retry','requested','processing'].includes(r.status)&&Date.parse(r.next_attempt_at)>Date.now());
        const page=await this.list((q.scheduled==='true'?scheduled:records).map(operationJob),q);
        return {...page,counts:{scheduled:scheduled.length,queued:records.filter(r=>['requested','pending','retry'].includes(r.status)||r.status==='processing'&&!r.lease_expires_at).length,
          running:records.filter(r=>['scanning','sending'].includes(r.status)||r.status==='processing'&&r.lease_expires_at).length,
          failed:records.filter(r=>['failed','dead_letter'].includes(r.status)||r.failure_code).length},
          providers:{billing:[...this.providers.billing.keys()],rewarded:[...this.providers.rewards.keys()],banners:[...this.providers.banners.keys()],
            push_configured:!!this.providers.push,scanner_configured:!!this.providers.scanner,pdf_sanitizer_configured:!!this.providers.pdfSanitizer}};
      }
      const jobDetail=path.match(/^\/admin\/jobs\/([^/]+)$/);
      if(jobDetail&&method==='GET'){
        const job=await this.store.get(jobDetail[1]);
        if(!job||job.country!==a.country||!['upload','privacy','outbox','webhook_inbox'].includes(job.kind)||job.kind==='privacy'&&job.type!=='export')fail(404,'NOT_FOUND','Задача не найдена');
        return operationJob(job!);
      }
      const retryJob=path.match(/^\/admin\/jobs\/([^/]+)\/retry$/);
      if(retryJob&&method==='POST') {
        const r=await this.store.get(retryJob[1]);if(!r||r.country!==a.country||!['upload','privacy','outbox'].includes(r.kind))fail(404,'NOT_FOUND','Задача не найдена');
        this.version(r!,b);const reason=text(b,'reason',10,1000);
        let updates:any;
        if(r!.kind==='privacy'&&r!.type==='export'&&r!.status==='failed')updates={status:'requested',attempts:0,lease_expires_at:null};
        else if(r!.kind==='outbox'&&['dead_letter','retry'].includes(r!.status)) {
          if(!this.providers.push)fail(503,'PROVIDER_UNAVAILABLE','Push-провайдер не подключён');
          updates={status:'pending',attempts:0};
        }else if(r!.kind==='upload'&&['processing','rejected'].includes(r!.status)&&['SCANNER_UNAVAILABLE','PDF_SANITIZER_UNAVAILABLE','FILE_PROCESSING_UNAVAILABLE'].includes(r!.failure_code)) {
          if(r!.scan_lease_until>new Date().toISOString())fail(409,'STATE_CONFLICT','Задача уже выполняется');
          if(!this.providers.scanner)fail(503,'SCANNER_UNAVAILABLE','Проверка файлов не подключена');
          if(r!.mime==='application/pdf'&&!this.providers.pdfSanitizer)fail(503,'PDF_SANITIZER_UNAVAILABLE','Обработка PDF не подключена');
          updates={status:'processing',scan_attempts:0,scan_lease_until:null,scan_nonce:null};
        }else fail(409,'STATE_CONFLICT','Повтор для этого состояния не разрешён');
        const updated=await this.store.put({...r!,...updates,failure_code:null,next_attempt_at:new Date().toISOString(),version:r!.version+1});
        await this.audit(a,'job.retry_requested',r!.id,reason);return operationJob(updated);
      }
      if(path==='/admin/boost-grants/preview'&&method==='POST'){await this.staff(a,'promotion');return (await this.growth.previewAdminBoost(a.country,b)).preview;}
      if(path==='/admin/boost-grants'&&method==='POST'){await this.staff(a,'promotion');const reason=text(b,'reason',10,1000);const result=await this.growth.adminBoost(a.id,a.country,{...b,reason});await this.audit(a,'boost.admin_grant',result.id,reason);return result;}
      if(path==='/admin/boost-reports'&&method==='GET'){await this.staff(a,'promotion');return this.list(await this.store.all('boost',a.country),q);}
      if(path==='/admin/refund-requests'&&method==='GET')return this.page('refund_request',a,q);
      const adminRefund=path.match(/^\/admin\/refund-requests\/([^/]+)(?:\/(approve|reject|submit|reconcile))?$/);
      if(adminRefund){const r=await this.object(adminRefund[1],a,'refund_request');
        if(method==='GET'&&!adminRefund[2]){const payment=r.payment_id?await this.refunds.payment(r.payment_id,a.country):undefined;return {...r,balance:payment?await this.refunds.balance(payment,r.id):null};}
        if(method==='POST'&&adminRefund[2]){this.version(r,b);const reason=text(b,'reason',10,1000),result=await this.refunds.command(r,a.id,adminRefund[2],reason);await this.audit(a,'refund.'+adminRefund[2],r.id,reason);return result;}
      }
      if(path==='/admin/payment-transactions'&&method==='GET'){
        const result=await this.page('payment_transaction',a,q);
        return {...result,items:result.items.map((x:any)=>({id:x.id,owner:x.owner,country:x.country,created_at:x.created_at,provider:x.provider,transaction_id:x.transaction_id,amount_minor:x.amount_minor,currency:x.currency,state:x.state,benefit:x.benefit??'subscription',source_id:x.source_id??x.boost_id??null,original_payment_id:x.original_payment_id??null,refund_request_id:x.refund_request_id??null,operation:x.operation??null,cash_amount_minor:x.cash_amount_minor??null,legacy:x.operation===undefined}))};
      }
      if(path==='/admin/monetization-summary'&&method==='GET') {
        const now=new Date().toISOString();
        const counts=(await this.store.db.query<any>("SELECT COUNT(*) FILTER(WHERE kind='user' AND data->>'status'='active' AND COALESCE(jsonb_array_length(data->'staff_permissions'),0)=0) AS users,COUNT(*) FILTER(WHERE kind='grant' AND data->>'source'='subscription' AND data->>'valid_until'>$2) AS subscription_grants,COUNT(*) FILTER(WHERE kind='ad_session' AND data->>'status' IN ('pending','created','started')) AS pending_rewards FROM records WHERE country=$1",[a.country,now])).rows[0];
        const current=(await this.store.all('monetization_config',a.country)).filter(r=>r.status==='effective'&&(!r.payload.role||r.payload.role==='all')&&(!r.payload.platform||r.payload.platform==='all')).sort((x,y)=>String(y.published_at).localeCompare(String(x.published_at)))[0]??null;
        const prices=(await this.store.all('price_version',a.country)).filter(r=>r.status==='effective');
        return {country:a.country,current,prices,users:Number(counts.users),subscription_grants:Number(counts.subscription_grants),pending_rewards:Number(counts.pending_rewards),config_ttl_seconds:(await this.settings(a.country)).config_ttl_seconds,providers:{billing:[...this.providers.billing.keys()],rewarded:[...this.providers.rewards.keys()],banner:[...this.providers.banners.keys()]}};
      }
      if(path==='/admin/country-capabilities'&&method==='GET')return {country:a.country,items:await this.store.all('country_control',a.country),
        legal_documents:(await this.store.all('legal_document',a.country)).filter(r=>r.status==='published').map(r=>({id:r.id,type:r.type,locale:r.locale,version:r.version})),
        verification_policy:(await this.store.all('verification_policy',a.country)).filter(r=>r.status==='effective').map(r=>({id:r.id,version:r.version})),
        retention_policy:(await this.store.all('retention_policy',a.country)).filter(r=>r.status==='effective').map(r=>({id:r.id,version:r.version})),
        providers:{billing:[...this.providers.billing.keys()],rewarded:[...this.providers.rewards.keys()],banners:[...this.providers.banners.keys()],push_configured:!!this.providers.push},
        commercial_launch:'unverified',checkout_enabled:false};
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
      if(path==='/admin/brand-icons'&&method==='POST'){const reason=text(b,'reason',10,1000);const result=await this.branding.version(a.id,a.country,String(b.upload_id),b.crop);await this.audit(a,'brand.draft_created',result.id,reason);return result;}
      const brand=path.match(/^\/admin\/brand-icons\/([^/]+)\/(approve|generate)$/);
      if(brand&&method==='POST') {
        const r=await this.object(brand[1],a,'brand_icon');this.version(r,b);
        if(brand[2]==='approve') {
          if(r.status!=='draft')fail(409,'STATE_CONFLICT','Версия уже утверждена');if(r.owner===a.id)fail(403,'SECOND_APPROVAL_REQUIRED','Нужно второе подтверждение');const result=await this.store.put({...r,status:'approved',approved_by:a.id,version:r.version+1});await this.audit(a,'brand.approved',r.id,text(b,'reason',10,1000));return result;
        }
        const reason=text(b,'reason',10,1000);if(r.status==='generated')return r;const result=await this.branding.generate(r);await this.audit(a,'brand.generated',r.id,reason);return result;
      }
      if(path==='/admin/legal/documents'&&method==='GET')return {items:await this.store.all('legal_document',a.country)};
      if(path==='/admin/legal/documents'&&method==='POST') {
        const content=text(b,'content',50,100000);const documentType=text(b,'type',2,50);const r=this.record('legal_document',a,{type:documentType,locale:text(b,'locale',2,5),content,hash:digest(content),status:'draft',...(['terms','terms_of_use'].includes(documentType)?{minimum_age:18}:{})});await this.store.put(r);await this.audit(a,'legal.draft',r.id,text(b,'reason',5,1000));return r;
      }
      const legalPublish=path.match(/^\/admin\/legal\/documents\/([^/]+)\/publish$/);
      if(legalPublish&&method==='POST'){const r=await this.object(legalPublish[1],a,'legal_document');this.version(r,b);if(r.owner===a.id)fail(403,'SECOND_APPROVAL_REQUIRED','Нужно подтверждение другого уполномоченного сотрудника');const result=await this.store.put({...r,status:'published',published_at:new Date().toISOString(),version:r.version+1});await this.audit(a,'legal.published',r.id,text(b,'reason',5,1000));return result;}
      const vd=path.match(/^\/admin\/verifications\/([^/]+)\/decision$/);
      if(vd&&method==='POST') {
        const r=await this.object(vd[1],a,'verification');this.version(r,b);if(r.status!=='pending_review'||b.document_revision!==r.document_revision)fail(409,'STATE_CONFLICT','Ревизия документа изменилась');
        if(!['passed','rejected','expired'].includes(b.decision))fail(400,'VALIDATION_ERROR','Недопустимое решение');const reason=text(b,'reason',10,1000);
        const end=Date.parse(String(b.expires_at));if(b.decision==='passed'&&(!Number.isFinite(end)||end<=Date.now()))fail(400,'VALIDATION_ERROR','Нужен срок действующей проверки');
        const u=(await this.store.get(r.owner))!;await this.store.put({...u,verification:b.decision,version:u.version+1});
        const result=await this.store.put({...r,status:b.decision,expires_at:b.decision==='passed'?new Date(end).toISOString():null,reason,reviewer_id:a.id,decided_at:new Date().toISOString(),version:r.version+1});await this.audit(a,'verification.'+b.decision,r.id,reason);if(b.decision==='passed')await this.growth.qualify(r.owner,a.country,'executor_verified',r.id);await this.notify(r.owner,a,'verification.updated',r.id);return {...result,document_refs:undefined};
      }
      if(path==='/admin/users'&&method==='GET'){
        const page=await this.page('user',a,q,{endUserOnly:true,statuses:q.status?[String(q.status)]:undefined});
        return {...page,items:page.items.map(u=>({...safeUser(u),version:u.version,status:u.status}))};
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
      const userActivity=path.match(/^\/admin\/users\/([^/]+)\/(orders|cases|support-threads|decisions)$/);
      if(userActivity&&method==='GET'){
        const user=await this.object(userActivity[1],a,'user'),relation=userActivity[2];
        const scoped={...q,_subject:user.id,_relation:relation};
        if(relation==='orders'){
          const page=await this.page('order',a,scoped,{participant:user.id,statuses:q.status?[String(q.status)]:undefined});
          return {...page,items:page.items.map(r=>({id:r.id,title:r.title,status:r.status,currency:r.currency,
            budget_amount:r.budget_amount,agreed_amount:r.agreed_amount,created_at:r.created_at,updated_at:r.updated_at,
            role:r.owner===user.id?'customer':'executor'}))};
        }
        if(relation==='cases'){
          await this.staff(a,'moderator');const page=await this.page('case',a,scoped,{caseActor:user.id});
          return {...page,items:page.items.map(r=>({id:r.id,status:r.status,reason_code:r.reason_code,created_at:r.created_at,updated_at:r.updated_at}))};
        }
        if(relation==='support-threads'){
          await this.staff(a,'support');const page=await this.page('support',a,scoped,{owner:user.id});
          return {...page,items:page.items.map(r=>({id:r.id,status:r.status,subject:r.subject,created_at:r.created_at,updated_at:r.updated_at}))};
        }
        await this.staff(a,'auditor');const limit=this.pageLimit(q),after=await this.cursor(scoped);
        const pivot=after?await this.store.get(after):undefined;
        if(after&&(!pivot||pivot.kind!=='audit'||pivot.country!==a.country))fail(400,'VALIDATION_ERROR','История изменилась. Обновите страницу',{restart_required:true});
        const rows=await accountDecisions(this.store,a.country,user.id,limit+1,pivot),batch=rows.slice(0,limit);
        return {items:batch,meta:{next_cursor:rows.length>limit?await this.nextCursor(batch.at(-1)!.id,scoped):null}};
      }
      const userDetail=path.match(/^\/admin\/users\/([^/]+)$/);
      const securityEvents=path.match(/^\/admin\/users\/([^/]+)\/security-events$/);
      if(securityEvents&&method==='GET') {
        await this.staff(a,'security');const u=await this.object(securityEvents[1],a,'user');const reason=text(q,'reason',10,1000);
        await this.audit(a,'security.events_read',u.id,reason);const page=await this.page('security_event',a,{...q,_subject:u.id},{owner:u.id});return {...page,items:page.items.map(securityEventSummary)};
      }
      if(userDetail&&method==='GET'){
        const u=await this.object(userDetail[1],a,'user');const result:any={...safeUser(u),status:u.status,version:u.version};
        if(q.include_phone==='true'){await this.staff(a,'phone_view');const reason=text(q,'reason',10,1000);await this.audit(a,'user.phone_read',u.id,reason);result.phone=u.phone;result.phone_status='unverified';}
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
        if(method==='POST'){if(t.retention_minimized_at)fail(409,'STATE_CONFLICT','Данные обращения очищены. Создайте новое обращение');const r=this.record('support_note',a,{thread_id:t.id,text:text(b,'text',1,3000)});await this.store.put(r);await this.audit(a,'support.internal_note',t.id,'Добавлена внутренняя заметка');return r;}
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
          if(t.retention_minimized_at)fail(409,'STATE_CONFLICT','Данные обращения очищены. Создайте новое обращение');
          const states:Record<string,string>={assign:'assigned',resolve:'resolved',wait_user:'waiting_user',wait_support:'waiting_support',reopen:'assigned'};
          if(!states[b.command])fail(400,'VALIDATION_ERROR','Недопустимая команда');
          if(b.command!=='assign'&&t.assignee_id!==a.id)fail(403,'FORBIDDEN','Обращение не назначено вам');
          if(b.command==='reopen'&&t.status!=='resolved')fail(409,'STATE_CONFLICT','Обращение не закрыто');
          if(b.command==='resolve'&&b.reopen_until!==undefined&&(!Number.isFinite(Date.parse(b.reopen_until))||Date.parse(b.reopen_until)<=Date.now()))fail(400,'VALIDATION_ERROR','Проверьте срок повторного открытия');
          const result=await this.store.put({...t,status:states[b.command],assignee_id:a.id,...(b.command==='resolve'?{resolved_at:new Date().toISOString(),reopen_until:b.reopen_until?new Date(b.reopen_until).toISOString():null}:{}),version:t.version+1});await this.audit(a,'support.'+b.command,t.id,text(b,'reason',5,1000));return result;
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
      const pushTestAccess=path.match(/^\/admin\/users\/([^/]+)\/push-test-access$/);
      if(pushTestAccess&&method==='POST'){
        const u=await this.object(pushTestAccess[1],a,'user');this.version(u,b);const reason=text(b,'reason',10,1000);if(typeof b.enabled!=='boolean')fail(400,'VALIDATION_ERROR','Подтвердите разрешение теста');
        const until=Date.parse(String(b.until));if(b.enabled&&(!Number.isFinite(until)||until<=Date.now()||until>Date.now()+30*86400000))fail(400,'VALIDATION_ERROR','Задайте конечный срок в пределах 30 дней');
        await this.store.put({...u,push_test_allowed:b.enabled,push_test_until:b.enabled?new Date(until).toISOString():null,version:u.version+1});await this.audit(a,'push.test_access_changed',u.id,reason);return {id:u.id,enabled:b.enabled,until:b.enabled?new Date(until).toISOString():null};
      }
      if(path==='/admin/push-test-accounts'&&method==='GET')return {can_manage:a.user.staff_permissions?.includes('administrator')===true,items:(await this.store.all('user',a.country)).filter(u=>u.push_test_allowed===true&&u.push_test_until>new Date().toISOString()&&u.status==='active').map(u=>({id:u.id,display_name:u.display_name,locale:u.locale??'ru'}))};
      const pushCommand=path.match(/^\/admin\/push-campaigns\/([^/]+)(?:\/(validate|preview|test|schedule|publish|cancel|stop))?$/);
      if(pushCommand){
        const c=await this.object(pushCommand[1],a,'push_campaign'),command=pushCommand[2];
        if(method==='GET'&&!command){const counts=(await db.query<{status:string,count:string}>("SELECT data->>'status' AS status,count(*)::text FROM records WHERE kind='outbox' AND country=$1 AND data->>'campaign_id'=$2 GROUP BY 1",[a.country,c.id])).rows;return {...c,delivery_counts:Object.fromEntries(counts.map(r=>[r.status,Number(r.count)])),provider_configured:!!this.providers.push};}
        if(method==='PATCH'&&!command){this.version(c,b);if(c.status!=='draft')fail(409,'STATE_CONFLICT','Редактируется только черновик');const updated=await this.store.put({...c,title:text(b,'title',3,120),payload:normalizePushPayload(b.payload??{}),version:c.version+1});await this.audit(a,'push.draft_updated',c.id,text(b,'reason',10,1000));return updated;}
        if(method==='POST'&&command){
          this.version(c,b);const reason=text(b,'reason',10,1000);
          if(['cancel','stop'].includes(command)){if(!['draft','scheduled','sending'].includes(c.status))fail(409,'STATE_CONFLICT','Кампания уже завершена');const result=await cancelPushCampaign(this.store,c);await this.audit(a,'push.canceled',c.id,reason);return result;}
          if(c.status!=='draft')fail(409,'STATE_CONFLICT','Кампания уже запланирована или завершена');
          validatePushCampaign(c);if(command==='validate')return {valid:true};
          if(command==='preview'){const preview=await pushPreview(this.store,c);const receipt=this.record('push_preview',a,{campaign_id:c.id,campaign_version:c.version,expires_at:new Date(Date.now()+600000).toISOString(),audience_count:preview.audience_count});await this.store.put(receipt);await this.audit(a,'push.preview',c.id,reason);return {...preview,preview_id:receipt.id,provider_configured:!!this.providers.push};}
          if(command==='test'){
            if(!Array.isArray(b.recipient_ids)||!b.recipient_ids.length||b.recipient_ids.length>5||new Set(b.recipient_ids).size!==b.recipient_ids.length)fail(400,'VALIDATION_ERROR','Выберите до 5 разрешённых тестовых аккаунтов');
            for(const id of b.recipient_ids){const u=await this.object(String(id),a,'user');if(u.push_test_allowed!==true||!u.push_test_until||u.push_test_until<=new Date().toISOString()||u.status!=='active')fail(403,'FORBIDDEN','Аккаунт не разрешён для тестовой отправки');}
            const test=testCampaign(c,a.id,b.recipient_ids);await this.store.put(test);await this.audit(a,'push.test_queued',test.id,reason);return {id:test.id,status:test.status,provider_configured:!!this.providers.push};
          }
          const preview=await this.object(String(b.preview_id),a,'push_preview');if(preview.campaign_id!==c.id||preview.campaign_version!==c.version||preview.expires_at<=new Date().toISOString())fail(409,'STATE_CONFLICT','Предпросмотр устарел');
          if(c.owner===a.id)fail(403,'SECOND_APPROVAL_REQUIRED','Нужно подтверждение другого сотрудника');
          if(Date.parse(c.payload.deadline_at)<=Date.now())fail(409,'STATE_CONFLICT','Дедлайн кампании истёк');
          const scheduled=await this.store.put({...c,status:'scheduled',scheduled_by:a.id,scheduled_at:new Date().toISOString(),preview_id:preview.id,version:c.version+1});await this.audit(a,'push.scheduled',c.id,reason);return scheduled;
        }
      }
      const configKinds=['monetization-configs','price-versions','categories','push-campaigns','referral-campaigns','moderation-dictionaries','ranking-configs','promotions','placement-policies','verification-policies','retention-policies','country-controls'];
      if(configKinds.includes(section)&&method==='POST'&&path.split('/').length===3) {
        if(section==='retention-policies')validateRetentionCategories(b.payload??{});
        if(section==='moderation-dictionaries'){try{b.payload=dictionaryPayload(b.payload);}catch(e:any){fail(400,'VALIDATION_ERROR',e.message);}}
        if(section==='categories'){
          const r=this.record('category',a,{title:text(b,'title',3,120),status:'draft'});let stable=r.id;
          if(b.payload?.category_id){const original=await this.object(String(b.payload.category_id),a,'category');stable=categoryId(original);r.legacy_id=original.legacy_id;}
          r.payload=categoryPayload(b.payload,a.country,stable);r.base_version_id=(await this.categories(a.country)).find(x=>x.id===stable)?.record_id??null;await this.store.put(r);await this.audit(a,'categories.draft',r.id,text(b,'reason',5,1000));return r;
        }
        const r=this.record(kinds[section],a,{title:text(b,'title',3,120),status:'draft',payload:section==='monetization-configs'?monetizationPayload(b.payload):section==='placement-policies'?placementPolicyPayload(b.payload):section==='ranking-configs'?rankingPayload(b.payload):section==='referral-campaigns'?referralPolicy(b.payload):section==='price-versions'?pricePayload(b.payload,a.country):section==='push-campaigns'?normalizePushPayload(b.payload??{}):section==='promotions'?normalizePromotionPayload(b.payload??{}):b.payload??{}});
        await this.store.put(r);await this.audit(a,section+'.draft',r.id,text(b,'reason',5,1000));return r;
      }
      const editMonetization=path.match(/^\/admin\/monetization-configs\/([^/]+)$/);
      if(editMonetization&&['GET','PATCH'].includes(method)){
        const r=await this.object(editMonetization[1],a,'monetization_config');if(method==='GET')return r;
        this.version(r,b);if(r.owner!==a.id||r.status!=='draft')fail(409,'STATE_CONFLICT','Изменять можно только собственный черновик монетизации');
        const result=await this.store.put({...r,title:text(b,'title',3,120),payload:monetizationPayload(b.payload),preview:undefined,version:r.version+1});await this.audit(a,'monetization.edited',r.id,text(b,'reason',10,1000));return result;
      }
      const editReferral=path.match(/^\/admin\/referral-campaigns\/([^/]+)$/);
      if(editReferral&&['GET','PATCH'].includes(method)){
        const r=await this.object(editReferral[1],a,'referral_campaign');
        if(method==='GET'){
          const attributions=(await this.store.all('referral_attribution',a.country)).filter(x=>x.campaign_id===r.id),rewards=(await this.store.all('referral_reward',a.country)).filter(x=>x.campaign_id===r.id),reservations=(await this.store.all('referral_reservation',a.country)).filter(x=>x.campaign_id===r.id);
          return {...r,metrics:{attributions:attributions.length,qualified:attributions.filter(x=>x.status==='qualified').length,issued:rewards.length,redeemed:rewards.filter(x=>x.status==='redeemed').length,reserved:reservations.filter(x=>x.status==='reserved').length,budget_used:reservations.length+rewards.filter(x=>!x.reservation_id).length}};
        }
        this.version(r,b);if(r.owner!==a.id||r.status!=='draft')fail(409,'STATE_CONFLICT','Создайте новый черновик кампании');
        const result=await this.store.put({...r,title:text(b,'title',3,120),payload:referralPolicy(b.payload),preview:undefined,version:r.version+1});await this.audit(a,'referrals.edited',r.id,text(b,'reason',5,1000));return result;
      }
      const editCategory=path.match(/^\/admin\/categories\/([^/]+)$/);
      if(editCategory&&['GET','PATCH'].includes(method)){
        const r=await this.object(editCategory[1],a,'category');if(method==='GET')return r;this.version(r,b);
        if(r.owner!==a.id||r.status!=='draft')fail(409,'STATE_CONFLICT','Создайте новую версию категории');
        if(b.payload?.category_id&&b.payload.category_id!==categoryId(r))fail(422,'VALIDATION_ERROR','Стабильный ID изменять нельзя');
        const result=await this.store.put({...r,title:text(b,'title',3,120),payload:categoryPayload(b.payload,a.country,categoryId(r)),preview:undefined,version:r.version+1});await this.audit(a,'categories.edited',r.id,text(b,'reason',5,1000));return result;
      }
      const editPlacement=path.match(/^\/admin\/placement-policies\/([^/]+)$/);
      if(editPlacement&&['GET','PATCH'].includes(method)){
        const r=await this.object(editPlacement[1],a,'placement_policy');if(method==='GET')return {...r,metrics:await placementPromises(this.store,a.country,r.payload.placement_id)};
        this.version(r,b);if(r.owner!==a.id||r.status!=='draft')fail(409,'STATE_CONFLICT','Создайте новую версию размещения');
        const result=await this.store.put({...r,title:text(b,'title',3,120),payload:placementPolicyPayload(b.payload),preview:undefined,version:r.version+1});await this.audit(a,'placements.edited',r.id,text(b,'reason',5,1000));return result;
      }
      const editRanking=path.match(/^\/admin\/ranking-configs\/([^/]+)$/);
      if(editRanking&&['GET','PATCH'].includes(method)){
        const r=await this.object(editRanking[1],a,'ranking_config');if(method==='GET')return r;
        this.version(r,b);if(r.owner!==a.id||r.status!=='draft')fail(409,'STATE_CONFLICT','Создайте новую версию рейтинга');
        const result=await this.store.put({...r,title:text(b,'title',3,120),payload:rankingPayload(b.payload),preview:undefined,version:r.version+1});await this.audit(a,'ranking.edited',r.id,text(b,'reason',5,1000));return result;
      }
      const editPrice=path.match(/^\/admin\/price-versions\/([^/]+)$/);
      if(editPrice&&['GET','PATCH'].includes(method)){
        const r=await this.object(editPrice[1],a,'price_version');if(method==='GET')return r;
        this.version(r,b);if(r.owner!==a.id||r.status!=='draft')fail(409,'STATE_CONFLICT','Создайте новую версию цены');
        const result=await this.store.put({...r,title:text(b,'title',3,120),payload:pricePayload(b.payload,a.country),preview:undefined,version:r.version+1});await this.audit(a,'prices.edited',r.id,text(b,'reason',5,1000));return result;
      }
      const editDocumentPolicy=path.match(/^\/admin\/(verification-policies|retention-policies)\/([^/]+)$/);
      if(editDocumentPolicy&&['GET','PATCH'].includes(method)){
        const r=await this.object(editDocumentPolicy[2],a,kinds[section]);if(method==='GET')return r;
        this.version(r,b);if(r.owner!==a.id||r.status!=='draft')fail(409,'STATE_CONFLICT','Создайте новый черновик политики');
        if(r.kind==='retention_policy')validateRetentionCategories(b.payload??{});
        const result=await this.store.put({...r,title:text(b,'title',3,120),payload:b.payload??{},preview:undefined,version:r.version+1});await this.audit(a,section+'.edited',r.id,text(b,'reason',5,1000));return result;
      }
      const editPromotion=path.match(/^\/admin\/promotions\/([^/]+)$/);
      if(editPromotion&&method==='GET')return this.object(editPromotion[1],a,'promotion');
      if(editPromotion&&method==='PATCH'){
        const r=await this.object(editPromotion[1],a,'promotion');this.version(r,b);
        if(r.status!=='draft'||r.owner!==a.id)fail(409,'STATE_CONFLICT','Создайте новую версию этого промо');
        const result=await this.store.put({...r,title:text(b,'title',3,120),payload:normalizePromotionPayload(b.payload??{}),preview:undefined,version:r.version+1});
        await this.audit(a,'promotions.edited',r.id,text(b,'reason',5,1000));return result;
      }
      const editDictionary=path.match(/^\/admin\/moderation-dictionaries\/([^/]+)$/);
      if(editDictionary&&['GET','PATCH'].includes(method)){
        const r=await this.object(editDictionary[1],a,'dictionary');if(method==='GET')return r;
        this.version(r,b);if(r.owner!==a.id||r.status!=='draft')fail(409,'STATE_CONFLICT','Создайте новый черновик словаря');
        let payload;try{payload=dictionaryPayload(b.payload);}catch(e:any){fail(400,'VALIDATION_ERROR',e.message);}
        const result=await this.store.put({...r,title:text(b,'title',3,120),payload,preview:undefined,version:r.version+1});await this.audit(a,'dictionary.edited',r.id,text(b,'reason',10,1000));return result;
      }
      const dictionaryDryRun=path.match(/^\/admin\/moderation-dictionaries\/([^/]+)\/dry-run$/);
      if(dictionaryDryRun&&method==='POST'){
        const d=await this.object(dictionaryDryRun[1],a,'dictionary');this.version(d,b);
        const sample=text(b,'text',1,10000),reason=text(b,'reason',10,1000);
        try{dictionaryPayload(d.payload);}catch(e:any){fail(400,'VALIDATION_ERROR',e.message);}
        if(!Object.hasOwn(TEXT_SURFACES,String(b.surface)))fail(400,'VALIDATION_ERROR','Неизвестная поверхность текста');
        const hits=d.payload.rules.filter((r:any)=>(!r.surfaces||r.surfaces.includes(b.surface))&&matchesRule(sample,r.value,r.type,d.payload.exceptions??[])).map((r:any)=>({rule_id:r.id??r.value,type:r.type,value:r.value}));
        await this.audit(a,'dictionary.dry_run',d.id,reason);return {dictionary_id:d.id,version:d.version,surface:b.surface,hits,matched:hits.length>0,mutated_content:false};
      }
      const securityDetail=path.match(/^\/admin\/security-events\/([^/]+)\/disclose$/);
      if(securityDetail&&method==='POST'){const r=await this.object(securityDetail[1],a,'security_event');const reason=text(b,'reason',10,1000);await this.audit(a,'security.event_disclosed',r.id,reason);return {...securityEventSummary(r),ip:r.ip??null,user_agent:r.user_agent??null};}
      const blacklistDetail=path.match(/^\/admin\/blacklist\/([^/]+)$/);
      if(blacklistDetail&&method==='GET'){const r=await this.object(blacklistDetail[1],a,'blacklist');return {id:r.id,user_id:r.user_id,case_id:r.case_id,status:r.status,scope:r.scope,reason:r.reason,ends_at:r.ends_at,created_at:r.created_at,version:r.version};}
      const dictionaryCommand=path.match(/^\/admin\/moderation-dictionaries\/([^/]+)\/(validate|preview|publish)$/);
      if(dictionaryCommand&&method==='POST') {
        const d=await this.object(dictionaryCommand[1],a,'dictionary');this.version(d,b);const reason=text(b,'reason',10,1000);try{dictionaryPayload(d.payload);}catch(e:any){fail(400,'VALIDATION_ERROR',e.message);}
        if(dictionaryCommand[2]!=='publish'){await this.audit(a,'dictionary.'+dictionaryCommand[2],d.id,reason);return {valid:true,version:d.version,rules:d.payload.rules.length,retroactive:false};}
        if(d.status!=='draft')fail(409,'STATE_CONFLICT','Публиковать можно только черновик словаря');
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
        if(!staffCase[2]&&method==='GET'){
          const target=await this.store.read(c.target_id),scope=c.target_scope??'public';
          await this.audit(a,'case.evidence_read',c.id,'Просмотр зафиксированного материала по делу');
          return {...c,target_context:target&&target.country===a.country?{version:target.version,kind:target.kind,status:target.status,scope,changed:c.target_content_hash?contentHash(targetSnapshot(target,scope))!==c.target_content_hash:false}:null};
        }
        if(staffCase[2]){
          if(method==='GET')return this.list((await this.store.all('case_message',a.country)).filter(m=>m.case_id===c.id),q);
          const reason=text(b,'reason',10,1000);const m=await this.store.put(this.record('case_message',a,{case_id:c.id,text:text(b,'text',1,3000),internal:false,upload_ids:[]}));
          await this.audit(a,'case.message_created',c.id,reason);await this.notify(c.owner,a,'case.message.created',c.id);return m;
        }
      }
      const caseDecision=path.match(/^\/admin\/cases\/([^/]+)\/(resolve|appeal-decision)$/);
      if(caseDecision&&method==='POST') {
        const peek=await this.store.read(caseDecision[1]);if(!peek||peek.kind!=='case'||peek.country!==a.country)fail(404,'NOT_FOUND','Дело не найдено');
        const target=await this.store.read(peek!.target_id);if(target?.country===a.country)await this.store.get(peek!.subject_user_id??target.owner);
        const c=await this.object(caseDecision[1],a,'case');this.version(c,b);
        if(caseDecision[2]==='appeal-decision'&&(!a.user.staff_permissions.includes('senior_moderator')||c.decision_actor===a.id||c.initial_decision_actor===a.id))fail(403,'FORBIDDEN','Нужен независимый старший модератор');
        if(caseDecision[2]==='appeal-decision'&&c.status!=='appealed'||caseDecision[2]==='resolve'&&['resolved','closed','dismissed','appealed'].includes(c.status))fail(409,'STATE_CONFLICT','Решение недоступно в текущем состоянии');
        const reason=text(b,'reason',10,1000);if(!['no_violation','content_removed','sanction_upheld','overturned'].includes(b.decision)||caseDecision[2]==='resolve'&&b.decision==='overturned'||caseDecision[2]==='appeal-decision'&&!['sanction_upheld','overturned'].includes(b.decision))fail(400,'VALIDATION_ERROR','Недопустимое решение');
        const effects=await resolveEffects(this.store,c,b.decision,b.expected_target_version);
        const r=await this.store.put({...c,status:'resolved',resolved_at:new Date().toISOString(),decision:b.decision,decision_actor:a.id,initial_decision_actor:c.initial_decision_actor??c.decision_actor??a.id,reason,effects,version:c.version+1});
        await this.store.put(this.record('case_decision',a,{case_id:c.id,decision:b.decision,target_version:effects.target_version,reason,status:'applied'}));
        if(c.reporter_private&&c.subject_user_id&&c.subject_user_id!==c.owner&&['content_removed','sanction_upheld'].includes(b.decision)){
          const notice=this.record('case',{id:c.subject_user_id,country:a.country},{subject_user_id:c.subject_user_id,source_private_case_id:c.id,target_type:c.target_type,target_id:c.target_id,target_scope:c.target_scope,target_snapshot:c.target_snapshot,target_content_hash:c.target_content_hash,target_version:c.target_version,previous_target_status:c.previous_target_status,reason_code:c.reason_code,description:b.public_reason===undefined?'Материал ограничен после проверки. Вы можете обратиться за объяснением и подать апелляцию.':text(b,'public_reason',10,3000),status:'resolved',resolved_at:new Date().toISOString(),decision:b.decision,decision_actor:a.id,initial_decision_actor:a.id,effects,upload_ids:[]});
          await this.store.put(notice);await this.notify(c.subject_user_id,a,'case.updated',notice.id);
        }
        if(c.source_private_case_id){const parent=await this.object(c.source_private_case_id,a,'case');const synced=await this.store.put({...parent,status:'resolved',resolved_at:new Date().toISOString(),decision:b.decision,decision_actor:a.id,reason,effects,version:parent.version+1});await this.notify(synced.owner,a,'case.updated',synced.id);}

        await this.audit(a,'case.'+b.decision,c.id,reason);await this.notify(c.owner,a,'case.updated',c.id);if(c.subject_user_id&&['hidden','restored'].includes(effects.target_action))await this.notify(c.subject_user_id,a,'content.moderated',c.target_id);if(c.subject_user_id&&c.subject_user_id!==c.owner&&!c.reporter_private)await this.notify(c.subject_user_id,a,'case.updated',c.id);return r;
      }
      const configurationCommand=path.match(/^\/admin\/([^/]+)\/([^/]+)\/(validate|preview|publish)$/);
      if(configurationCommand&&configKinds.includes(section)&&method==='POST') {
        const r=await this.object(configurationCommand[2],a,kinds[section]);
        if(configurationCommand[3]==='preview'){this.version(r,b);const reason=text(b,'reason',10,1000);const preview=await this.configuration.preview(r);await this.audit(a,'configuration.preview',r.id,reason);return preview;}
        if(configurationCommand[3]==='validate'){if(['monetization_config','verification_policy','retention_policy','price_version','category','referral_campaign','ranking_config','placement_policy'].includes(r.kind))this.version(r,b);const result=await this.configuration.validate(r);if(r.kind==='price_version')await this.audit(a,'prices.validated',r.id,text(b,'reason',10,1000));return result;}
        const result=await this.configuration.publish(r,a.id,b.expected_version);await this.audit(a,section+'.published',r.id,text(b,'reason',10,1000));return result;
      }
      const configurationStop=path.match(/^\/admin\/([^/]+)\/([^/]+)\/(stop|cancel|rollback)$/);
      if(configurationStop&&configKinds.includes(section)&&method==='POST') {
        if(section==='categories')await this.store.db.query('SELECT pg_advisory_xact_lock(hashtextextended($1,0))',['category-publish:'+a.country]);
        const r=await this.object(configurationStop[2],a,kinds[section]);this.version(r,b);const reason=text(b,'reason',10,1000);
        if(r.kind==='category'&&configurationStop[3]!=='rollback'&&(await this.categories(a.country)).some(child=>child.payload.parent_id===categoryId(r)))fail(409,'CATEGORY_HAS_CHILDREN','Сначала перенесите или архивируйте дочерние категории');
        if(r.kind==='country_control'&&configurationStop[3]!=='rollback')fail(409,'SECOND_APPROVAL_REQUIRED','Для изменения состояния страны опубликуйте новый черновик с независимым подтверждением');
        if(configurationStop[3]==='rollback'){const draft=this.record(r.kind,a,{title:r.title,payload:r.payload,status:'draft',rollback_of:r.id,...(r.kind==='category'?{legacy_id:r.legacy_id,base_version_id:(await this.categories(a.country)).find(x=>x.id===categoryId(r))?.record_id??null}:{})});await this.store.put(draft);await this.audit(a,section+'.rollback_draft',draft.id,reason);return draft;}
        if(r.kind==='placement_policy'&&r.status==='effective'){
          await this.store.db.query('SELECT pg_advisory_xact_lock(hashtextextended($1,0))',['boost-capacity:'+a.country+':'+r.payload.placement_id]);
          if((await placementPromises(this.store,a.country,r.payload.placement_id)).promised_peak>0)fail(409,'PLACEMENT_PROMISES_ACTIVE','Сначала завершите действующие размещения и резервы');
        }
        const result=await this.store.put({...r,status:'stopped',version:r.version+1});await this.audit(a,section+'.stopped',r.id,reason);return result;
      }
      fail(404,'NOT_FOUND','Команда ещё не реализована');
    }
    fail(404,'NOT_FOUND','Маршрут не найден');
  }
  private async reauth(a:Actor,b:any) {
    const c=(await this.store.db.query<any>('SELECT password_hash FROM credentials WHERE user_id=$1',[a.id])).rows[0];
    if(!c||!await verify(c.password_hash,String(b.current_password??'')))fail(401,'REAUTH_REQUIRED','Подтвердите текущий пароль');
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
  private async page(kind:string,a:Actor,q:any,options:{member?:string;subjectUser?:string;owner?:string;recipient?:string;boostBucket?:string;inviteState?:string;caseActor?:string;caseBucket?:string;participant?:string;executor?:string;statuses?:string[];publicActor?:string;endUserOnly?:boolean}={}) {
    const limit=this.pageLimit(q),after=await this.cursor(q);
    const filters:any={};
    if(kind==='contractor'&&options.publicActor){
      if(q.work_mode!==undefined&&!['onsite','workshop','remote','hybrid'].includes(q.work_mode))fail(400,'VALIDATION_ERROR','Проверьте формат услуги');
      if(q.verified_only!==undefined&&!['true','false'].includes(q.verified_only))fail(400,'VALIDATION_ERROR','Проверьте фильтр документов');
      const amount=(key:string)=>{if(q[key]===undefined)return undefined;if(!/^\d+$/.test(String(q[key]))||!Number.isSafeInteger(Number(q[key])))fail(400,'VALIDATION_ERROR','Проверьте диапазон цены');return Number(q[key]);};
      filters.priceMin=amount('price_min');filters.priceMax=amount('price_max');
      if(filters.priceMin!==undefined&&filters.priceMax!==undefined&&filters.priceMin>filters.priceMax)fail(400,'VALIDATION_ERROR','Проверьте диапазон цены');
      if(q.rating_min!==undefined){if(!/^\d(?:\.\d+)?$/.test(String(q.rating_min))||Number(q.rating_min)>5)fail(400,'VALIDATION_ERROR','Проверьте рейтинг');filters.ratingMin=Number(q.rating_min);}
      filters.workMode=q.work_mode;
    }
    const selected=await this.store.select(kind,a.country,{...options,...filters,limit:limit+1,after,city:filters.workMode==='remote'?undefined:q.city,category:q.category_id,search:q.q,sourceId:q.source_id});
    const batch=selected.slice(0,limit);
    const items:RecordData[]=options.publicActor&&kind==='contractor'?await contractorPresentation(this.store,a.country,batch):batch.map(x=>options.publicActor&&kind==='order'?{...publicContent(x),exact_address:undefined}:x);
    return {items,meta:{next_cursor:selected.length>limit?await this.nextCursor(items.at(-1)!.id,q):null}};
  }
  private async portfolioPage(records:RecordData[],q:any) {
    const sorted=records.filter(r=>(!q.category_id||r.category_id===q.category_id)&&(!q.q||[r.title,r.description].join(' ').toLowerCase().includes(String(q.q).toLowerCase()))).sort((x,y)=>(x.position??0)-(y.position??0)||x.id.localeCompare(y.id));
    const scoped={...q,_portfolio_order:digest(JSON.stringify(sorted.map(r=>[r.id,r.position??0,r.published_version??r.version])))};
    const after=await this.cursor(scoped),start=after?sorted.findIndex(r=>r.id===after)+1:0,limit=this.pageLimit(q),batch=sorted.slice(start,start+limit);
    return {items:batch,meta:{next_cursor:start+batch.length<sorted.length?await this.nextCursor(batch.at(-1)!.id,scoped):null}};
  }
  private async list(items:any[],q:any) {
    const limit=this.pageLimit(q),after=await this.cursor(q);
    const filtered=items.filter(x=>(!after||x.id>after)&&(!q.status||x.status===q.status)&&(!q.product_type||x.payload?.product_type===q.product_type)&&(!q.order_id||x.order_id===q.order_id)&&(!q.city||x.city===q.city)&&(!q.category_id||x.category_id===q.category_id)&&(!q.q||[x.id,x.title,x.display_name,x.subject,x.action,x.reason,x.type,x.event,x.payload?.product_id,x.payload?.provider].filter(Boolean).join(' ').toLowerCase().includes(String(q.q).toLowerCase()))).sort((a,b)=>a.id.localeCompare(b.id));
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
      const hidden=['hidden','rejected'].includes(m.moderation_status)||m.moderation_status==='quarantined'&&m.owner!==a.id;
      return {...m,...(m.tombstone||hidden?{text:'',upload_ids:[]}:{}),hidden,delivery_state:m.moderation_status==='quarantined'?'quarantined':read?'read':delivered?'delivered':'sent'};
      };
      const visible=all.filter(m=>!['quarantined','hidden','rejected'].includes(m.moderation_status)||m.owner===a.id);
      const selected=q.after_sequence!==undefined?visible.filter(m=>m.sequence>Number(q.after_sequence)).slice(0,100):visible.filter(m=>q.before_sequence===undefined||m.sequence<Number(q.before_sequence)).slice(-100);
      const updates=q.updated_since?all.filter(m=>m.edited_at&&m.edited_at>=q.updated_since):[];
      return {items:selected.map(render),updates:updates.slice(0,100).map(render),meta:{server_time:watermark,updates_truncated:updates.length>100,has_more:selected.length>0&&visible.some(m=>m.sequence<selected[0].sequence)}};
    }
    if(method!=='POST')fail(404,'NOT_FOUND','Маршрут не найден');
    if(c.retention_minimized_at)fail(409,'STATE_CONFLICT','Данные обращения очищены. Создайте новое обращение');
    if(['closed','frozen','restricted'].includes(c.status))fail(409,'STATE_CONFLICT','Чат закрыт для новых сообщений');
    if(c.kind==='support'&&c.status==='resolved'&&(!c.reopen_until||c.reopen_until<=new Date().toISOString()))fail(409,'STATE_CONFLICT','Обращение закрыто. Можно создать новое.');
    if(c.kind==='conversation') {
      for(const other of c.members)if(other!==a.id&&await this.blocked(a,other))fail(403,'PAIR_BLOCKED','Прямой контакт ограничен. Поддержка доступна.');
      if(c.status==='open'){const offer=c.offer_id?await this.store.get(c.offer_id):undefined;if(offer&&offerExpired(offer,(await readSettings(this.store,a.country)).offer_expiry_hours))fail(409,'OFFER_EXPIRED','Срок отклика истёк');const o=await this.object(c.order_id,a,'order');if(o.status!=='open')fail(409,'STATE_CONFLICT','Заказ закрыт');await this.entitlement(a,'search_full');}
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
  async deliverOutbox(now=new Date()) {
    if(!this.providers.push)return {sent:0,blocked:'push_provider_unavailable'};
    const pending=await this.exclusive(async()=>{
      const result=await this.store.db.query<{data:RecordData}>("SELECT data FROM records WHERE kind='outbox' AND ((data->>'status' IN('pending','retry') AND (data->>'next_attempt_at' IS NULL OR data->>'next_attempt_at'<=$1)) OR (data->>'status'='processing' AND data->>'lease_expires_at'<=$1)) ORDER BY data->>'created_at',id LIMIT 20",[now.toISOString()]);return result.rows.map(r=>r.data);
    });
    let sent=0;
    for(const entry of pending){
      const delivery=await this.exclusive(async()=>{
        await this.store.db.exec('BEGIN');try{
          await this.store.db.query('SELECT pg_advisory_xact_lock(hashtextextended($1,0))',['push-recipient:'+entry.recipient_id]);
          const claim=async()=>{
            const current=await this.store.get(entry.id);if(!current||!(['pending','retry'].includes(current.status)||current.status==='processing'&&current.lease_expires_at<=now.toISOString()))return;
            const update=async(status:string,extra:any={})=>this.store.put({...current,status,...extra,version:current.version+1});
            const user=await this.store.get(current.recipient_id);
            if(!user||user.country!==entry.country||user.status==='deleted'){await update('suppressed');return;}
            const preference=current.type.startsWith('message.')?'chat':current.type.startsWith('marketing.')?'marketing':'service';
            if(user.notification_preferences?.[preference]===false||preference==='marketing'&&user.notification_preferences?.marketing!==true){await update('suppressed');return;}
            let message:any={event_id:current.event_id,title:'JOBA',body:'Новое событие в приложении'};
            if(current.campaign_id){const result=await claimCampaignMessage(this.store,current,user,now);if(result.stop){await update(result.stop);return;}if(result.retry){await update('retry',{next_attempt_at:result.retry});return;}message=result.message;}
            const quiet=user.notification_preferences?.quiet_hours;
            if(quiet){const clock=new Intl.DateTimeFormat('en-GB',{timeZone:quiet.time_zone,hour:'2-digit',minute:'2-digit',hour12:false}).format(now);const within=quiet.start<quiet.end?clock>=quiet.start&&clock<quiet.end:clock>=quiet.start||clock<quiet.end;if(within){await update('retry',{next_attempt_at:new Date(now.getTime()+60000).toISOString()});return;}}
            const tokens=(await this.store.db.query<{data:RecordData}>(`SELECT p.data FROM records p WHERE p.kind='push_token' AND p.country=$1 AND p.owner=$2 AND p.data->>'status'='active' AND EXISTS(SELECT 1 FROM tokens t WHERE t.family::text=p.data->>'session_family' AND t.user_id::text=p.owner AND t.country=p.country AND t.kind='refresh' AND t.revoked=false AND t.used=false AND t.expires_at>$3::timestamptz)`,[entry.country,user.id,now.toISOString()])).rows.map(r=>r.data);
            if(!tokens.length){await update('waiting_token');return;}
            const lease=randomUUID();await update('processing',{lease_id:lease,lease_expires_at:new Date(now.getTime()+60000).toISOString(),claimed_at:now.toISOString()});return {current,tokens,message,lease};
          };
          const result=await claim();await this.store.db.exec('COMMIT');return result;
        }catch(e){await this.store.db.exec('ROLLBACK');throw e;}
      });
      if(!delivery)continue;
      try{
        for(const token of delivery.tokens){
          if((delivery.current.accepted_tokens??[]).includes(token.id))continue;
          const live=await this.exclusive(async()=>{const r=await this.store.get(entry.id);if(r?.status!=='processing'||r.lease_id!==delivery.lease)return false;const checkedAt=new Date(Math.max(Date.now(),now.getTime()));const user=await this.store.get(r.recipient_id);const decision=r.campaign_id&&user?await claimCampaignMessage(this.store,r,user,checkedAt):undefined;const stop=!user||user.status==='deleted'?'suppressed':decision?.stop;if(stop){await this.store.put({...r,status:stop,lease_expires_at:null,version:r.version+1});return false;}await this.store.put({...r,lease_expires_at:new Date(checkedAt.getTime()+60000).toISOString(),version:r.version+1});return true;});
          if(!live)break;
          const result=await Promise.race([this.providers.push.send(token.token,delivery.message),new Promise<never>((_,reject)=>{const timer=setTimeout(()=>reject(Error('Push timeout')),10000);timer.unref();})]);
          await this.exclusive(async()=>{const r=await this.store.get(entry.id);if(r?.status!=='processing'||r.lease_id!==delivery.lease)return;await this.store.put({...r,accepted_tokens:[...new Set([...(r.accepted_tokens??[]),token.id])],provider_message_ids:[...(r.provider_message_ids??[]),result.provider_message_id],version:r.version+1});});
        }
        const completed=await this.exclusive(async()=>{const r=await this.store.get(entry.id);if(r?.status!=='processing'||r.lease_id!==delivery.lease)return false;await this.store.put({...r,status:'sent',sent_at:now.toISOString(),lease_expires_at:null,version:r.version+1});return true;});if(completed)sent++;
      }catch{
        await this.exclusive(async()=>{const r=await this.store.get(entry.id);if(r?.status!=='processing'||r.lease_id!==delivery.lease)return;const attempts=(r.attempts??0)+1;await this.store.put({...r,status:attempts>=5?'dead_letter':'retry',attempts,next_attempt_at:new Date(now.getTime()+Math.min(3600000,2**attempts*1000)).toISOString(),failure_code:'PUSH_PROVIDER_ERROR',lease_expires_at:null,version:r.version+1});});
      }
    }
    await this.exclusive(async()=>{for(const id of new Set(pending.map(e=>e.campaign_id).filter(Boolean))){const c=await this.store.get(id);if(c)await refreshPushCampaign(this.store,c,now);}});
    return {sent};
  }
  private async safeUploads(a:Actor,ids:any,purpose:string,max=10) {
    if(!Array.isArray(ids)||ids.length>max||new Set(ids).size!==ids.length)fail(400,'VALIDATION_ERROR','Проверьте список файлов');
    for(const id of ids){const u=await this.object(String(id),a,'upload',true);if(u.status!=='clean'||u.purpose!==purpose)fail(422,'UNSAFE_UPLOAD','Файл ещё не проверен или имеет другое назначение');}
    return ids;
  }
  private async authorizeFile(u:RecordData,a:Actor,q:any) {
    if(u.status!=='clean'||u.purpose==='export'&&u.expires_at<=new Date().toISOString())fail(404,'NOT_FOUND','Файл недоступен');
    if(u.purpose==='banner'){await this.staff(a,'campaign');return;}
    if(u.purpose==='brand'){if(!a.mfa||a.user.status!=='active'||!a.user.staff_permissions?.some((p:string)=>['content','brand_owner','release','administrator'].includes(p)))fail(403,'FORBIDDEN','Нужны служебные права брендинга и MFA');return;}
    if(u.purpose==='identity') {
      await this.staff(a,'identity_view');if(!q.reason||String(q.reason).length<10)fail(400,'VALIDATION_ERROR','Требуется служебная причина просмотра');await this.audit(a,'identity.sensitive_read',u.id,String(q.reason));
    }else if(u.owner!==a.id) {
      const related=(await this.store.all('message',a.country)).find(m=>!m.tombstone&&!['quarantined','hidden','rejected'].includes(m.moderation_status)&&m.upload_ids?.includes(u.id));const c=related?await this.store.get(related.thread_id):undefined;
      if(c?.members.includes(a.id))return;
      const supportMessage=(await this.store.all('support_message',a.country)).find(m=>!m.tombstone&&!['quarantined','hidden','rejected'].includes(m.moderation_status)&&m.upload_ids?.includes(u.id));
      const support=supportMessage?await this.store.get(supportMessage.thread_id):undefined;
      if(support?.owner===a.id)return;
      if(support?.assignee_id===a.id){await this.staff(a,'support');return;}
      const caseMessage=(await this.store.all('case_message',a.country)).find(m=>!m.internal&&m.upload_ids?.includes(u.id));
      const linkedCase=caseMessage?await this.store.get(caseMessage.case_id):(await this.store.all('case',a.country)).find(c=>[...c.upload_ids??[],...c.appeal_upload_ids??[],...c.target_snapshot?.upload_ids??[],...c.target_snapshot?.completion_upload_ids??[],...c.target_snapshot?.gallery_ids??[],...c.target_snapshot?.photos??[],...(c.target_snapshot?.avatar_id?[c.target_snapshot.avatar_id]:[])].includes(u.id));
      if(linkedCase){
        if(linkedCase.upload_ids?.includes(u.id)&&(linkedCase.owner===a.id||!linkedCase.reporter_private&&linkedCase.subject_user_id===a.id))return;
        if(a.mfa&&(a.user.staff_permissions?.includes('moderator')||a.user.staff_permissions?.includes('administrator'))){await this.staff(a,'moderator');const reason=text(q,'reason',10,1000);await this.audit(a,'case.evidence_read',u.id,reason);return;}
      }
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
        const order=(await this.store.all('order',a.country)).find(o=>o.upload_ids?.includes(u.id)||o.revision_upload_ids?.includes(u.id)||o.completion_upload_ids?.includes(u.id));
        if(order&&[order.owner,order.executor_id].includes(a.id))return;
        const owner=order?await this.store.get(order.owner):undefined;
        if(order?.upload_ids?.includes(u.id)&&owner?.status==='active'&&order?.expires_at>new Date().toISOString()&&order?.status==='open'&&!['quarantined','hidden','rejected'].includes(order.moderation_status)&&!await this.blocked(a,order.owner)){await this.entitlement(a,'search_full',true);return;}
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
    if(a.user.status!=='active'||a.user.active_role!=='executor'||!a.user.roles?.includes('executor'))return;
    const now=new Date().toISOString();
    const promotion=(await this.store.all('promotion',a.country)).filter(p=>{
      if(p.status!=='effective'||!(p.preview?.promo_end_exclusive>now)||p.payload.valid_from&&p.payload.valid_from>now)return false;
      const cutoff=p.payload.valid_from??p.published_at??p.created_at;
      return !p.payload.audience||p.payload.audience==='all'||(p.payload.audience==='new'?a.user.created_at>=cutoff:a.user.created_at<cutoff);
    }).sort((x,y)=>String(y.published_at??y.created_at).localeCompare(String(x.published_at??x.created_at))||y.id.localeCompare(x.id))[0];
    if(!promotion)return;
    const existing=(await this.store.all('grant',a.country)).find(g=>g.owner===a.id&&g.source_id===promotion.id);if(existing)return;
    const grant=this.record('grant',a,{source:'subscription_promotion',source_id:promotion.id,valid_until:promotion.preview.promo_end_exclusive,capabilities:['search_full','send_offer','publish_profile'],terms_snapshot:promotion.preview});
    await this.store.db.query('INSERT INTO records(id,kind,owner,country,version,data) VALUES($1,$2,$3,$4,$5,$6) ON CONFLICT DO NOTHING',[grant.id,grant.kind,grant.owner,grant.country,grant.version,JSON.stringify(grant)]);
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
      let state='clean',failure:string|null=null,clean:Buffer|undefined,preview:Buffer|undefined,previewId:string|undefined;
      try{
        const raw=await this.files.read(id);let verdict:string;
        try{verdict=await this.providers.scanner!.scan(raw,upload.mime);}catch{throw Error('SCANNER_UNAVAILABLE');}
        if(verdict==='infected')state='infected';else if(verdict!=='clean')throw Error('SCANNER_UNAVAILABLE');
        else if(upload.mime==='application/pdf'){
          if(!this.providers.pdfSanitizer)throw Error('PDF_SANITIZER_UNAVAILABLE');
          try{clean=await this.providers.pdfSanitizer.sanitize(raw);}catch{throw Error('PDF_POLICY_REJECTED');}
        }else{try{const image=sharp(raw,{limitInputPixels:25000000}),metadata=await image.metadata();if(metadata.format!==(upload.mime==='image/png'?'png':'jpeg'))throw Error('Unexpected image format');const bannerWidth=[5,6,7,8].includes(metadata.orientation??0)?metadata.height:metadata.width,bannerHeight=[5,6,7,8].includes(metadata.orientation??0)?metadata.width:metadata.height;if(upload.purpose==='banner'&&(!bannerWidth||!bannerHeight||bannerWidth<320||bannerHeight<50||bannerWidth>4096||bannerHeight>4096))throw Error('IMAGE_POLICY_REJECTED');if(upload.purpose==='brand'){if(!metadata.width||!metadata.height||metadata.width<1024||metadata.height<1024||metadata.width>4096||metadata.height>4096)throw Error('IMAGE_POLICY_REJECTED');clean=await image.rotate().png().toBuffer();}else clean=await image.rotate().jpeg().toBuffer();}catch{throw Error('IMAGE_POLICY_REJECTED');}}
        if(clean){if(upload.mime!=='application/pdf'){preview=upload.purpose==='brand'?await sharp(clean).resize({width:960,withoutEnlargement:true}).png().toBuffer():await sharp(clean).resize({width:960,withoutEnlargement:true}).jpeg({quality:80}).toBuffer();previewId=randomUUID();}}
      }catch(error:any){failure=['SCANNER_UNAVAILABLE','PDF_SANITIZER_UNAVAILABLE','PDF_POLICY_REJECTED','IMAGE_POLICY_REJECTED'].includes(error.message)?error.message:'FILE_PROCESSING_UNAVAILABLE';state=['SCANNER_UNAVAILABLE','PDF_SANITIZER_UNAVAILABLE','FILE_PROCESSING_UNAVAILABLE'].includes(failure!)?'processing':'rejected';}
      return this.exclusive(async()=>{
        await this.store.db.exec('BEGIN');try{
          await this.store.db.query('SELECT id FROM records WHERE id=$1 FOR UPDATE',[id]);
          const current=await this.store.get(id);
          if(!current||current.scan_nonce!==upload.scan_nonce||current.status!=='scanning'){await this.store.db.exec('COMMIT');return current??{id,status:'expired'};}
          // Persist derived bytes only while the claimed row is locked and still scanning.
          // A deletion that invalidated the claim must never have its files recreated.
          if(clean){try{await this.files.write(id,clean);if(previewId&&preview)await this.files.write(previewId,preview);}catch{if(previewId)await this.files.remove(previewId).catch(()=>{});previewId=undefined;clean=undefined;state='processing';failure='FILE_PROCESSING_UNAVAILABLE';}}
          const attempts=(current.scan_attempts??0)+1;
          const result=await this.store.put({...current,status:state==='processing'&&attempts>=5?'rejected':state,failure_code:failure,scan_attempts:attempts,next_attempt_at:state==='processing'?new Date(Date.now()+Math.min(3600000,2**attempts*1000)).toISOString():null,scan_lease_until:null,mime:clean&&current.mime!=='application/pdf'&&current.purpose!=='brand'?'image/jpeg':current.mime,stored_size:clean?.length??current.stored_size,...(previewId?{preview_file_id:previewId}:{}),version:current.version+1});
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
      const valid=await this.exclusive(async()=>{const current=await this.store.get(job.id),owner=await this.store.get(job.owner);return current?.status==='processing'&&current.version===job.version&&owner?.status!=='deleted';});
      if(!valid)return;
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
    const exportJobs:RecordData[]=[];let purgeFiles:string[]=[],pushRecipients:string[]=[];
    const run=async()=>{
      await this.store.db.exec('BEGIN');
      try {
        for(const r of await this.store.all('offer'))if(r.status==='active'&&offerExpired(r,(await readSettings(this.store,r.country)).offer_expiry_hours,now)){
          await this.store.put({...r,status:'expired',version:r.version+1});
          const chat=r.conversation_id?await this.store.get(r.conversation_id):undefined;
          if(chat?.status==='open')await this.store.put({...chat,status:'closed',version:chat.version+1});
        }
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
          if(!disputes.length&&!['quarantined','hidden','rejected'].includes(r.moderation_status))await this.store.put({...r,status:'published',published_at:now.toISOString(),version:r.version+1});
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
        for(const r of await this.store.all('privacy'))if(['requested','awaiting_retention_policy','scheduled','awaiting_resolution'].includes(r.status)&&r.type==='delete') {
          const policy=(await this.store.all('retention_policy',r.country)).find(x=>x.status==='effective');
          if(!policy){if(r.status==='requested')await this.store.put({...r,status:'awaiting_retention_policy',version:r.version+1});continue;}
          if(['requested','awaiting_retention_policy'].includes(r.status)){
            const grace=(await this.settings(r.country)).deletion_grace_hours;
            await this.store.put({...r,status:'scheduled',policy_id:policy.id,execute_after:new Date(now.getTime()+grace*3600000).toISOString(),version:r.version+1});continue;
          }
          if(r.execute_after>now.toISOString())continue;
          const work=await this.store.select('order',r.country,{participant:r.owner,statuses:['assigned','in_progress','completion_requested'],limit:1});
          if(work.length){if(r.status!=='awaiting_resolution')await this.store.put({...r,status:'awaiting_resolution',version:r.version+1});continue;}
          await this.store.put({...r,status:'erasing',version:r.version+1});
          const u=await this.store.get(r.owner);if(u)await this.store.put({id:u.id,kind:u.kind,owner:u.owner,country:u.country,created_at:u.created_at,phone:null,avatar_id:null,languages:[],roles:[],display_name:'Удалённый пользователь',city:'',status:'deleted',version:u.version+1},{skipContentCheck:true});
          await this.store.db.query('DELETE FROM credentials WHERE user_id=$1',[r.owner]);await this.store.db.query('UPDATE tokens SET revoked=true WHERE user_id=$1',[r.owner]);
          await this.store.db.query('DELETE FROM idempotency WHERE scope LIKE $1',[r.owner+':%']);
          for(const kind of ['contractor','portfolio','content_revision'])for(const {data:x} of (await this.store.db.query<{data:RecordData}>('SELECT data FROM records WHERE kind=$1 AND country=$2 AND owner=$3',[kind,r.country,r.owner])).rows)await anonymizeProfile(this.store,x);
          const plan=await deletionPlan(this.store,r.owner,r.country,policy,now,'account_removed');
          await this.store.db.query("UPDATE records SET version=version+1,data=jsonb_set(jsonb_set(data,'{status}',$3::jsonb),'{version}',to_jsonb(version+1)) WHERE kind='download_ticket' AND country=$1 AND owner=$2 AND data->>'status'='active'",[r.country,r.owner,JSON.stringify('revoked')]);
          await this.store.db.query("UPDATE records SET version=version+1,data=jsonb_build_object('id',id::text,'kind',kind,'owner',owner,'country',country,'created_at',data->'created_at','status','revoked','version',version+1) WHERE kind='push_token' AND country=$1 AND owner=$2",[r.country,r.owner]);
          await this.store.db.query("UPDATE records SET version=version+1,data=data||jsonb_build_object('status','canceled','failure_code','ACCOUNT_DELETED','lease_expires_at',NULL,'version',version+1) WHERE kind='privacy' AND country=$1 AND owner=$2 AND data->>'type'='export' AND data->>'status' IN ('requested','processing','failed')",[r.country,r.owner]);
          await this.store.put({...r,status:'limited_retention',reason:plan.missing_policy_categories.length?'Для части сохранённых данных нужны опубликованные сроки. Полное удаление ещё не завершено.':'Часть данных сохранена по категориям и основаниям. Полное удаление ещё не завершено.',policy_id:policy.id,retention_plan:plan,retention_review_at:undefined,completed_at:now.toISOString(),version:r.version+2});
        }
        for(const job of await this.store.all('privacy'))if(job.type==='delete'&&job.status==='limited_retention')await processDeletionCategories(this.store,job,(await this.store.all('retention_policy',job.country)).find(p=>p.status==='effective'),now);
        pushRecipients=await queuePushCampaigns(this.store,now);
        purgeFiles=await planFileRetention(this.store,now,async verification=>{await this.notify(verification.owner,{id:verification.owner,country:verification.country},'verification.expired',verification.id);});
        await this.store.db.query("DELETE FROM rate_limits WHERE window_start<CURRENT_TIMESTAMP-INTERVAL '1 day'");
        await this.store.db.exec('COMMIT');
      }catch(e){await this.store.db.exec('ROLLBACK');throw e;}
    };
    const promise=this.queue.then(run,run);this.queue=promise.catch(()=>{});await promise;
    for(const id of pushRecipients)this.events.emit(id);
    for(const id of purgeFiles){try{const pending=await this.exclusive(()=>this.store.get(id));if(pending?.status!=='purge_pending')continue;await this.files.remove(id);if(pending.preview_file_id)await this.files.remove(pending.preview_file_id);await this.exclusive(async()=>{const file=await this.store.get(id);if(file?.status==='purge_pending')await this.store.put(purgedUpload(file,now));});}catch{/* The pending marker is retried on the next maintenance run. */}}
    await this.exclusive(async()=>{await this.store.db.exec('BEGIN');try{await refreshWorkFileProgress(this.store,now);await this.store.db.exec('COMMIT');}catch(error){await this.store.db.exec('ROLLBACK');throw error;}});
    for(const job of exportJobs)await this.processExport(job,now);
  }
}
