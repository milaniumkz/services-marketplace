import {randomUUID,randomBytes,timingSafeEqual} from 'node:crypto';
import {HttpException} from '@nestjs/common';
import {Store,RecordData} from './store';
import {isStaffOwner} from './staff-access';
const fail=(message:string,status=422):never=>{throw new HttpException({error:{code:status===403?'FORBIDDEN':status===409?'STATE_CONFLICT':status===429?'REWARD_LIMIT':'VALIDATION_ERROR',message,retryable:false}},status);};
export const webAdNotice='Реклама Яндекса загружается с внешних серверов. Для показа, подбора (в том числе персонализации) и измерения рекламы Яндекс может обрабатывать IP-адрес, сведения об устройстве и браузере, рекламные идентификаторы и cookies; возможна трансграничная передача. Удостоверение личности, селфи, телефон, переписку и платёжные данные JOBA не передаёт рекламной сети в параметрах интеграции. Согласие добровольное и отзывается на главной странице. Политика Яндекса: https://yandex.ru/legal/confidential/';
const defaults={version:0,enabled:false,rewarded_enabled:false,banner_id:'',mobile_rewarded_id:'',desktop_rewarded_id:'',reward_kind:'ad_free',reward_seconds:3600,daily_cap:5,cooldown_seconds:300};
export const webAdsConfig=async(store:Store)=>({...defaults,...(await store.all('web_ad_config','KZ'))[0]});
export async function adminWebAds(store:Store,a:{id:string;user:RecordData;mfa:boolean},method:string,b:any){
 if(!isStaffOwner(a.user)||!a.mfa||a.user.status!=='active')fail('Управление веб-рекламой доступно владельцу.',403);
 if(method==='GET')return webAdsConfig(store);
 if(method!=='PUT')fail('Действие не поддерживается.');
 await store.db.query('SELECT pg_advisory_xact_lock(hashtextextended($1,0))',['web_ads_config']);
 const old=await webAdsConfig(store);if(b.expected_version!==old.version)fail('Настройки уже изменились. Обновите страницу.',409);
 for(const key of ['enabled','rewarded_enabled'])if(typeof b[key]!=='boolean')fail('Укажите состояние рекламных показов.');
 for(const key of ['banner_id','mobile_rewarded_id','desktop_rewarded_id'])if(typeof b[key]!=='string'||!/^R-A-\d+-\d+$/.test(b[key]))fail('Укажите корректные веб-идентификаторы РСЯ (R-A).');
 if(new Set([b.banner_id,b.mobile_rewarded_id,b.desktop_rewarded_id]).size!==3)fail('Для баннера, мобильного и десктопного Rewarded нужны разные блоки.');
 if(b.reward_kind!=='ad_free')fail('Веб-награда не открывает платные функции; доступен режим без баннеров.');
 for(const [key,min,max] of [['reward_seconds',60,2592000],['daily_cap',1,100],['cooldown_seconds',0,86400]] as const)if(!Number.isSafeInteger(b[key])||b[key]<min||b[key]>max)fail('Проверьте срок награды, дневной лимит и паузу.');
 const now=new Date().toISOString(),r={id:old.id??randomUUID(),kind:'web_ad_config',country:'KZ',owner:a.id,created_at:old.created_at??now,version:old.version+1,enabled:b.enabled,rewarded_enabled:b.rewarded_enabled,banner_id:b.banner_id,mobile_rewarded_id:b.mobile_rewarded_id,desktop_rewarded_id:b.desktop_rewarded_id,reward_kind:'ad_free',reward_seconds:b.reward_seconds,daily_cap:b.daily_cap,cooldown_seconds:b.cooldown_seconds,updated_at:now};
 await store.put(r);await store.put({id:randomUUID(),kind:'audit',country:'KZ',owner:a.id,created_at:now,version:1,actor_id:a.id,action:'web_ads.updated',target_id:r.id});return r;
}
export async function userWebAds(store:Store,a:{id:string;country:string},method:string,path:string,b:any){
 if(method!=='GET')await store.db.query('SELECT pg_advisory_xact_lock(hashtextextended($1,0))',['web_ads_user:'+a.id]);
 const config=await webAdsConfig(store),now=new Date(),consent=(await store.db.query<{data:RecordData}>("SELECT data FROM records WHERE kind='web_ad_consent' AND country=$1 AND owner=$2 ORDER BY COALESCE((data->>'sequence')::int,0) DESC LIMIT 1",[a.country,a.id])).rows[0]?.data;
 if(path==='/me/web-ads'&&method==='GET'){
  const grants=(await store.db.query<{data:RecordData}>("SELECT data FROM records WHERE kind='web_ad_grant' AND country=$1 AND owner=$2 AND data->>'valid_until'>$3 ORDER BY data->>'valid_until' DESC LIMIT 1",[a.country,a.id,now.toISOString()])).rows.map(x=>x.data);
  return {notice:webAdNotice,enabled:config.enabled,rewarded_enabled:config.enabled&&config.rewarded_enabled,banner_id:config.banner_id,mobile_rewarded_id:config.mobile_rewarded_id,desktop_rewarded_id:config.desktop_rewarded_id,reward_kind:config.reward_kind,reward_seconds:config.reward_seconds,consent:consent?.accepted===true,consent_recorded:!!consent,ad_free_until:grants[0]?.valid_until??null,server_time:now.toISOString()};
 }
 if(path==='/me/web-ads/consent'&&method==='POST'){
  if(typeof b.accepted!=='boolean')fail('Укажите согласие на рекламные показы.');
  const saved={id:randomUUID(),kind:'web_ad_consent',country:a.country,owner:a.id,created_at:now.toISOString(),version:1,sequence:(consent?.sequence??0)+1,accepted:b.accepted,updated_at:now.toISOString(),notice_version:1,notice_text:webAdNotice};await store.put(saved);
  await store.put({id:randomUUID(),kind:'audit',country:a.country,owner:a.id,created_at:now.toISOString(),version:1,actor_id:a.id,action:b.accepted?'web_ads.consent_accepted':'web_ads.consent_revoked',target_id:saved.id});return {accepted:saved.accepted};
 }
 if(path==='/me/web-ads/reward-sessions'&&method==='POST'){
  if(!config.enabled||!config.rewarded_enabled||consent?.accepted!==true)fail('Реклама недоступна или согласие на показы отключено.',403);
  if(!['desktop','touch'].includes(b.platform))fail('Не удалось определить платформу браузера.');
  const usage=(await store.db.query<{used:string;last:string}>("SELECT COUNT(*) FILTER(WHERE left(data->>'created_at',10)=$3)::text AS used,MAX(data->>'created_at') AS last FROM records WHERE kind='web_ad_session' AND country=$1 AND owner=$2",[a.country,a.id,now.toISOString().slice(0,10)])).rows[0];
  if(Number(usage.used)>=config.daily_cap||Date.parse(usage.last)>now.getTime()-config.cooldown_seconds*1000)fail('Достигнут лимит просмотров или ещё действует пауза. Повторите позже.',429);
  const r={id:randomUUID(),kind:'web_ad_session',country:a.country,owner:a.id,created_at:now.toISOString(),version:1,status:'pending',nonce:randomBytes(32).toString('base64url'),platform:b.platform,block_id:b.platform==='desktop'?config.desktop_rewarded_id:config.mobile_rewarded_id,reward_seconds:config.reward_seconds,reward_kind:'ad_free',expires_at:new Date(now.getTime()+15*60000).toISOString()};await store.put(r);return r;
 }
 const match=path.match(/^\/me\/web-ads\/reward-sessions\/([^/]+)\/outcome$/);
 if(match&&method==='POST'){
  const r=await store.get(match[1]);if(!r||r.kind!=='web_ad_session'||r.owner!==a.id||r.country!==a.country)fail('Просмотр не найден.',403);
  const token=Buffer.from(String(b.nonce??'')),expected=Buffer.from(r!.nonce);if(token.length!==expected.length||!timingSafeEqual(token,expected))fail('Не удалось подтвердить сессию просмотра.',403);
  if(typeof b.completed!=='boolean')fail('Укажите результат просмотра.');
  if(r!.status!=='pending')return {status:r!.status,ad_free_until:r!.ad_free_until??null};
  if(Date.parse(r!.expires_at)<=now.getTime())fail('Срок подтверждения просмотра истёк.',409);
  if(!b.completed){await store.put({...r!,status:'not_completed',version:r!.version+1});return {status:'not_completed'};}
  // Yandex Web exposes onRewarded(bool), not a signed server receipt. This low-trust
  // report only suppresses ads; it NEVER grants subscriptions, money or paid actions.
  const until=new Date(now.getTime()+r!.reward_seconds*1000).toISOString();
  await store.put({id:randomUUID(),kind:'web_ad_grant',country:a.country,owner:a.id,created_at:now.toISOString(),version:1,source_id:r!.id,valid_until:until,benefit:'ad_free',verification_method:'client_sdk_callback_reported'});
  await store.put({...r!,status:'granted',ad_free_until:until,version:r!.version+1,completed_at:now.toISOString(),verification_method:'client_sdk_callback_reported'});
  return {status:'granted',ad_free_until:until};
 }
 fail('Действие не поддерживается.');
}
