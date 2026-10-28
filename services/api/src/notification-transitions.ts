import type {RecordData,Store} from './store';
export const notificationTransitionKinds=new Set(['order','invite','offer','review','contractor','portfolio','subscription','refund_request','referral_reward','boost','support','cancel_request','amendment']);
export type Notify=(owner:string,country:string,type:string,target:string)=>Promise<void>;

/** Called within the business transaction; unchanged writes cannot duplicate events. */
export async function notifyTransition(store:Store,before:RecordData|undefined,after:RecordData,notify:Notify) {
 if(before&&before.version>=after.version)return;
 const changed=before?.status!==after.status;
 const send=async(owner:string|undefined,type:string)=>{if(owner)await notify(owner,after.country,type,after.id);};
 if(after.kind==='order'&&before){
  let type=changed?({open:'order.published',in_progress:before.status==='completion_requested'?'order.revision_requested':'order.started',completed:'order.completed',cancelled:'order.cancelled',expired:'order.expired'} as Record<string,string>)[after.status]:undefined;
  if(!changed&&after.status==='open'&&before.revision!==after.revision)type='order.updated';
  if(!type)return;
  const recipients=new Set<string>([after.owner,...after.executor_id?[after.executor_id]:[]]);
  if(['order.updated','order.cancelled','order.expired'].includes(type)){
   const offers=await store.db.query<{owner:string}>("SELECT owner FROM records WHERE kind='offer' AND country=$1 AND data->>'order_id'=$2 AND data->>'status' IN('active','selected') UNION SELECT data->>'recipient_id' AS owner FROM records WHERE kind='invite' AND country=$1 AND data->>'order_id'=$2 AND data->>'status'='pending'",[after.country,after.id]);
   for(const row of offers.rows)if(row.owner)recipients.add(row.owner);
  }
  for(const owner of recipients)await send(owner,type);
 }
 if(['cancel_request','amendment'].includes(after.kind)&&before&&changed&&after.status==='expired'){await send(after.owner,after.kind+'.expired');if(after.recipient_id!==after.owner)await send(after.recipient_id,after.kind+'.expired');}
 if(after.kind==='invite'&&before&&changed&&['accepted','declined','revoked','expired'].includes(after.status)){await notify(['accepted','declined'].includes(after.status)?after.owner:after.recipient_id,after.country,'invite.'+after.status,after.order_id);if(after.status==='expired'&&after.owner!==after.recipient_id)await notify(after.owner,after.country,'invite.expired',after.order_id);}
 if(after.kind==='offer'&&before&&changed&&after.status==='expired'){await send(after.owner,'offer.expired');const order=await store.read(after.order_id);if(order?.country===after.country)await notify(order.owner,after.country,'order.offer_expired',after.order_id);}
 if(after.kind==='offer'&&before&&!changed&&after.status==='active'&&['amount','note','proposed_start_at','duration_minutes'].some(k=>before[k]!==after[k])){const order=await store.read(after.order_id);if(order?.country===after.country)await notify(order.owner,after.country,'offer.updated',after.order_id);}
 if(after.kind==='review'&&before&&changed&&after.status==='published'&&!['quarantined','hidden','rejected'].includes(after.moderation_status))await send(after.target_id,'review.published');
 if(['contractor','portfolio'].includes(after.kind)&&before){
  const previous=before.draft?.status??before.status,current=after.draft?.status??after.status;
  if(['pending_review','pending_moderation'].includes(previous)&&['published','paused','rejected'].includes(current))await send(after.owner,after.kind+'.'+(current==='rejected'?'rejected':'approved'));
 }
 if(after.kind==='subscription'&&before&&!changed&&after.status==='active'&&Date.parse(after.valid_until)>Date.parse(before.valid_until))await send(after.owner,'subscription.renewed');
 if(after.kind==='subscription'&&changed)await send(after.owner,'subscription.'+(['active','expired','revoked'].includes(after.status)?after.status:'updated'));
 if(after.kind==='refund_request'&&changed&&['confirmed','failed','rejected'].includes(after.status))await send(after.owner,'refund.'+after.status);
 if(after.kind==='referral_reward'&&changed&&['available','redeemed','expired'].includes(after.status))await send(after.owner,'referral.'+after.status);
 if(after.kind==='boost'&&changed&&['active','expired','paused','revoked'].includes(after.status))await send(after.owner,'boost.'+after.status);
 if(after.kind==='support'&&before&&changed&&(after.status==='resolved'||before.status==='resolved'))await send(after.owner,after.status==='resolved'?'support.resolved':'support.reopened');
}
