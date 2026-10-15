import { randomUUID } from 'node:crypto';
import { RecordData, Store } from './store';
import { Providers, VerifiedPurchase } from './providers';
import { HttpException } from '@nestjs/common';
import { readSettings } from './settings';
function fail(code:string,message:string,status=503):never{throw new HttpException({error:{code,message,details:{},retryable:status===503}},status);};
export class Commerce {
  constructor(private store:Store,readonly providers:Providers) {}
  private record(kind:string,owner:string,country:string,data:any):RecordData {return {...data,id:randomUUID(),kind,owner,country,version:1,created_at:new Date().toISOString()};}
  async offers(country:string) {
    const prices=(await this.store.all('price_version',country)).filter(p=>p.status==='effective');
    return {items:prices.filter(p=>this.providers.billing.has(p.payload.provider)).map(p=>({id:p.id,...p.payload}))};
  }
  async verify(owner:string,country:string,providerName:string,reference:string) {
    const provider=this.providers.billing.get(providerName);if(!provider)fail('PROVIDER_UNAVAILABLE','Платёжный провайдер ещё не подключён');
    const purchase=await provider!.verifyPurchase(reference,owner);
    if(purchase.user_id!==owner||purchase.country!==country||purchase.provider!==providerName)fail('PURCHASE_OWNERSHIP_MISMATCH','Покупка принадлежит другому аккаунту или региону',403);
    return this.apply(purchase);
  }
  async webhook(providerName:string,raw:Buffer,headers:Record<string,string>) {
    const provider=this.providers.billing.get(providerName);if(!provider)fail('PROVIDER_UNAVAILABLE','Провайдер ещё не подключён');
    const event=await provider!.verifyWebhook(raw,headers);
    const duplicate=(await this.store.all('webhook_inbox',event.purchase.country)).find(x=>x.provider===providerName&&x.event_id===event.event_id);
    if(duplicate)return {accepted:true,duplicate:true};
    await this.store.put(this.record('webhook_inbox','provider',event.purchase.country,{provider:providerName,event_id:event.event_id,status:'verified',transaction_id:event.purchase.transaction_id}));
    const result=await this.apply(event.purchase);return {accepted:true,...(result.subscription?{subscription_id:result.subscription.id}:{check_id:result.check!.id})};
  }
  async apply(p:VerifiedPurchase) {
    if(!Number.isSafeInteger(p.amount_minor)||p.amount_minor<0||!Number.isFinite(Date.parse(p.valid_until))||!Number.isInteger(p.revision))fail('INVALID_PROVIDER_EVIDENCE','Некорректный ответ провайдера',422);
    if(!['sandbox','production'].includes(p.environment)||process.env.NODE_ENV==='production'&&p.environment!=='production')fail('PROVIDER_ENVIRONMENT_MISMATCH','Среда покупки не соответствует серверу',422);
    p={...p,valid_until:new Date(p.valid_until).toISOString()};
    const u=await this.store.get(p.user_id);if(!u||u.country!==p.country)fail('PURCHASE_OWNERSHIP_MISMATCH','Аккаунт покупки не найден',403);
    const existing=(await this.store.all('subscription',p.country)).find(x=>x.provider===p.provider&&x.original_transaction_id===p.original_transaction_id);
    if(!existing&&!u.roles?.includes('executor'))fail('EXECUTOR_ROLE_REQUIRED','Подписка доступна только исполнителю',403);
    if(p.state==='pending'){
      const price=(await this.store.all('price_version',p.country)).find(x=>x.status==='effective'&&x.payload.provider===p.provider&&x.payload.product_id===p.product_id&&x.payload.product_type!=='boost');
      if(!price||price.payload.currency!==p.currency||price.payload.amount_minor!==p.amount_minor)fail('PRICE_MISMATCH','Предложение не соответствует покупке',422);
      const previous=(await this.store.all('purchase_check',p.country)).find(x=>x.owner===p.user_id&&x.provider===p.provider&&x.transaction_id===p.transaction_id);
      return {pending:true,check:previous??await this.store.put(this.record('purchase_check',p.user_id,p.country,{provider:p.provider,transaction_id:p.transaction_id,status:'pending'}))};
    }
    if(!['active','grace','billing_retry','paused','expired','revoked','canceled_at_period_end'].includes(p.state))fail('INVALID_PROVIDER_EVIDENCE','Недопустимое состояние покупки',422);
    const price=(await this.store.all('price_version',p.country)).find(x=>x.status==='effective'&&x.payload.provider===p.provider&&x.payload.product_id===p.product_id);
    if(price?.payload.product_type==='boost')fail('PRODUCT_TYPE_MISMATCH','Разовую покупку продвижения нельзя использовать как подписку',422);
    if(!price&&!existing)fail('PRODUCT_NOT_CONFIGURED','Продукт не опубликован в каталоге цен',422);
    if(price&&(price.payload.currency!==p.currency||price.payload.amount_minor!==p.amount_minor)&&!existing)fail('PRICE_MISMATCH','Цена не совпадает с опубликованной версией',422);
    if(existing&&existing.owner!==p.user_id)fail('PURCHASE_OWNERSHIP_MISMATCH','Покупку нельзя перенести на другой аккаунт',403);
    if(existing&&existing.provider_revision>=p.revision)return {subscription:existing,duplicate:true};
    const ledger=(await this.store.all('payment_transaction',p.country)).find(x=>x.provider===p.provider&&x.transaction_id===p.transaction_id&&x.state===p.state);
    if(!ledger)await this.store.put(this.record('payment_transaction',p.user_id,p.country,{provider:p.provider,transaction_id:p.transaction_id,original_transaction_id:p.original_transaction_id,amount_minor:p.amount_minor,currency:p.currency,state:p.state,provider_revision:p.revision}));
    const subscription=await this.store.put({...existing??this.record('subscription',p.user_id,p.country,{}),price_snapshot:existing?.price_snapshot??price?.payload,provider:p.provider,original_transaction_id:p.original_transaction_id,product_id:p.product_id,status:p.state,valid_until:p.valid_until,provider_revision:p.revision,version:existing?existing.version+1:1});
    const grant=(await this.store.all('grant',p.country)).find(g=>g.source_id===subscription.id);
    const valid=['active','grace','canceled_at_period_end'].includes(p.state);
    await this.store.put({...grant??this.record('grant',p.user_id,p.country,{}),source:'subscription',source_id:subscription.id,valid_until:valid?p.valid_until:new Date().toISOString(),capabilities:['search_full','send_offer','publish_profile'],version:grant?grant.version+1:1});
    for(const check of await this.store.all('purchase_check',p.country))if(check.owner===p.user_id&&check.provider===p.provider&&check.transaction_id===p.transaction_id)await this.store.put({...check,status:'confirmed',subscription_id:subscription.id,version:check.version+1});
    return {subscription,duplicate:false};
  }
  async rewardSession(owner:string,country:string,b:any) {
    const settings=await readSettings(this.store,country);
    const config=(await this.store.all('monetization_config',country)).find(x=>x.status==='effective');
    if(!config?.payload?.rewarded_access_enabled)fail('REWARDED_DISABLED','Рекламный доступ выключен',403);
    const provider=this.providers.rewards.get(config!.payload.provider);if(!provider)fail('PROVIDER_UNAVAILABLE','Рекламная сеть ещё не подключена');
    const r=config!.payload.reward_policy;
    if(!r||!['duration','action_credits'].includes(r.kind))fail('REWARD_POLICY_UNAPPROVED','Политика награды не утверждена');
    const sessions=(await this.store.all('ad_session',country)).filter(s=>s.owner===owner&&s.created_at.slice(0,10)===new Date().toISOString().slice(0,10));
    if(sessions.length>=(config!.payload.daily_cap??5))fail('REWARD_LIMIT','Дневной лимит достигнут',429);
    if(sessions.some(s=>Date.parse(s.created_at)>Date.now()-(config!.payload.cooldown_seconds??300)*1000))fail('REWARD_COOLDOWN','Повторите после паузы',429);
    const session=this.record('ad_session',owner,country,{provider:provider!.name,placement:b.placement,nonce:randomUUID(),policy_snapshot:r,config_version:config!.version,late_window_hours:settings.reward_late_hours,status:'pending',expires_at:new Date(Date.now()+15*60000).toISOString()});
    await this.store.put(session);return session;
  }
  async rewardCallback(providerName:string,raw:Buffer,headers:Record<string,string>) {
    const provider=this.providers.rewards.get(providerName);if(!provider)fail('PROVIDER_UNAVAILABLE','Рекламная сеть не подключена');
    const proof=await provider!.verifyCallback(raw,headers);
    const session=await this.store.get(proof.session_id);
    if(!session||session.kind!=='ad_session'||session.provider!==providerName||proof.provider!==providerName)fail('REWARD_SESSION_MISMATCH','Сессия не найдена',422);
    const rewards=await this.store.all('ad_reward',session!.country);
    const duplicate=rewards.find(r=>r.session_id===session!.id||r.provider===providerName&&r.transaction_id===proof.transaction_id);
    if(duplicate)return {granted:true,duplicate:true};
    if(Date.parse(session!.expires_at)+(session!.late_window_hours??72)*3600000<Date.now())fail('LATE_REWARD_REQUIRES_REVIEW','Позднее подтверждение требует сверки',409);
    const policy=session!.policy_snapshot;
    const grant=this.record('grant',session!.owner,session!.country,{source:'verified_ad_reward',source_id:session!.id,capabilities:policy.capabilities,valid_until:new Date(Date.now()+Number(policy.duration_seconds??86400)*1000).toISOString(),balance:policy.kind==='action_credits'?Number(policy.credits):undefined});
    await this.store.put(grant);await this.store.put(this.record('ad_reward',session!.owner,session!.country,{provider:providerName,transaction_id:proof.transaction_id,session_id:session!.id,grant_id:grant.id}));
    await this.store.put({...session!,status:'granted',version:session!.version+1});return {granted:true,duplicate:false,grant_id:grant.id};
  }
}
