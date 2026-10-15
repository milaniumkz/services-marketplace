import { randomUUID } from 'node:crypto';
import { HttpException } from '@nestjs/common';
import { RecordData, Store } from './store';
import { readSettings } from './settings';
import { Providers } from './providers';
import { Temporal } from '@js-temporal/polyfill';
function fail(code:string,message:string,status=409):never{throw new HttpException({error:{code,message,details:{},retryable:false}},status);};
export class Growth {
  constructor(private store:Store,private providers=new Providers()){}
  private record(kind:string,owner:string,country:string,data:any):RecordData{return {...data,id:randomUUID(),kind,owner,country,version:1,created_at:new Date().toISOString()};}
  async referrals(owner:string,country:string) {
    let code=(await this.store.all('referral_code',country)).find(x=>x.owner===owner);
    if(!code){code=this.record('referral_code',owner,country,{code:randomUUID().replaceAll('-','').slice(0,12)});await this.store.put(code);}
    return {code:code.code,campaigns:(await this.store.all('referral_campaign',country)).filter(x=>x.status==='effective').map(x=>({id:x.id,...x.payload})),attributions:(await this.store.all('referral_attribution',country)).filter(x=>x.referrer_id===owner).map(x=>({id:x.id,status:x.status})),rewards:(await this.store.all('referral_reward',country)).filter(x=>x.owner===owner)};
  }
  async attribute(owner:string,country:string,code:string) {
    const previous=(await this.store.all('referral_attribution',country)).find(x=>x.owner===owner);if(previous)fail('ATTRIBUTION_ALREADY_SET','Пригласивший уже закреплён');
    const referrer=(await this.store.all('referral_code',country)).find(x=>x.code===code);if(!referrer||referrer.owner===owner)fail('REFERRAL_INELIGIBLE','Код недоступен',422);
    const campaign=(await this.store.all('referral_campaign',country)).find(x=>x.status==='effective');if(!campaign)fail('CAMPAIGN_UNAVAILABLE','Активной реферальной кампании нет',422);
    return this.store.put(this.record('referral_attribution',owner,country,{referrer_id:referrer.owner,campaign_id:campaign.id,campaign_snapshot:campaign.payload,status:'pending'}));
  }
  async qualify(owner:string,country:string,event:string,eventId:string) {
    const attribution=(await this.store.all('referral_attribution',country)).find(x=>x.owner===owner&&x.status==='pending'&&x.campaign_snapshot.qualifying_event===event);if(!attribution)return;
    await this.store.put({...attribution,status:'qualified',qualifying_event_id:eventId,version:attribution.version+1});
    const all=(await this.store.all('referral_attribution',country)).filter(x=>x.referrer_id===attribution.referrer_id&&x.campaign_id===attribution.campaign_id&&x.status==='qualified');
    const rewards=(await this.store.all('referral_reward',country)).filter(x=>x.campaign_id===attribution.campaign_id);
    const own=rewards.filter(x=>x.owner===attribution.referrer_id);
    const policy=attribution.campaign_snapshot;
    if(Math.floor(all.length/policy.threshold)<=own.length||rewards.length>=policy.budget_units)return;
    await this.store.put(this.record('referral_reward',attribution.referrer_id,country,{campaign_id:attribution.campaign_id,policy_snapshot:policy,status:'available',expires_at:new Date(Date.now()+30*86400000).toISOString(),qualifying_attributions:all.map(x=>x.id)}));
  }
  async redeem(owner:string,country:string,id:string) {
    const r=await this.store.get(id);if(!r||r.kind!=='referral_reward'||r.owner!==owner||r.country!==country)fail('NOT_FOUND','Награда не найдена',404);
    if(r.status==='redeemed')return r;if(r.status!=='available'||r.expires_at<=new Date().toISOString())fail('REWARD_EXPIRED','Награда больше не доступна');
    const grant=this.record('grant',owner,country,{source:'referral_privilege',source_id:r.id,valid_until:new Date(Date.now()+r.policy_snapshot.reward_duration_seconds*1000).toISOString(),capabilities:r.policy_snapshot.capabilities});
    await this.store.put(grant);return this.store.put({...r,status:'redeemed',grant_id:grant.id,version:r.version+1});
  }
  async reserveBoost(owner:string,country:string,b:any) {
    const settings=await readSettings(this.store,country);
    const target=await this.store.get(b.target_id);if(!target||target.owner!==owner||target.country!==country||!['open','published'].includes(target.status))fail('TARGET_INELIGIBLE','Карточка недоступна',422);
    const policy=(await this.store.all('placement_policy',country)).find(x=>x.status==='effective'&&x.payload.placement_id===b.placement_id);if(!policy)fail('PLACEMENT_UNAVAILABLE','Место не опубликовано',422);
    const price=await this.store.get(b.price_id);if(!price||price.kind!=='price_version'||price.status!=='effective'||price.country!==country)fail('PRICE_UNAVAILABLE','Цена не опубликована',422);
    let end:string;
    if(['month','year'].includes(price.payload.period)) {
      try{const start=Temporal.Instant.from(new Date().toISOString()).toZonedDateTimeISO(price.payload.time_zone??'UTC');end=start.add(price.payload.period==='month'?{months:1}:{years:1}).toInstant().toString();}catch{fail('DURATION_UNAPPROVED','Проверьте календарный период и часовой пояс',422);}
    }else {const days=price.payload.period==='week'?7:Number(price.payload.duration_days);if(!Number.isInteger(days)||days<1||days>366)fail('DURATION_UNAPPROVED','Длительность размещения не задана',422);end=new Date(Date.now()+days*86400000).toISOString();}
    if(target.kind==='order'&&Date.parse(target.expires_at)<Date.parse(end!))fail('TARGET_EXPIRES_EARLY','Заказ завершится раньше размещения',422);
    const active=(await this.store.all('boost',country)).filter(x=>x.placement_id===b.placement_id&&['reserved','payment_pending','scheduled','active'].includes(x.status)&&(x.reservation_expires_at??x.ends_at)>new Date().toISOString());
    if(active.length>=policy.payload.capacity)fail('PLACEMENT_FULL','Нет свободного места');
    if(active.some(x=>x.target_id===target.id))fail('BOOST_OVERLAP','Для карточки уже есть размещение');
    return this.store.put(this.record('boost',owner,country,{target_id:target.id,placement_id:b.placement_id,price_snapshot:price.payload,policy_snapshot:policy.payload,status:'reserved',starts_at:new Date().toISOString(),ends_at:end,reservation_expires_at:new Date(Date.now()+settings.boost_reservation_minutes*60000).toISOString()}));
  }
  async verifyBoost(owner:string,country:string,b:any) {
    const boost=await this.store.get(b.reservation_id);if(!boost||boost.kind!=='boost'||boost.owner!==owner||boost.country!==country)fail('NOT_FOUND','Резерв не найден',404);
    const provider=this.providers.billing.get(b.provider);if(!provider)fail('PROVIDER_UNAVAILABLE','Платёжный адаптер не подключён',503);
    if(boost.price_snapshot.provider!==b.provider)fail('PROVIDER_MISMATCH','Резерв связан с другим провайдером',422);
    const p=await provider.verifyPurchase(String(b.transaction_reference),owner);
    if(p.user_id!==owner||p.country!==country||p.provider!==b.provider||p.product_id!==boost.price_snapshot.product_id||p.amount_minor!==boost.price_snapshot.amount_minor||p.currency!==boost.price_snapshot.currency)fail('PURCHASE_OWNERSHIP_MISMATCH','Покупка не соответствует резерву',403);
    if(process.env.NODE_ENV==='production'&&p.environment!=='production')fail('PROVIDER_ENVIRONMENT_MISMATCH','Недопустимая среда покупки',422);
    const transactions=await this.store.all('payment_transaction',country);
    const previous=transactions.find(x=>x.provider===p.provider&&x.transaction_id===p.transaction_id&&x.state===p.state);
    if(previous){if(previous.boost_id!==boost.id)fail('TRANSACTION_ALREADY_USED','Покупка уже связана с другим правом',403);return {...boost,duplicate:true};}
    if(p.state==='pending')return this.store.put({...boost,status:'payment_pending',provider:p.provider,version:boost.version+1});
    if(!['active','revoked'].includes(p.state))fail('PAYMENT_PENDING','Покупка ещё не подтверждена',409);
    await this.store.put(this.record('payment_transaction',owner,country,{provider:p.provider,transaction_id:p.transaction_id,state:p.state,amount_minor:p.amount_minor,currency:p.currency,benefit:'boost',boost_id:boost.id}));
    if(p.state==='revoked')return this.store.put({...boost,status:'revoked',version:boost.version+1});
    const user=await this.store.get(owner),target=await this.store.get(boost.target_id);
    const entitlement=(await this.store.all('grant',country)).some(g=>g.owner===owner&&g.valid_until>new Date().toISOString()&&(g.balance===undefined||g.balance>0));
    const eligible=user?.status==='active'&&target&&['open','published'].includes(target.status)&&(target.kind!=='contractor'||user.verification==='passed')&&entitlement;
    const policy=(await this.store.all('placement_policy',country)).find(x=>x.status==='effective'&&x.payload.placement_id===boost.placement_id);
    const others=(await this.store.all('boost',country)).filter(x=>x.id!==boost.id&&x.placement_id===boost.placement_id&&['reserved','scheduled','active'].includes(x.status)&&(x.reservation_expires_at??x.ends_at)>new Date().toISOString());
    const available=policy&&others.length<policy.payload.capacity;
    const resolution=!eligible||!available||boost.ends_at<=new Date().toISOString();
    return this.store.put({...boost,status:resolution?'resolution_required':'active',provenance:'paid',provider:p.provider,transaction_id:p.transaction_id,confirmed_at:new Date().toISOString(),version:boost.version+1});
  }
  async previewAdminBoost(country:string,b:any) {
    const target=await this.store.get(b.target_id);
    if(!target||target.country!==country||!['order','contractor'].includes(target.kind)||target.status!==(target.kind==='order'?'open':'published')||['quarantined','hidden','rejected'].includes(target.moderation_status))fail('TARGET_INELIGIBLE','Карточка недоступна',422);
    const user=await this.store.get(target.owner),now=new Date().toISOString();
    const access=(await this.store.db.query<{allowed:boolean}>("SELECT EXISTS(SELECT 1 FROM records WHERE kind='grant' AND country=$1 AND owner=$2 AND data->>'valid_until'>$3 AND COALESCE(data->'capabilities','[]'::jsonb) ? 'search_full' AND (data->>'balance' IS NULL OR (data->>'balance')::numeric>0)) AS allowed",[country,target.owner,now])).rows[0].allowed;
    if(user?.kind!=='user'||user.country!==country||user.status!=='active'||target.kind==='contractor'&&user.verification!=='passed'||!access)fail('TARGET_INELIGIBLE','Не выполнены условия допуска',422);
    const policy=(await this.store.all('placement_policy',country)).find(x=>x.status==='effective'&&x.payload.placement_id===b.placement_id);
    if(!policy)fail('PLACEMENT_UNAVAILABLE','Место не опубликовано',422);
    const end=Date.parse(b.ends_at);
    if(!Number.isFinite(end)||end<=Date.now()||target.kind==='order'&&!(end<=Date.parse(target.expires_at)))fail('TARGET_EXPIRES_EARLY','Проверьте срок размещения',422);
    const active=(await this.store.all('boost',country)).filter(x=>['reserved','payment_pending','scheduled','active'].includes(x.status)&&x.ends_at>now&&(x.starts_at??x.created_at)<new Date(end).toISOString()&&(!['reserved','payment_pending'].includes(x.status)||x.reservation_expires_at>now));
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
    const {target,policy,preview}=await this.previewAdminBoost(country,b);
    return this.store.put(this.record('boost',target.owner,country,{target_id:target.id,placement_id:b.placement_id,policy_snapshot:policy.payload,provenance:'admin_grant',amount_minor:0,actor_id:actor,reason:b.reason,status:'active',starts_at:preview.starts_at,ends_at:preview.ends_at}));
  }
}
