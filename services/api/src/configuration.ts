import {placementPolicyPayload,placementPromises} from './placement-policy';
import {referralPolicy} from './referral-policy';
import {categoryId,validateCategory} from './category-payload';
import {pricePayload} from './price-payload';
import {validatePushCampaign} from './push-campaigns';
import {rankingParameters} from './ranking';
import { Temporal } from '@js-temporal/polyfill';
import { HttpException } from '@nestjs/common';
import { RecordData, Store } from './store';
import { Providers } from './providers';
import { validateRules } from './moderation';
function fail(code:string,message:string,status=422):never{throw new HttpException({error:{code,message,details:{},retryable:status===503}},status);};
export function promoEnd(date:string,timeZone:string) {
  return Temporal.PlainDate.from(date).add({days:1}).toZonedDateTime(timeZone).toInstant().toString();
}
export function normalizePromotionPayload(value:any) {
  const p={...value};
  if(p.start_local!==undefined){try{p.valid_from=new Date(Number(Temporal.PlainDateTime.from(p.start_local).toZonedDateTime(p.time_zone,{disambiguation:'reject'}).toInstant().epochMilliseconds)).toISOString();}catch{fail('VALIDATION_ERROR','Проверьте начало промо и IANA часовой пояс');}delete p.start_local;}
  return p;
}
export class Configuration {
  constructor(private store:Store,private providers:Providers){}
  async validate(r:RecordData) {
    const p=r.payload??{};
    if(r.kind==='push_campaign')return validatePushCampaign(r);
    if(r.kind==='country_control') {
      if(typeof p.registration_enabled!=='boolean'||typeof p.stop_new_business!=='boolean')fail('VALIDATION_ERROR','Укажите состояние регистрации и новых действий');
    }
    if(r.kind==='price_version') {
      pricePayload(p,r.country);
      if(!Number.isSafeInteger(p.amount_minor)||p.amount_minor<0||!['KZT','KGS','RUB','BYN'].includes(p.currency))fail('VALIDATION_ERROR','Проверьте цену и валюту');
      const provider=this.providers.billing.get(p.provider);if(!provider)fail('PROVIDER_UNAVAILABLE','Сначала подключите платёжного провайдера',503);
      const product=await provider.validateProduct(p.product_id,r.country);
      if(product.product_id!==p.product_id||product.currency!==p.currency||product.amount_minor!==p.amount_minor)fail('PRICE_MISMATCH','Цена не синхронизирована с провайдером');
      return {provider_verified:true};
    }
    if(r.kind==='monetization_config') {
      if(p.subscription_enabled===false)fail('SUBSCRIPTION_REQUIRED','Опцию подписки нельзя удалить');
      if(typeof p.banner_ads_enabled!=='boolean'||typeof p.rewarded_access_enabled!=='boolean')fail('VALIDATION_ERROR','Рекламные флаги независимы и обязательны');
      if(p.banner_ads_enabled) {
        const provider=this.providers.banners.get(p.banner_provider);
        if(!provider)fail('BANNER_PROVIDER_UNAVAILABLE','Баннерная сеть ещё не подключена',503);
        if(!Array.isArray(p.banner_placements)||!p.banner_placements.length||p.banner_placements.length>10||p.banner_placements.some((id:any)=>typeof id!=='string'||!id.trim()||id.length>100))fail('VALIDATION_ERROR','Укажите разрешённые размещения');
        for(const placement of p.banner_placements)if(!(await provider.validatePlacement(placement,r.country)).allowed)fail('BANNER_PLACEMENT_UNAPPROVED','Размещение не подтверждено сетью');
      }
      if(p.rewarded_access_enabled) {
        if(!this.providers.rewards.has(p.provider)||!p.policy_evidence)fail('REWARD_POLICY_UNAPPROVED','Нужны провайдер и подтверждение допустимости pay-or-ad',503);
        const reward=p.reward_policy;if(!reward||!['duration','action_credits'].includes(reward.kind)||!Array.isArray(reward.capabilities)||!reward.capabilities.length)fail('VALIDATION_ERROR','Проверьте политику награды');
        if(reward.kind==='duration'&&(!Number.isInteger(reward.duration_seconds)||reward.duration_seconds<60||reward.duration_seconds>30*86400))fail('VALIDATION_ERROR','Проверьте длительность награды');
        if(reward.kind==='action_credits'&&(!Number.isInteger(reward.credits)||reward.credits<1||reward.credits>100))fail('VALIDATION_ERROR','Проверьте число кредитов');
        if(reward.kind==='action_credits'&&reward.capabilities.some((capability:string)=>!['publish_order','send_offer','select_offer','publish_profile'].includes(capability)))fail('VALIDATION_ERROR','Для чтения поиска используйте временный доступ, а не кредиты действий');
        if(reward.duration_seconds!==undefined&&(!Number.isInteger(reward.duration_seconds)||reward.duration_seconds<60||reward.duration_seconds>30*86400))fail('VALIDATION_ERROR','Проверьте срок награды или кредитов');
      }
    }
    if(r.kind==='promotion') {
      if(typeof p.end_date!=='string'||typeof p.time_zone!=='string')fail('VALIDATION_ERROR','Дата и часовой пояс обязательны');
      let end:string;try{end=promoEnd(p.end_date,p.time_zone);}catch{fail('VALIDATION_ERROR','Некорректная дата или IANA time zone');}
      const next=await this.store.get(p.next_price_id);if(!next||next.kind!=='price_version'||next.country!==r.country||next.status!=='effective'||next.payload.product_type==='boost')fail('NEXT_PRICE_UNVERIFIED','Сначала опубликуйте следующий тариф');
      if(Date.parse(end!)<=Date.now())fail('VALIDATION_ERROR','Дата промо уже прошла');
      if(p.valid_from!==undefined&&(!Number.isFinite(Date.parse(p.valid_from))||new Date(p.valid_from).toISOString()!==p.valid_from||Date.parse(p.valid_from)>=Date.parse(end!)))fail('VALIDATION_ERROR','Начало должно предшествовать окончанию промо');
      if(p.audience!==undefined&&!['all','new','existing'].includes(p.audience))fail('VALIDATION_ERROR','Выберите аудиторию промо');
      if(p.role!==undefined&&p.role!=='executor')fail('VALIDATION_ERROR','Промо подписки доступно только исполнителям');
      if(p.user_terms!==undefined&&(typeof p.user_terms!=='string'||p.user_terms.trim().length<10||p.user_terms.length>4000))fail('VALIDATION_ERROR','Укажите условия для пользователя');
      return {valid_from:p.valid_from??null,audience:p.audience??'all',role:'executor',user_terms:p.user_terms??null,promo_end_exclusive:end!,next_price:{id:next.id,...next.payload},amount_minor:0};
    }
    if(r.kind==='dictionary'){try{validateRules(p.rules);}catch(e:any){fail('VALIDATION_ERROR',e.message);}}
    if(r.kind==='category')return validateCategory(this.store,r);
    if(r.kind==='referral_campaign')referralPolicy(p);
    if(r.kind==='ranking_config')rankingParameters(p);
    if(r.kind==='placement_policy'){const policy=placementPolicyPayload(p);return {valid:true,...policy,...await placementPromises(this.store,r.country,policy.placement_id)};}
    if(['verification_policy','retention_policy'].includes(r.kind)) {
      const document=await this.store.get(p.document_id);if(!document||document.kind!=='legal_document'||document.country!==r.country||document.status!=='published')fail('LEGAL_VERSION_UNAPPROVED','Нужно опубликованное правовое основание');
      if(r.kind==='verification_policy'&&(!Array.isArray(p.document_types)||!p.document_types.length||p.document_types.some((t:string)=>!['passport','id_card'].includes(t))))fail('VALIDATION_ERROR','Укажите допустимые типы документа');
      if(r.kind==='verification_policy'&&p.document_types.some((type:string)=>!Array.isArray(p.required_pages?.[type])||!p.required_pages[type].length||p.required_pages[type].length>4||new Set(p.required_pages[type]).size!==p.required_pages[type].length||p.required_pages[type].some((page:any)=>typeof page!=='string'||page.trim().length<2||page.length>80)))fail('VALIDATION_ERROR','Укажите утверждённые стороны или страницы для каждого типа документа');
      if(r.kind==='retention_policy'&&(!Number.isInteger(p.document_days)||p.document_days<1||p.document_days>365))fail('VALIDATION_ERROR','Укажите утверждённый срок хранения документов');
    }
    return {valid:true};
  }
  async preview(r:RecordData) {
    const validation=await this.validate(r),now=new Date().toISOString();
    const count=async(kind:string,condition:string)=>Number((await this.store.db.query<{count:string}>(`SELECT count(*)::text FROM records WHERE country=$1 AND kind=$2 AND $3::text IS NOT NULL AND ${condition}`,[r.country,kind,now])).rows[0].count);
    const [accounts,grants,subscriptions]=await Promise.all([count('user',"data->>'status'='active'"),count('grant',"data->>'valid_until'>$3"),count('subscription',"data->>'valid_until'>$3")]);
    return {...validation,source_id:r.id,source_version:r.version,country:r.country,country_active_accounts:accounts,country_unexpired_grants:grants,country_unexpired_subscriptions:subscriptions,existing_grants_preserved:true,applied:false,generated_at:now};
  }
  async publish(r:RecordData,actor:string,version:number) {
    if(r.version!==version)fail('STATE_CONFLICT','Настройка изменилась',409);
    if(r.owner===actor)fail('SECOND_APPROVAL_REQUIRED','Нужно подтверждение другого сотрудника',403);
    if(!['draft','validated','approved'].includes(r.status))fail('STATE_CONFLICT','Версия уже опубликована',409);
    if(r.kind==='category'){
      await this.store.db.query('SELECT pg_advisory_xact_lock(hashtextextended($1,0))',['category-publish:'+r.country]);
      const fresh=await this.store.get(r.id);if(!fresh||fresh.version!==version)fail('STATE_CONFLICT','Версия категории изменилась',409);
      const head=(await this.store.all('category',r.country)).find(x=>x.status==='effective'&&categoryId(x)===categoryId(r));
      if(Object.hasOwn(r,'base_version_id')&&(head?.id??null)!==r.base_version_id)fail('CATEGORY_BASE_CHANGED','Каталог изменился. Откройте актуальную категорию и создайте новую версию',409);
    }
    if(r.kind==='placement_policy'){
      placementPolicyPayload(r.payload);
      await this.store.db.query('SELECT pg_advisory_xact_lock(hashtextextended($1,0))',['boost-capacity:'+r.country+':'+r.payload.placement_id]);
      const fresh=await this.store.get(r.id);if(!fresh||fresh.version!==version)fail('STATE_CONFLICT','Версия размещения изменилась',409);
    }
    const preview=await this.validate(r);
    if(r.kind==='placement_policy') {
      const promises=await placementPromises(this.store,r.country,r.payload.placement_id);
      if(promises.promised_peak>r.payload.capacity)fail('CAPACITY_PROMISE_CONFLICT','Нельзя уменьшить ёмкость ниже выданных обещаний',409);
    }
    const scope=(x:RecordData)=>JSON.stringify(['referral_campaign','ranking_config'].includes(x.kind)?{country:x.country}:x.kind==='category'?{category:x.payload?.category_id??x.id}:x.kind==='price_version'?{provider:x.payload.provider,product:x.payload.product_id,audience:x.payload.audience}:x.kind==='placement_policy'?{placement:x.payload.placement_id}:{scope:x.payload?.scope,role:x.payload?.role,platform:x.payload?.platform});
    for(const old of await this.store.all(r.kind,r.country))if(old.status==='effective'&&scope(old)===scope(r))await this.store.put({...old,status:'superseded',version:old.version+1});
    return this.store.put({...r,status:'effective',preview,published_by:actor,published_at:new Date().toISOString(),version:r.version+1});
  }
}
