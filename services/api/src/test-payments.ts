import {randomUUID} from 'node:crypto';
import {HttpException} from '@nestjs/common';
import {Store,RecordData} from './store';
import {subscriptionCapabilities,subscriptionRole} from './subscription-plans';
const fail=(code:string,message:string,status=422):never=>{throw new HttpException({error:{code,message,retryable:false}},status);};
const row=(kind:string,owner:string,country:string,data:any):RecordData=>({id:randomUUID(),kind,owner,country,version:1,created_at:new Date().toISOString(),...data});
export async function testPaymentSettings(store:Store,country:string,providerReady:boolean){
 const r=(await store.all('test_payment_settings',country))[0];return {enabled:r?.enabled===true&&!providerReady,configured_enabled:r?.enabled===true,version:r?.version??0,real_provider_connected:providerReady};
}
export async function updateTestPayments(store:Store,country:string,actor:string,b:any,providerReady:boolean){
 if(typeof b.enabled!=='boolean'||typeof b.reason!=='string'||b.reason.trim().length<10||b.reason.length>1000)fail('VALIDATION_ERROR','Укажите режим и причину изменения');
 await store.db.query('SELECT pg_advisory_xact_lock(hashtextextended($1,0))',['test-payment-mode:'+country]);
 const existing=(await store.all('test_payment_settings',country))[0];if(b.expected_version!==(existing?.version??0))fail('STATE_CONFLICT','Настройка изменена',409);
 if(b.enabled&&providerReady)fail('TEST_PAYMENTS_UNAVAILABLE','Подключён реальный платёжный провайдер',409);
 const now=new Date().toISOString();await store.put({...existing??row('test_payment_settings',actor,country,{}),enabled:b.enabled,version:(existing?.version??0)+1,updated_at:now});
 if(!b.enabled){
  for(const subscription of await store.all('subscription',country))if(subscription.is_test&&subscription.status==='active')await store.put({...subscription,status:'revoked',valid_until:now,version:subscription.version+1});
  for(const grant of await store.all('grant',country))if(grant.is_test)await store.put({...grant,valid_until:now,version:grant.version+1});
 }
 await store.put(row('audit',actor,country,{actor_id:actor,action:'billing.test_mode_changed',target_id:country,reason:b.reason,enabled:b.enabled}));
 return testPaymentSettings(store,country,providerReady);
}
export async function simulateSubscription(store:Store,user:RecordData,b:any,offers:any[]){
 if(user.status!=='active')fail('FORBIDDEN','Аккаунт ограничен',403);
 if(b.accepted!==true)fail('CONSENT_REQUIRED','Подтвердите условия тестовой оплаты',403);
 const offer=offers.find(o=>o.id===b.offer_id&&o.is_test===true);
 if(!offer)fail('OFFER_CHANGED','Тестовый тариф недоступен. Обновите условия оплаты',409);
 await store.db.query('SELECT pg_advisory_xact_lock(hashtextextended($1,0))',['test-payment-mode:'+user.country]);
 const settings=await testPaymentSettings(store,user.country,false);
 const catalog=(await store.all('subscription_catalog',user.country))[0];
 if(!settings.enabled||settings.version!==offer.test_settings_version||(catalog?.version??0)!==offer.catalog_version)fail('OFFER_CHANGED','Условия тестовой оплаты изменились',409);
 if(offer.amount_minor!==b.amount_minor||offer.currency!==b.currency)fail('OFFER_CHANGED','Цена изменилась. Обновите условия оплаты',409);
 const role=subscriptionRole(user);if(!(user.roles??['customer']).includes(role))fail('ROLE_REQUIRED','Настройте выбранную роль',403);if(offer.role!==role)fail('ROLE_REQUIRED','Выберите подписку текущей роли',403);
 if(user.verification!=='passed')fail('VERIFICATION_REQUIRED','Сначала подтвердите личность',403);
 await store.db.query('SELECT pg_advisory_xact_lock(hashtextextended($1,0))',['test-payment:'+user.country+':'+user.id+':'+role]);
 const now=new Date(),until=new Date(now.getTime()+30*86400000).toISOString();
 const subscriptions=(await store.select('subscription',user.country,{owner:user.id,limit:1000})).filter(s=>s.valid_until>now.toISOString()&&['active','grace','canceled_at_period_end'].includes(s.status)&&((s.price_snapshot?.plan==='customer')=== (role==='customer')));
 if(subscriptions.some(s=>!s.is_test))fail('SUBSCRIPTION_ACTIVE','Реальная подписка уже активна',409);
 const previous=subscriptions.find(s=>s.is_test&&s.price_snapshot?.plan===offer.plan);if(previous)return {subscription:previous,is_test:true,duplicate:true};
 for(const s of subscriptions){await store.put({...s,status:'revoked',valid_until:now.toISOString(),version:s.version+1});for(const g of await store.select('grant',user.country,{owner:user.id,sourceId:s.id,limit:100}))await store.put({...g,valid_until:now.toISOString(),version:g.version+1});}
 const subscription=await store.put(row('subscription',user.id,user.country,{provider:'test',is_test:true,environment:'sandbox',product_id:offer.product_id,status:'active',valid_until:until,auto_renew:false,price_snapshot:offer,role,original_transaction_id:randomUUID()}));
 await store.put(row('grant',user.id,user.country,{source:'subscription',source_id:subscription.id,role,plan:offer.plan,is_test:true,valid_until:until,capabilities:subscriptionCapabilities(offer.plan)}));
 await store.put(row('payment_transaction',user.id,user.country,{provider:'test',is_test:true,environment:'sandbox',transaction_id:randomUUID(),operation:'test_purchase',state:'active',benefit:'subscription',source_id:subscription.id,amount_minor:offer.amount_minor,cash_amount_minor:0,currency:offer.currency,accepted_terms:true}));
 await store.put(row('audit',user.id,user.country,{actor_id:user.id,action:'billing.test_subscription_created',target_id:subscription.id,reason:'Явное подтверждение имитации оплаты без списания денег',plan:offer.plan}));
 return {subscription,is_test:true,duplicate:false};
}
