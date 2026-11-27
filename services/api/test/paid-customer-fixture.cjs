const {randomUUID}=require('node:crypto');
// Business lifecycle tests require a verified customer with a current role-scoped grant.
// This is isolated fixture state, not a payment or a production self-grant endpoint.
async function paidCustomer(api,session){
 const user=await api.store.get(session.user.id);
 await api.store.put({...user,verification:'passed'});
 await api.store.put({id:randomUUID(),kind:'grant',owner:user.id,country:user.country,version:1,created_at:new Date().toISOString(),valid_until:new Date(Date.now()+30*86400000).toISOString(),role:'customer',plan:'customer',capabilities:['view_contractors','publish_order'],source:'isolated_paid_customer_fixture'});
}
module.exports={paidCustomer};
