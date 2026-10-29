import {createHash,randomUUID} from 'node:crypto';
import {HttpException} from '@nestjs/common';
import {Store,RecordData} from './store';
import type {Commerce} from './commerce';
import {testPaymentSettings} from './test-payments';
import {subscriptionRole} from './subscription-plans';
import {activatePeriods,basePeriod,createPeriod,DAY_MS,periodActive,periodPlan,userPeriods} from './subscription-periods';
import {bestDiscount,discountedPrice,useDiscount} from './personal-discounts';
function fail(code:string,message:string,status=409):never{throw new HttpException({error:{code,message,retryable:false}},status);}
const live=(r:RecordData,now:Date)=>['active','grace','canceled_at_period_end','scheduled'].includes(r.status)&&Date.parse(r.valid_until)>now.getTime();
export async function subscriptionState(store:Store,user:RecordData,now=new Date()){
 await activatePeriods(store,user,now);
 const periods=(await userPeriods(store,user)).filter(r=>live(r,now)),bases=periods.filter(basePeriod),current=bases.filter(r=>periodActive(r,now));
 const premium=periods.some(r=>periodActive(r,now)&&periodPlan(r)==='premium'&&(!r.is_upgrade||current.length>0)),standard=current.some(r=>periodPlan(r)==='standard');
 return {periods,bases,current,premium,standard,paid_until:bases.reduce((v,r)=>Math.max(v,Date.parse(r.valid_until)),now.getTime())};
}
async function contextKey(store:Store,user:RecordData,now=new Date()){
 const state=await subscriptionState(store,user,now),catalog=(await store.all('subscription_catalog',user.country))[0],settings=await testPaymentSettings(store,user.country,false);
 const discounts=(await store.select('referral_discount',user.country,{owner:user.id,limit:1000})).filter(d=>d.status==='active'&&d.valid_until>now.toISOString()).sort((a,b)=>a.id.localeCompare(b.id));
 const reservations=(await store.select('boost',user.country,{owner:user.id,limit:1000})).filter(b=>['reserved','payment_pending'].includes(b.status)&&b.reservation_expires_at>now.toISOString()&&b.price_snapshot?.discount_id).map(b=>[b.id,b.version]).sort();
 const context=createHash('sha256').update(JSON.stringify({reservations,role:subscriptionRole(user),catalog:catalog?.version??0,settings:settings.version,periods:state.periods.map(s=>[s.id,s.version,s.status]).sort(),discounts:discounts.map(d=>[d.id,d.version])})).digest('hex');
 return {state,catalog,settings,context};
}
export async function checkoutOffers(store:Store,commerce:Commerce,user:RecordData,now=new Date()){
 const {state,catalog,settings,context}=await contextKey(store,user,now),role=subscriptionRole(user);
 const raw=await commerce.offers(user.country,role,role==='executor'&&state.standard&&!state.premium);
 if(!settings.enabled||commerce.providers.billing.size)return {...raw,subscription_state:{paid_until:new Date(state.paid_until).toISOString(),premium:state.premium,standard:state.standard}};
 const prior=(await store.select('checkout_quote',user.country,{owner:user.id,limit:1000})).filter(q=>q.status==='available'&&q.context===context&&q.expires_at>now.toISOString());
 const templates:any[]=raw.items.filter(o=>o.is_test&&!(role==='executor'&&state.standard&&!state.premium&&o.plan==='premium')).map(o=>({...o,offer_kind:o.plan==='top100'?'addon':state.bases.length?'renewal':'purchase'}));
 if(role==='executor'&&state.standard&&!state.premium){
  const current=state.current.filter(s=>periodPlan(s)==='standard').sort((a,b)=>Date.parse(a.valid_until)-Date.parse(b.valid_until))[0];
  const futurePremium=state.bases.filter(s=>periodPlan(s)==='premium'&&Date.parse(s.valid_from??s.created_at)>now.getTime()).sort((a,b)=>Date.parse(a.valid_from??a.created_at)-Date.parse(b.valid_from??b.created_at))[0];
  const cap=futurePremium?Date.parse(futurePremium.valid_from??futurePremium.created_at):state.paid_until;
  const end=Math.max(Date.parse(current.valid_until),cap),standardPrice=catalog?.prices?.standard??100000,premiumPrice=catalog?.prices?.premium??150000;
  const duration=(end-now.getTime())/1000,amount=Math.ceil(Math.max(0,premiumPrice-standardPrice)*duration/(30*86400));
  const premiumOffer=raw.items.find(o=>o.plan==='premium'&&o.is_test);
  if(premiumOffer&&duration>0)templates.unshift({...premiumOffer,offer_kind:'upgrade',title:'Перейти на Премиум',amount_minor:amount,duration_seconds:duration,valid_until:new Date(end).toISOString()});
 }
 const offers=[];
 for(const t of templates){
  const found=prior.find(q=>q.plan===t.plan&&q.offer_kind===t.offer_kind);
  if(found){offers.push({...found.offer,id:found.id});continue;}
  const discount=await bestDiscount(store,user,t.plan,t.offer_kind,now),price=discountedPrice(t.amount_minor,discount);
  const topPeriods=state.periods.filter(s=>periodPlan(s)==='top100'),topEnd=topPeriods.reduce((v,s)=>Math.max(v,Date.parse(s.valid_until)),now.getTime());
  const from=t.offer_kind==='renewal'?new Date(state.paid_until).toISOString():t.offer_kind==='addon'&&topEnd>now.getTime()?new Date(topEnd).toISOString():null;
  const id=randomUUID(),offer={...t,...price,id,starts_at:from,valid_until:t.valid_until??(from?new Date(Date.parse(from)+30*DAY_MS).toISOString():null),duration_days:t.offer_kind==='upgrade'?null:30,auto_renew:false};
  const quote:RecordData={id,kind:'checkout_quote',owner:user.id,country:user.country,version:1,created_at:now.toISOString(),status:'available',context,plan:t.plan,offer_kind:t.offer_kind,expires_at:new Date(now.getTime()+5*60000).toISOString(),offer};
  await store.put(quote);offers.push(offer);
 }
 return {...raw,items:offers,subscription_state:{paid_until:new Date(state.paid_until).toISOString(),premium:state.premium,standard:state.standard},addons:(await commerce.plans(user.country)).addons};
}
export async function buyTestQuote(store:Store,commerce:Commerce,user:RecordData,b:any,now=new Date()){
 if(user.status!=='active')fail('FORBIDDEN','Аккаунт ограничен',403);
 if(b.accepted!==true)fail('CONSENT_REQUIRED','Подтвердите условия оплаты',403);
 const quote=await store.get(String(b.offer_id));
 if(!quote||quote.kind!=='checkout_quote'||quote.country!==user.country||quote.owner!==user.id)fail('OFFER_CHANGED','Предложение недоступно. Обновите условия оплаты');
 await store.db.query('SELECT pg_advisory_xact_lock(hashtextextended($1,0))',['subscription-periods:'+user.country+':'+user.id]);
 const activeMode=await testPaymentSettings(store,user.country,commerce.providers.billing.size>0);
 if(!activeMode.enabled||commerce.providers.billing.size)fail('TEST_PAYMENTS_UNAVAILABLE','Тестовая оплата выключена');
 if(quote.offer.role!==subscriptionRole(user))fail('OFFER_CHANGED','Выберите предложение текущей роли');
 if(quote.status==='consumed'){const subscription=await store.get(quote.subscription_id);if(subscription)return {subscription,is_test:true,duplicate:true};}
 const {state,settings,context}=await contextKey(store,user,now),offer=quote.offer;
 if(!settings.enabled||commerce.providers.billing.size)fail('TEST_PAYMENTS_UNAVAILABLE','Тестовая оплата выключена');
 if(quote.status!=='available'||quote.expires_at<=now.toISOString()||quote.context!==context)fail('OFFER_CHANGED','Цена или подписка изменилась. Обновите условия оплаты');
 if(b.amount_minor!==offer.amount_minor||b.currency!==offer.currency)fail('OFFER_CHANGED','Итоговая цена изменилась. Обновите условия оплаты');
 if(subscriptionRole(user)!==offer.role||!(user.roles??['customer']).includes(offer.role))fail('ROLE_REQUIRED','Выберите тариф текущей роли',403);
 if(user.verification!=='passed')fail('VERIFICATION_REQUIRED','Сначала подтвердите личность',403);
 if(offer.plan==='premium'&&offer.offer_kind!=='upgrade'&&state.standard&&!state.premium)fail('OFFER_CHANGED','Для перехода со Стандарта выберите немедленное повышение до Премиума с доплатой');
 if(offer.plan==='top100'&&(!state.standard||state.premium))fail('ENTITLEMENT_REQUIRED','Для отдельного Топ-100 нужен активный Стандарт',403);
 if(offer.offer_kind==='upgrade'&&(!state.standard||state.premium))fail('OFFER_CHANGED','Текущий тариф изменился');
 await useDiscount(store,user.id,user.country,offer,now);
 const seconds=offer.offer_kind==='upgrade'?(Date.parse(offer.valid_until)-now.getTime())/1000:30*86400;
 if(seconds<=0)fail('OFFER_CHANGED','Оплаченный период уже закончился');
 const subscription=await createPeriod(store,user,{plan:offer.plan,seconds,from:offer.starts_at??undefined,price:offer,provider:'test',is_test:true,is_upgrade:offer.offer_kind==='upgrade',quote_id:quote.id},now);
 const row=(kind:string,data:any):RecordData=>({id:randomUUID(),kind,owner:user.id,country:user.country,version:1,created_at:now.toISOString(),...data});
 await store.put(row('payment_transaction',{provider:'test',is_test:true,environment:'sandbox',transaction_id:randomUUID(),operation:'test_purchase',state:'active',benefit:'subscription',source_id:subscription.id,amount_minor:offer.amount_minor,original_amount_minor:offer.original_amount_minor,discount_id:offer.discount_id,discount_percent:offer.discount_percent,cash_amount_minor:0,currency:offer.currency,accepted_terms:true}));
 await store.put(row('audit',{actor_id:user.id,action:'billing.test_subscription_created',target_id:subscription.id,reason:'Подтверждённая пользователем имитация оплаты без списания денег',plan:offer.plan,offer_kind:offer.offer_kind}));
 await store.put({...quote,status:'consumed',subscription_id:subscription.id,version:quote.version+1});
 return {subscription,is_test:true,duplicate:false};
}
