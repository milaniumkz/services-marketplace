import {randomUUID} from 'node:crypto';
import {Store} from './store';
/** Owner-requested transition to approval valid until explicit revocation (28 Oct 2026). */
export async function migrateIdentityValidity(store:Store,country:string){
 const key='identity-until-revoked-v1';
 const marker=(await store.all('migration',country)).find(r=>r.key===key);if(marker)return {changed:0,restored:0};
 const checks=await store.all('verification',country);let changed=0,restored=0;
 for(const r of checks){
  if(!['passed','expired'].includes(r.status)||!r.reviewer_id||!r.decided_at||!r.expires_at||r.failure_code)continue;
  const user=await store.get(r.owner);if(!user||user.kind!=='user'||user.country!==country)continue;
  const decisions=checks.filter(v=>v.owner===r.owner&&v.decided_at).sort((a,b)=>String(b.decided_at).localeCompare(String(a.decided_at))||b.created_at.localeCompare(a.created_at));
  const policy=r.policy_id?await store.get(r.policy_id):undefined,document=policy?await store.get(policy.payload.document_id):undefined;
  const consents=document?(await store.all('consent',country)).filter(c=>c.owner===r.owner&&c.document_id===document.id).sort((a,b)=>(b.sequence??0)-(a.sequence??0)):[];
  const canRestore=r.status==='expired'&&user.status==='active'&&user.verification==='expired'&&decisions[0]?.id===r.id&&policy?.status==='effective'&&document?.status==='published'&&consents[0]?.accepted===true&&consents[0]?.document_hash===document.hash;
  if(r.status!=='passed'&&!canRestore)continue;
  const now=new Date().toISOString();
  await store.put({...r,status:canRestore?'passed':r.status,previous_expires_at:r.expires_at,expires_at:null,validity_policy:'until_revoked',validity_migrated_at:now,version:r.version+1});changed++;
  if(canRestore){await store.put({...user,verification:'passed',version:user.version+1});restored++;}
  await store.put({id:randomUUID(),kind:'audit',owner:'system',country,version:1,created_at:now,actor_id:'system',action:'verification.validity_migrated',target_id:r.id,reason:'Бессрочное подтверждение до ручного отзыва по указанию владельца; восстановление ранее одобренных, а не отклонённых проверок',before:{status:r.status,expires_at:r.expires_at},after:{status:canRestore?'passed':r.status,expires_at:null},account_restored:canRestore});
 }
 await store.put({id:randomUUID(),kind:'migration',owner:'system',country,version:1,created_at:new Date().toISOString(),key,status:'completed',changed,restored});return {changed,restored};
}
