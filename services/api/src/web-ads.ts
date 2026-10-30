import {randomUUID,randomBytes,timingSafeEqual} from 'node:crypto';
import {HttpException} from '@nestjs/common';
import {Store,RecordData} from './store';
import {isStaffOwner} from './staff-access';
import {currentLegalDocuments,legalHashAccepted} from './legal-documents';
import {subscriptionRole} from './subscription-plans';
import {createPeriod,userPeriods,periodPlan} from './subscription-periods';
const fail=(message:string,status=422):never=>{throw new HttpException({error:{code:status===403?'FORBIDDEN':status===409?'STATE_CONFLICT':status===429?'REWARD_LIMIT':'VALIDATION_ERROR',message,retryable:false}},status);};
export const webAdNotice='Реклама Яндекса загружается с внешних серверов. Для показа, подбора (в том числе персонализации) и измерения рекламы Яндекс может обрабатывать IP-адрес, сведения об устройстве и браузере, рекламные идентификаторы и cookies; возможна трансграничная передача. Удостоверение личности, селфи, телефон, переписку и платёжные данные JOBA не передаёт рекламной сети в параметрах интеграции. Согласие добровольное и отзывается на главной странице. Политика Яндекса: https://yandex.ru/legal/confidential/';
const defaults={version:0,enabled:false,rewarded_enabled:false,banner_id:'',mobile_rewarded_id:'',desktop_rewarded_id:'',reward_kind:'subscription',reward_days:30,customer_views:5,standard_views:5,top100_views:5,daily_cap:30,cooldown_seconds:0};
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
 if(b.reward_kind!=='subscription'||b.reward_days!==30)fail('Рекламная подписка и Топ-100 выдаются на 30 дней.');
 for(const [key,min,max] of [['customer_views',1,1000],['standard_views',1,1000],['top100_views',1,1000],['daily_cap',1,1000],['cooldown_seconds',0,86400]] as const)if(!Number.isSafeInteger(b[key])||b[key]<min||b[key]>max)fail('Проверьте срок награды, дневной лимит и паузу.');
 const now=new Date().toISOString(),r={id:old.id??randomUUID(),kind:'web_ad_config',country:'KZ',owner:a.id,created_at:old.created_at??now,version:old.version+1,enabled:b.enabled,rewarded_enabled:b.rewarded_enabled,banner_id:b.banner_id,mobile_rewarded_id:b.mobile_rewarded_id,desktop_rewarded_id:b.desktop_rewarded_id,reward_kind:'subscription',reward_days:30,customer_views:b.customer_views,standard_views:b.standard_views,top100_views:b.top100_views,daily_cap:b.daily_cap,cooldown_seconds:b.cooldown_seconds,updated_at:now};
 await store.put(r);await store.put({id:randomUUID(),kind:'audit',country:'KZ',owner:a.id,created_at:now,version:1,actor_id:a.id,action:'web_ads.updated',target_id:r.id});return r;
}
export async function recordWebAdConsent(store:Store,a:{id:string;country:string},accepted:boolean,now:Date,source='web_ads'){
 await store.db.query('SELECT pg_advisory_xact_lock(hashtextextended($1,0))',['web_ads_user:'+a.id]);
 const account=await store.get(a.id);if(accepted&&account?.status!=='active')fail('Аккаунт недоступен.',403);
 const old=(await store.db.query<{data:RecordData}>("SELECT data FROM records WHERE kind='web_ad_consent' AND country=$1 AND owner=$2 ORDER BY COALESCE((data->>'sequence')::int,0) DESC LIMIT 1",[a.country,a.id])).rows[0]?.data;
 if(source==='privacy_settings'&&old?.accepted!==true)return;
 const saved={id:randomUUID(),kind:'web_ad_consent',country:a.country,owner:a.id,created_at:now.toISOString(),version:1,sequence:(old?.sequence??0)+1,accepted,updated_at:now.toISOString(),notice_version:1,notice_text:webAdNotice,source};await store.put(saved);
 if(source==='web_ads'){
  const previous=(await store.select('processing_consent',a.country,{owner:a.id,limit:1}))[0],doc=currentLegalDocuments(await store.all('legal_document',a.country),a.country,account?.locale??'ru').find(d=>['privacy','privacy_policy'].includes(d.type));
  if(accepted&&!doc)fail('Для показа рекламы нужна опубликованная политика конфиденциальности.',403);
  const values={marketing:previous?.marketing===true,optional_analytics:previous?.optional_analytics===true,ad_personalization:accepted};
  const processing={...previous,id:previous?.id??randomUUID(),kind:'processing_consent',country:a.country,owner:a.id,created_at:previous?.created_at??now.toISOString(),version:(previous?.version??0)+1,...values,document_id:doc?.id??previous?.document_id??null,document_hash:doc?.hash??previous?.document_hash??null,updated_at:now.toISOString()};
  await store.put(processing);await store.put({id:randomUUID(),kind:'processing_consent_event',country:a.country,owner:a.id,created_at:now.toISOString(),version:1,...values,document_id:processing.document_id,document_hash:processing.document_hash,source:'web_ads',web_ad_consent_id:saved.id});
 }
 await store.put({id:randomUUID(),kind:'audit',country:a.country,owner:a.id,created_at:now.toISOString(),version:1,actor_id:a.id,action:accepted?'web_ads.consent_accepted':'web_ads.consent_revoked',target_id:saved.id,source});
 return saved;
}
const targets=['customer','standard','top100'];
const requiredCount=(c:typeof defaults,target:string)=>target==='customer'?c.customer_views:target==='top100'?c.top100_views:c.standard_views;
const title=(target:string)=>target==='customer'?'Подписка заказчика':target==='standard'?'Стандарт исполнителя':'Топ-100 отдельно';
async function activeProgress(store:Store,a:{id:string;country:string},target:string){return (await store.db.query<{data:RecordData}>("SELECT data FROM records WHERE kind='web_ad_progress' AND country=$1 AND owner=$2 AND data->>'target'=$3 AND data->>'status' IN('collecting','ready') ORDER BY data->>'created_at' DESC LIMIT 1",[a.country,a.id,target])).rows[0]?.data;}
async function eligibility(store:Store,user:RecordData,target:string){
 const role=subscriptionRole(user);
 if(user.status!=='active')return 'Аккаунт ограничен.';
 if(!targets.includes(target)||(target==='customer')!==(role==='customer'))return 'Выберите услугу своей текущей роли.';
 if(user.verification!=='passed')return 'Сначала подтвердите личность: документ с двух сторон и селфи.';
 const control=(await store.all('country_control',user.country)).find(r=>r.status==='effective');if(control?.payload.stop_new_business)return 'Новые покупки в этой стране временно приостановлены.';
 if(target==='top100'){
  const grants=await store.select('grant',user.country,{owner:user.id,limit:1000}),live=grants.filter(g=>g.valid_until>new Date().toISOString());
  if(live.some(g=>g.plan==='premium'&&g.capabilities?.includes('top100')))return 'В Премиуме Топ-100 уже включён.';
  if(!live.some(g=>g.plan==='standard'&&g.capabilities?.includes('publish_profile')))return 'Для Топ-100 нужен действующий Стандарт.';
 }
 return null;
}
async function legalReady(store:Store,user:RecordData){
 const docs=currentLegalDocuments(await store.all('legal_document',user.country),user.country,user.locale??'ru').filter(d=>['privacy','privacy_policy','terms','terms_of_use'].includes(d.type));
 if(!docs.some(d=>['privacy','privacy_policy'].includes(d.type))||!docs.some(d=>['terms','terms_of_use'].includes(d.type)))fail('Условия подписки пока не опубликованы.',403);
 for(const d of docs){const c=(await store.db.query<{data:RecordData}>("SELECT data FROM records WHERE kind='consent' AND country=$1 AND owner=$2 AND data->>'document_id'=$3 ORDER BY (data->>'sequence')::int DESC LIMIT 1",[user.country,user.id,d.id])).rows[0]?.data;if(!c?.accepted||!legalHashAccepted(d,c.document_hash)||d.minimum_age===18&&!c.age_confirmed)fail('Примите опубликованные условия и политику конфиденциальности.',403);}
}
async function redeemProgress(store:Store,user:RecordData,progress:RecordData,now:Date){
 if(progress.status==='redeemed')return progress.receipt;
 if(progress.completed_views<progress.required_views)fail('Сначала завершите все необходимые просмотры.',409);
 await store.db.query('SELECT pg_advisory_xact_lock(hashtextextended($1,0))',['subscription-periods:'+user.country+':'+user.id]);
 const reason=await eligibility(store,user,progress.target);if(reason)return {status:'ready',message:reason,completed_views:progress.completed_views,required_views:progress.required_views,target:progress.target};
 try{await legalReady(store,user);}catch(e){if(e instanceof HttpException)return {status:'ready',message:'Обновите согласие с условиями перед активацией. Просмотры сохранены.',target:progress.target,completed_views:progress.completed_views,required_views:progress.required_views};throw e;}
 const periods=(await userPeriods(store,user)).filter(s=>['active','grace','canceled_at_period_end','scheduled'].includes(s.status)&&s.valid_until>now.toISOString());
 const compatible=periods.filter(s=>progress.target==='top100'?periodPlan(s)==='top100':!s.is_upgrade&&periodPlan(s)!=='top100');
 const start=compatible.reduce((v,s)=>Math.max(v,Date.parse(s.valid_until)),now.getTime());
 const subscription=await createPeriod(store,user,{plan:progress.target,seconds:30*86400,from:new Date(start).toISOString(),provider:'yandex_web_ads',price:{plan:progress.target,role:subscriptionRole(user),amount_minor:0,currency:({KZ:'KZT',KG:'KGS',RU:'RUB',BY:'BYN'} as Record<string,string>)[user.country],period:'days',duration_days:30,offer_kind:'rewarded',required_views:progress.required_views,verification_method:'client_sdk_callback_reported'}},now);
 await store.put({...subscription,is_ad_supported:true,web_ad_progress_id:progress.id,verification_method:'client_sdk_callback_reported',version:subscription.version+1});
 const grant=await store.get(subscription.grant_id);if(grant)await store.put({...grant,source:'web_ad_reward',verification_method:'client_sdk_callback_reported',version:grant.version+1});
 const receipt={status:'granted',target:progress.target,completed_views:progress.completed_views,required_views:progress.required_views,subscription_id:subscription.id,valid_from:subscription.valid_from,valid_until:subscription.valid_until,scheduled:subscription.status==='scheduled'};
 await store.put({...progress,status:'redeemed',receipt,redeemed_at:now.toISOString(),version:progress.version+1});
 await store.put({id:randomUUID(),kind:'web_ad_redemption',owner:user.id,country:user.country,created_at:now.toISOString(),version:1,progress_id:progress.id,subscription_id:subscription.id,target:progress.target,required_views:progress.required_views,verification_method:'client_sdk_callback_reported',cash_amount_minor:0});
 return receipt;
}
export async function userWebAds(store:Store,a:{id:string;country:string},method:string,path:string,b:any){
 if(method!=='GET')await store.db.query('SELECT pg_advisory_xact_lock(hashtextextended($1,0))',['web_ads_user:'+a.id]);
 const user=await store.get(a.id);if(!user||method!=='GET'&&!(path==='/me/web-ads/consent'&&b.accepted===false)&&user.status!=='active')fail('Аккаунт недоступен.',403);
 const config=await webAdsConfig(store),now=new Date(),consent=(await store.db.query<{data:RecordData}>("SELECT data FROM records WHERE kind='web_ad_consent' AND country=$1 AND owner=$2 ORDER BY COALESCE((data->>'sequence')::int,0) DESC LIMIT 1",[a.country,a.id])).rows[0]?.data;
 if(path==='/me/web-ads'&&method==='GET'){
  const available=subscriptionRole(user!)==='customer'?['customer']:['standard','top100'],offers=[];
  for(const target of available){const p=await activeProgress(store,a,target),reason=await eligibility(store,user!,target);offers.push({target,title:title(target),required_views:p?.required_views??requiredCount(config,target),completed_views:p?.completed_views??0,duration_days:30,ready:p?.status==='ready',eligible:!reason,reason});}
  return {notice:webAdNotice,enabled:config.enabled,rewarded_enabled:config.rewarded_enabled,banner_id:config.banner_id,mobile_rewarded_id:config.mobile_rewarded_id,desktop_rewarded_id:config.desktop_rewarded_id,reward_kind:'subscription',reward_days:30,offers,verification_status:user!.verification,role:subscriptionRole(user!),consent:consent?.accepted===true,consent_recorded:!!consent,server_time:now.toISOString()};
 }
 if(path==='/me/web-ads/consent'&&method==='POST'){if(typeof b.accepted!=='boolean')fail('Укажите согласие на рекламные показы.');await recordWebAdConsent(store,a,b.accepted,now);return {accepted:b.accepted};}
 if(path==='/me/web-ads/redeem'&&method==='POST'){
  const p=await activeProgress(store,a,String(b.target));if(!p)fail('Нет завершённого набора просмотров.',409);return redeemProgress(store,user!,p!,now);
 }
 if(path==='/me/web-ads/reward-sessions'&&method==='POST'){
  if(!config.rewarded_enabled||consent?.accepted!==true)fail('Реклама недоступна или согласие на показы отключено.',403);
  if(!['desktop','touch'].includes(b.platform))fail('Не удалось определить платформу браузера.');
  const target=String(b.target),reason=await eligibility(store,user!,target);if(reason)fail(reason,403);await legalReady(store,user!);
  let progress=await activeProgress(store,a,target);if(progress?.status==='ready')fail('Просмотры уже набраны. Нажмите «Активировать».',409);
  const pending=(await store.db.query<{data:RecordData}>("SELECT data FROM records WHERE kind='web_ad_session' AND country=$1 AND owner=$2 AND data->>'status'='pending' AND data->>'expires_at'>$3 ORDER BY data->>'created_at' DESC LIMIT 1",[a.country,a.id,now.toISOString()])).rows[0]?.data;
  if(pending){if(pending.target===target&&pending.platform===b.platform)return pending;fail('Завершите текущий просмотр перед выбором другой услуги.',409);}
  const usage=(await store.db.query<{used:string;last:string}>("SELECT COUNT(*) FILTER(WHERE left(data->>'created_at',10)=$3)::text AS used,MAX(data->>'created_at') AS last FROM records WHERE kind='web_ad_session' AND country=$1 AND owner=$2",[a.country,a.id,now.toISOString().slice(0,10)])).rows[0];
  if(Number(usage.used)>=config.daily_cap||Date.parse(usage.last)>now.getTime()-config.cooldown_seconds*1000)fail('Достигнут лимит просмотров или ещё действует пауза. Повторите позже.',429);
  if(!progress){progress={id:randomUUID(),kind:'web_ad_progress',country:a.country,owner:a.id,created_at:now.toISOString(),version:1,status:'collecting',target,required_views:requiredCount(config,target),completed_views:0,reward_days:30};await store.put(progress);}
  const session={id:randomUUID(),kind:'web_ad_session',country:a.country,owner:a.id,created_at:now.toISOString(),version:1,status:'pending',nonce:randomBytes(32).toString('base64url'),platform:b.platform,block_id:b.platform==='desktop'?config.desktop_rewarded_id:config.mobile_rewarded_id,progress_id:progress.id,target,required_views:progress.required_views,expires_at:new Date(now.getTime()+15*60000).toISOString()};await store.put(session);return session;
 }
 const match=path.match(/^\/me\/web-ads\/reward-sessions\/([^/]+)\/outcome$/);
 if(match&&method==='POST'){
  const r=await store.get(match[1]);if(!r||r.kind!=='web_ad_session'||r.owner!==a.id||r.country!==a.country)fail('Просмотр не найден.',403);
  const token=Buffer.from(String(b.nonce??'')),expected=Buffer.from(r!.nonce);if(token.length!==expected.length||!timingSafeEqual(token,expected))fail('Не удалось подтвердить сессию просмотра.',403);
  if(typeof b.completed!=='boolean')fail('Укажите результат просмотра.');if(r!.status!=='pending')return r!.receipt;
  if(Date.parse(r!.expires_at)<=now.getTime())fail('Срок подтверждения просмотра истёк.',409);
  if(!b.completed){const receipt={status:'not_completed',target:r!.target};await store.put({...r!,status:'not_completed',receipt,version:r!.version+1});return receipt;}
  const p=await store.get(r!.progress_id);if(!p||p.owner!==a.id||p.country!==a.country||p.kind!=='web_ad_progress'||p.status==='redeemed')fail('Набор просмотров уже завершён.',409);
  const original=p!;const updated:RecordData={...original,completed_views:original.completed_views+1,status:original.completed_views+1>=original.required_views?'ready':'collecting',version:original.version+1};await store.put(updated);
  const receipt=updated.status==='ready'?await redeemProgress(store,user!,updated,now):{status:'progress',target:p!.target,completed_views:updated.completed_views,required_views:p!.required_views};
  await store.put({...r!,status:receipt.status==='granted'?'granted':'credited',receipt,verification_method:'client_sdk_callback_reported',completed_at:now.toISOString(),version:r!.version+1});return receipt;
 }
 fail('Действие не поддерживается.');
}
