import {issueDiscount,bestDiscount,discountedPrice,useDiscount} from './personal-discounts';
import {createPeriod,periodPlan} from './subscription-periods';
import {subscriptionRole} from './subscription-plans';
import {subscriptionState} from './subscription-quotes';
import { randomUUID } from 'node:crypto';
import { HttpException } from '@nestjs/common';
import { RecordData, Store } from './store';
import { readSettings } from './settings';
import { Providers } from './providers';
import { promotedPlacements } from './promoted-listings';
import { Temporal } from '@js-temporal/polyfill';
function fail(code:string,message:string,status=409):never{throw new HttpException({error:{code,message,details:{},retryable:false}},status);};
export class Growth {
  constructor(private store:Store,private providers=new Providers()){}
  private record(kind:string,owner:string,country:string,data:any):RecordData{return {...data,id:randomUUID(),kind,owner,country,version:1,created_at:new Date().toISOString()};}
  async referrals(owner:string,country:string) {
    let code=(await this.store.all('referral_code',country)).find(x=>x.owner===owner);
    if(!code){code=this.record('referral_code',owner,country,{code:randomUUID().replaceAll('-','').slice(0,12)});await this.store.put(code);}
    return {code:code.code,campaigns:(await this.store.all('referral_campaign',country)).filter(x=>x.status==='effective').map(x=>({id:x.id,...x.payload})),attributions:(await this.store.all('referral_attribution',country)).filter(x=>x.referrer_id===owner).map(x=>({id:x.id,status:x.status})),rewards:(await this.store.all('referral_reward',country)).filter(x=>x.owner===owner),discounts:(await this.store.all('referral_discount',country)).filter(x=>x.owner===owner).map(d=>({id:d.id,percent:d.percent,services:d.services,valid_until:d.valid_until,status:d.status,uses:d.uses,max_uses:d.max_uses}))};
  }
  async attribute(owner:string,country:string,code:string) {
    await this.store.db.query('SELECT pg_advisory_xact_lock(hashtextextended($1,0))',['referrals:'+country]);
    const previous=(await this.store.all('referral_attribution',country)).find(x=>x.owner===owner);if(previous)fail('ATTRIBUTION_ALREADY_SET','Пригласивший уже закреплён');
    const referrer=(await this.store.all('referral_code',country)).find(x=>x.code===code);if(!referrer||referrer.owner===owner)fail('REFERRAL_INELIGIBLE','Код недоступен',422);
    const inviter=await this.store.get(referrer.owner);if(!inviter||inviter.status!=='active'||inviter.staff_permissions?.length)fail('REFERRAL_INELIGIBLE','Код недоступен',422);
    const campaign=(await this.store.all('referral_campaign',country)).find(x=>x.status==='effective');if(!campaign)fail('CAMPAIGN_UNAVAILABLE','Активной реферальной кампании нет',422);
    if(campaign.payload.attribution_window_days!==undefined){
      const account=await this.store.get(owner),created=Date.parse(account?.created_at??''),days=campaign.payload.attribution_window_days;
      if(!account||account.kind!=='user'||account.country!==country||!Number.isSafeInteger(days)||days<1||days>365||!Number.isFinite(created)||created>Date.now()||Date.now()>=created+days*86400000)fail('ATTRIBUTION_WINDOW_EXPIRED','Срок ввода кода после регистрации истёк',422);
    }
    // Reserve one complete reward before accepting the first invitation in its group.
    // Reservations survive campaign stop and never borrow another inviter's budget.
    const reservations=(await this.store.all('referral_reservation',country)).filter(x=>x.campaign_id===campaign.id);
    const attributions=await this.store.all('referral_attribution',country);
    let reservation=reservations.find(x=>x.owner===referrer.owner&&x.status==='reserved'&&attributions.filter(a=>a.reservation_id===x.id).length<x.policy_snapshot.threshold);
    if(!reservation){
      const legacyRewards=(await this.store.all('referral_reward',country)).filter(x=>x.campaign_id===campaign.id&&!x.reservation_id);
      if(reservations.length+legacyRewards.length>=campaign.payload.budget_units)fail('REFERRAL_BUDGET_EXHAUSTED','Бюджет новых приглашений исчерпан');
      reservation=this.record('referral_reservation',referrer.owner,country,{campaign_id:campaign.id,policy_snapshot:campaign.payload,status:'reserved'});
      await this.store.put(reservation);
    }
    const saved=await this.store.put(this.record('referral_attribution',owner,country,{referrer_id:referrer.owner,campaign_id:campaign.id,reservation_id:reservation.id,campaign_snapshot:reservation.policy_snapshot,status:'pending'}));if(reservation.policy_snapshot.qualifying_event==='registered')await this.qualify(owner,country,'registered',owner);return (await this.store.get(saved.id))!;
  }
  async qualify(owner:string,country:string,event:string,eventId:string) {
    await this.store.db.query('SELECT pg_advisory_xact_lock(hashtextextended($1,0))',['referrals:'+country]);
    const attribution=(await this.store.all('referral_attribution',country)).find(x=>x.owner===owner&&x.status==='pending'&&x.campaign_snapshot.qualifying_event===event);if(!attribution)return;
    await this.store.put({...attribution,status:'qualified',qualifying_event_id:eventId,version:attribution.version+1});
    if(attribution.reservation_id){
      const reservation=await this.store.get(attribution.reservation_id);
      if(!reservation||reservation.status!=='reserved')return;
      const qualified=(await this.store.all('referral_attribution',country)).filter(x=>x.reservation_id===reservation.id&&x.status==='qualified');
      if(qualified.length<reservation.policy_snapshot.threshold)return;
      const reward=this.record('referral_reward',attribution.referrer_id,country,{campaign_id:attribution.campaign_id,reservation_id:reservation.id,policy_snapshot:reservation.policy_snapshot,status:'available',expires_at:new Date(Date.now()+30*86400000).toISOString(),qualifying_attributions:qualified.map(x=>x.id)});
      await this.store.put(reward);
      await this.store.put({...reservation,status:'issued',reward_id:reward.id,version:reservation.version+1});
      await this.redeemEligible(attribution.referrer_id,country);
      return;
    }
    const all=(await this.store.all('referral_attribution',country)).filter(x=>x.referrer_id===attribution.referrer_id&&x.campaign_id===attribution.campaign_id&&x.status==='qualified');
    const rewards=(await this.store.all('referral_reward',country)).filter(x=>x.campaign_id===attribution.campaign_id);
    const own=rewards.filter(x=>x.owner===attribution.referrer_id);
    const policy=attribution.campaign_snapshot;
    if(Math.floor(all.length/policy.threshold)<=own.length||rewards.length>=policy.budget_units)return;
    await this.store.put(this.record('referral_reward',attribution.referrer_id,country,{campaign_id:attribution.campaign_id,policy_snapshot:policy,status:'available',expires_at:new Date(Date.now()+30*86400000).toISOString(),qualifying_attributions:all.map(x=>x.id)}));
    await this.redeemEligible(attribution.referrer_id,country);
  }
  async redeem(owner:string,country:string,id:string) {
    await this.store.db.query('SELECT pg_advisory_xact_lock(hashtextextended($1,0))',['referrals:'+country]);
    const r=await this.store.get(id);if(!r||r.kind!=='referral_reward'||r.owner!==owner||r.country!==country)fail('NOT_FOUND','Награда не найдена',404);
    if(r.status==='redeemed')return r;if(r.status!=='available'||r.expires_at<=new Date().toISOString())fail('REWARD_EXPIRED','Награда больше не доступна');
    if(r.policy_snapshot.reward_kind==='discount'){const discount=await issueDiscount(this.store,r);return this.store.put({...r,status:'redeemed',discount_id:discount.id,version:r.version+1});}
    if(r.policy_snapshot.reward_kind==='subscription_days'){
      const user=await this.store.get(owner);if(!user||user.status!=='active')fail('FORBIDDEN','Аккаунт недоступен',403);
      const state=await subscriptionState(this.store,user),role=subscriptionRole(user),p=r.policy_snapshot;
      const plan=p.reward_plan==='current'?(role==='customer'?'customer':state.premium?'premium':'standard'):p.reward_plan;
      if((plan==='customer')!==(role==='customer'))fail('ROLE_REQUIRED','Награда предназначена для другой роли',403);
      if(plan==='top100'&&!state.current.length)fail('ENTITLEMENT_REQUIRED','Для бонусного Топ-100 нужен основной доступ',403);
      const topEnd=state.periods.filter(s=>periodPlan(s)==='top100'||periodPlan(s)==='premium').reduce((v,s)=>Math.max(v,Date.parse(s.valid_until)),Date.now());
      const from=new Date(plan==='top100'?topEnd:state.paid_until).toISOString();
      const period=await createPeriod(this.store,user,{plan,seconds:p.reward_duration_seconds,from,price:{plan,amount_minor:0,currency:({KZ:'KZT',KG:'KGS',RU:'RUB',BY:'BYN'} as Record<string,string>)[country],period:'days',reward_id:r.id},provider:'referral',referral_reward_id:r.id});
      return this.store.put({...r,status:'redeemed',subscription_id:period.id,grant_id:period.grant_id,version:r.version+1});
    }
    const grant=this.record('grant',owner,country,{source:'referral_privilege',source_id:r.id,valid_until:new Date(Date.now()+r.policy_snapshot.reward_duration_seconds*1000).toISOString(),capabilities:r.policy_snapshot.capabilities});
    await this.store.put(grant);return this.store.put({...r,status:'redeemed',grant_id:grant.id,version:r.version+1});
  }
  async redeemEligible(owner:string,country:string){
    const user=await this.store.get(owner);if(!user||user.status!=='active'||user.staff_permissions?.length)return;
    const rewards=(await this.store.select('referral_reward',country,{owner,statuses:['available'],limit:100})).filter(r=>r.policy_snapshot?.reward_kind&&r.expires_at>new Date().toISOString());
    for(const r of rewards){try{await this.redeem(owner,country,r.id);}catch(error){const code=(error as any).getResponse?.()?.error?.code;if(!['ROLE_REQUIRED','ENTITLEMENT_REQUIRED'].includes(code))throw error;}}
  }
  async reserveBoost(owner:string,country:string,b:any) {
    const settings=await readSettings(this.store,country);
    const target=await this.store.get(b.target_id);if(!target||target.owner!==owner||target.country!==country||!['order','contractor'].includes(target.kind)||target.status!==(target.kind==='order'?'open':'published')||['quarantined','hidden','rejected'].includes(target.moderation_status))fail('TARGET_INELIGIBLE','Карточка недоступна',422);
    const policy=(await this.store.all('placement_policy',country)).find(x=>x.status==='effective'&&x.payload.placement_id===b.placement_id);if(!policy)fail('PLACEMENT_UNAVAILABLE','Место не опубликовано',422);
    const price=await this.store.get(b.price_id);if(!price||price.kind!=='price_version'||price.status!=='effective'||price.country!==country||price.payload.product_type!=='boost')fail('PRICE_UNAVAILABLE','Цена не опубликована',422);
    let end:string;
    if(['month','year'].includes(price.payload.period)) {
      try{const start=Temporal.Instant.from(new Date().toISOString()).toZonedDateTimeISO(price.payload.time_zone??'UTC');end=start.add(price.payload.period==='month'?{months:1}:{years:1}).toInstant().toString();}catch{fail('DURATION_UNAPPROVED','Проверьте календарный период и часовой пояс',422);}
    }else {const days=price.payload.period==='week'?7:Number(price.payload.duration_days);if(!Number.isInteger(days)||days<1||days>366)fail('DURATION_UNAPPROVED','Длительность размещения не задана',422);end=new Date(Date.now()+days*86400000).toISOString();}
    if(target.kind==='order'&&Date.parse(target.expires_at)<Date.parse(end!))fail('TARGET_EXPIRES_EARLY','Заказ завершится раньше размещения',422);
    await this.store.db.query('SELECT pg_advisory_xact_lock(hashtextextended($1,0))',['boost-target:'+country+':'+b.target_id]);
    await this.store.db.query('SELECT pg_advisory_xact_lock(hashtextextended($1,0))',['boost-capacity:'+country+':'+b.placement_id]);
    await this.previewAdminBoost(country,{...b,ends_at:end});
    await this.store.db.query('SELECT pg_advisory_xact_lock(hashtextextended($1,0))',['personal-discount:'+country+':'+owner]);
    const buyer=await this.store.get(owner),discount=buyer?await bestDiscount(this.store,buyer,'boost'):undefined;
    return this.store.put(this.record('boost',owner,country,{target_id:target.id,placement_id:b.placement_id,price_snapshot:{...price.payload,...discountedPrice(price.payload.amount_minor,discount)},policy_snapshot:policy.payload,status:'reserved',starts_at:new Date().toISOString(),ends_at:end,reservation_expires_at:new Date(Date.now()+settings.boost_reservation_minutes*60000).toISOString()}));
  }
  async verifyBoost(owner:string,country:string,b:any) {
    const boost=await this.store.get(b.reservation_id);if(!boost||boost.kind!=='boost'||boost.owner!==owner||boost.country!==country)fail('NOT_FOUND','Резерв не найден',404);
    const provider=this.providers.billing.get(b.provider);if(!provider)fail('PROVIDER_UNAVAILABLE','Платёжный адаптер не подключён',503);
    if(boost.price_snapshot.provider!==b.provider)fail('PROVIDER_MISMATCH','Резерв связан с другим провайдером',422);
    const p=await provider.verifyPurchase(String(b.transaction_reference),owner);
    if(p.user_id!==owner||p.country!==country||p.provider!==b.provider||p.product_id!==boost.price_snapshot.product_id||p.amount_minor!==boost.price_snapshot.amount_minor||p.currency!==boost.price_snapshot.currency)fail('PURCHASE_OWNERSHIP_MISMATCH','Покупка не соответствует резерву',403);
    if(process.env.NODE_ENV==='production'&&p.environment!=='production')fail('PROVIDER_ENVIRONMENT_MISMATCH','Недопустимая среда покупки',422);
    await this.store.db.query('SELECT pg_advisory_xact_lock(hashtextextended($1,0))',['boost-target:'+country+':'+boost.target_id]);
    await this.store.db.query('SELECT pg_advisory_xact_lock(hashtextextended($1,0))',['boost-capacity:'+country+':'+boost.placement_id]);
    await this.store.db.query('SELECT pg_advisory_xact_lock(hashtextextended($1,0))',['payment-transaction:'+country+':'+p.provider+':'+p.transaction_id]);
    const transactions=await this.store.all('payment_transaction',country),transactionEvents=transactions.filter(x=>x.provider===p.provider&&x.transaction_id===p.transaction_id);
    if(transactionEvents.some(x=>x.boost_id!==boost.id||x.owner!==owner||x.environment&&x.environment!==p.environment||x.amount_minor!==p.amount_minor||x.currency!==p.currency))fail('TRANSACTION_ALREADY_USED','Покупка уже связана с другим правом',403);
    const previous=transactionEvents.find(x=>x.state===p.state);
    if(previous){if(previous.boost_id!==boost.id)fail('TRANSACTION_ALREADY_USED','Покупка уже связана с другим правом',403);return {...boost,duplicate:true};}
    if(p.state==='pending')return this.store.put({...boost,status:'payment_pending',provider:p.provider,version:boost.version+1});
    if(!['active','revoked'].includes(p.state))fail('PAYMENT_PENDING','Покупка ещё не подтверждена',409);
    await this.store.put(this.record('payment_transaction',owner,country,{provider:p.provider,transaction_id:p.transaction_id,state:p.state,amount_minor:p.amount_minor,currency:p.currency,benefit:'boost',environment:p.environment,boost_id:boost.id,source_id:boost.id,operation:p.state==='active'?'purchase':'revoke',cash_amount_minor:p.state==='active'?p.amount_minor:0}));
    if(p.state==='revoked')return this.store.put({...boost,status:'revoked',version:boost.version+1});
    let resolution=false;
    try {
      const {target}=await this.previewAdminBoost(country,{target_id:boost.target_id,placement_id:boost.placement_id,ends_at:boost.ends_at},boost.id);
      resolution=target.owner!==owner;
    } catch(e) {
      if(!(e instanceof HttpException)||!['TARGET_INELIGIBLE','PLACEMENT_UNAVAILABLE','TARGET_EXPIRES_EARLY','BOOST_OVERLAP','PLACEMENT_FULL'].includes((e.getResponse() as any)?.error?.code))throw e;
      resolution=true;
    }
    if(!resolution)try{await useDiscount(this.store,owner,country,boost.price_snapshot,new Date(),boost.id);}catch(error){if((error as any).getResponse?.()?.error?.code!=='OFFER_CHANGED')throw error;resolution=true;}
    return this.store.put({...boost,status:resolution?'resolution_required':'active',provenance:'paid',provider:p.provider,transaction_id:p.transaction_id,confirmed_at:new Date().toISOString(),version:boost.version+1});
  }
  async previewAdminBoost(country:string,b:any,excludedId?:string) {
    const target=await this.store.get(b.target_id);
    if(!target||target.country!==country||!['order','contractor'].includes(target.kind)||target.status!==(target.kind==='order'?'open':'published')||['quarantined','hidden','rejected'].includes(target.moderation_status))fail('TARGET_INELIGIBLE','Карточка недоступна',422);
    const user=await this.store.get(target.owner),now=new Date().toISOString();
    const access=(await this.store.db.query<{allowed:boolean}>("SELECT EXISTS(SELECT 1 FROM records WHERE kind='grant' AND country=$1 AND owner=$2 AND data->>'valid_until'>$3 AND COALESCE(data->'capabilities','[]'::jsonb) ? 'search_full' AND (data->>'balance' IS NULL OR (data->>'balance')::numeric>0)) AS allowed",[country,target.owner,now])).rows[0].allowed;
    if(user?.kind!=='user'||user.country!==country||user.status!=='active'||target.kind==='contractor'&&user.verification!=='passed'||target.kind==='contractor'&&!access)fail('TARGET_INELIGIBLE','Не выполнены условия допуска',422);
    const policy=(await this.store.all('placement_policy',country)).find(x=>x.status==='effective'&&x.payload.placement_id===b.placement_id);
    if(!policy)fail('PLACEMENT_UNAVAILABLE','Место не опубликовано',422);
    if(!promotedPlacements.includes(b.placement_id)||(b.placement_id.includes('.orders.')?'order':'contractor')!==target.kind)fail('PLACEMENT_UNAVAILABLE','Площадка не подходит для карточки',422);
    const end=Date.parse(b.ends_at);
    if(!Number.isFinite(end)||end<=Date.now()||target.kind==='order'&&!(end<=Date.parse(target.expires_at)))fail('TARGET_EXPIRES_EARLY','Проверьте срок размещения',422);
    const active=(await this.store.all('boost',country)).filter(x=>x.id!==excludedId&&['reserved','payment_pending','scheduled','active'].includes(x.status)&&x.ends_at>now&&(x.starts_at??x.created_at)<new Date(end).toISOString()&&(!['reserved','payment_pending'].includes(x.status)||x.reservation_expires_at>now));
    if(active.some(x=>x.target_id===target.id))fail('BOOST_OVERLAP','Для карточки уже есть размещение');
    const events=active.filter(x=>x.placement_id===b.placement_id).flatMap(x=>[
      {time:Math.max(Date.parse(x.starts_at??x.created_at),Date.parse(now)),delta:1},
      {time:Math.min(Date.parse(x.ends_at),end),delta:-1}]);
    let occupied=0,running=0;
    for(const event of events.sort((x,y)=>x.time-y.time||x.delta-y.delta)){
      if(!Number.isFinite(event.time))fail('PLACEMENT_UNAVAILABLE','Проверьте сроки существующих размещений',422);
      running+=event.delta;occupied=Math.max(occupied,running);
    }
    if(occupied>=policy.payload.capacity)fail('PLACEMENT_FULL','Нет свободной ёмкости');
    if(b.expected_target_version!==undefined&&b.expected_target_version!==target.version||b.expected_policy_version!==undefined&&b.expected_policy_version!==policy.version)fail('STATE_CONFLICT','Карточка или политика изменились. Повторите предпросмотр');
    return {target,policy,preview:{target_id:target.id,target_type:target.kind,title:target.title,country,city:target.city??'',category_id:target.category_id??'',owner_id:target.owner,placement_id:b.placement_id,expected_target_version:target.version,expected_policy_version:policy.version,starts_at:now,ends_at:new Date(end).toISOString(),available_slots:policy.payload.capacity-occupied,amount_minor:0,provenance:'admin_grant',checks:{owner_active:true,verification:target.kind==='contractor'?'passed':'not_required',access_active:true,target_public:true,within_target_expiry:true,no_overlap:true},organic_rank_changed:false}};
  }
  async adminBoost(actor:string,country:string,b:any) {
    if(!Number.isInteger(b.expected_target_version)||!Number.isInteger(b.expected_policy_version))fail('VALIDATION_ERROR','Сначала выполните предпросмотр выдачи',400);
    await this.store.db.query('SELECT pg_advisory_xact_lock(hashtextextended($1,0))',['boost-target:'+country+':'+b.target_id]);
    await this.store.db.query('SELECT pg_advisory_xact_lock(hashtextextended($1,0))',['boost-capacity:'+country+':'+b.placement_id]);
    const {target,policy,preview}=await this.previewAdminBoost(country,b);
    return this.store.put(this.record('boost',target.owner,country,{target_id:target.id,placement_id:b.placement_id,policy_snapshot:policy.payload,provenance:'admin_grant',amount_minor:0,actor_id:actor,reason:b.reason,status:'active',starts_at:preview.starts_at,ends_at:preview.ends_at}));
  }
}
