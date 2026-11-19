export const subscriptionPlans=[
 {code:'standard',role:'executor',title:'Стандарт',duration_days:30,top100:false},
 {code:'premium',role:'executor',title:'Премиум',duration_days:30,top100:true},
 {code:'customer',role:'customer',title:'Заказчик',duration_days:30,top100:false},
] as const;
export const top100Addon={code:'top100',role:'executor',title:'Топ-100 отдельно',duration_days:30,top100:true,addon:true} as const;
export function subscriptionPlan(code:unknown){if(code==='top100')return top100Addon;return subscriptionPlans.find(p=>p.code===code)??subscriptionPlans[0];}
export function subscriptionCapabilities(code:unknown){return code==='top100'?['top100']:code==='customer'?['view_contractors','publish_order']:['search_full','send_offer','publish_profile',...(code==='premium'?['top100']:[])];}
export function subscriptionRole(user:Record<string,any>){return user.active_role??(user.roles?.includes('executor')&&!user.roles?.includes('customer')?'executor':'customer');}
