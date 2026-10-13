import type { Store } from './store';
export const DEFAULT_SETTINGS={
  password_min:15,access_seconds:600,refresh_days:30,order_expiry_days:14,order_expiry_max_days:30,
  offer_expiry_hours:72,invite_expiry_hours:72,invite_daily_limit:10,auto_hold_minutes:60,review_blind_days:14,review_correction_hours:48,
  message_edit_minutes:15,portfolio_projects:20,portfolio_photos:10,upload_image_mb:5,upload_chat_mb:10,
  config_ttl_seconds:60,reward_late_hours:72,boost_reservation_minutes:10,
  ranking_window_days:30,ranking_dislike_weight:.5,ranking_age_days:30
};
export async function readSettings(store:Store,country:string) {const r=(await store.all('runtime_settings',country)).find(x=>x.status==='effective');return {...DEFAULT_SETTINGS,...r?.payload};}
export function validateSettings(settings:any) {
  if(!settings||typeof settings!=='object')throw Error('Нужен объект настроек');
  for(const [key,value] of Object.entries(settings)) {
    if(!(key in DEFAULT_SETTINGS)||typeof value!=='number'||!Number.isFinite(value)||value<=0||value>10000000)throw Error('Недопустимая настройка '+key);
    if(key!=='ranking_dislike_weight'&&!Number.isInteger(value))throw Error('Настройка должна быть целым числом: '+key);
  }
  if(settings.password_min!==undefined&&settings.password_min<15)throw Error('Минимальная длина пароля не ниже 15');
  if(settings.password_min>128||settings.access_seconds>3600||settings.refresh_days>90||settings.order_expiry_days>30||settings.order_expiry_max_days>30||settings.portfolio_photos>20||settings.upload_image_mb>50||settings.upload_chat_mb>50)throw Error('Настройка превышает безопасный предел');
  if(settings.order_expiry_days>settings.order_expiry_max_days)throw Error('Срок заказа превышает разрешённый максимум');
}
