export const subscriptionPlans=[
 {code:'standard',title:'Стандарт',duration_days:30,top100:false},
 {code:'premium',title:'Премиум',duration_days:30,top100:true},
] as const;
export function subscriptionPlan(code:unknown){return subscriptionPlans.find(p=>p.code===code)??subscriptionPlans[0];}
export function subscriptionCapabilities(code:unknown){return ['search_full','send_offer','publish_profile',...(code==='premium'?['top100']:[])];}
