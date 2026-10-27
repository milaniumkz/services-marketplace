export const subscriptionPlans=[
 {code:'standard',role:'executor',title:'Стандарт',duration_days:30,top100:false},
 {code:'premium',role:'executor',title:'Премиум',duration_days:30,top100:true},
 {code:'customer',role:'customer',title:'Заказчик',duration_days:30,top100:false},
] as const;
export function subscriptionPlan(code:unknown){return subscriptionPlans.find(p=>p.code===code)??subscriptionPlans[0];}
export function subscriptionCapabilities(code:unknown){return code==='customer'?['view_contractors','publish_order']:['search_full','send_offer','publish_profile',...(code==='premium'?['top100']:[])];}
export function subscriptionRole(user:Record<string,any>){return user.active_role??(user.roles?.includes('executor')&&!user.roles?.includes('customer')?'executor':'customer');}
