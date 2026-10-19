import {countryEnabled} from './country-access';
import { randomBytes,randomUUID } from 'node:crypto';
import { hash } from '@node-rs/argon2';
import { Store } from './store';
import { PrivateFiles } from './private-files';

const permissions=new Set(['platform_owner','bulk_restrict','administrator','content','moderator','senior_moderator','security','support','support_internal','phone_view','billing','campaign','moderator_manager','verification_reviewer','identity_view','promotion','brand_owner','release','auditor','privacy']);
function base32(bytes:Buffer){
 const alphabet='ABCDEFGHIJKLMNOPQRSTUVWXYZ234567';let bits=0,value=0,result='';
 for(const byte of bytes){value=(value<<8)|byte;bits+=8;while(bits>=5){result+=alphabet[(value>>>(bits-5))&31];bits-=5;}}
 if(bits)result+=alphabet[(value<<(5-bits))&31];return result;
}
/** Offline operator command only. Owner bootstrap is offline. Managed roles are assigned by the owner through the audited API. */
export async function bootstrapStaff(store:Store,files:PrivateFiles,input:any,saveEnrollment:(value:any)=>Promise<void>){
 if(!countryEnabled(input.country))throw Error('Select the matching regional country');
 if(input.locale!==undefined&&!['ru','kk','sr','be'].includes(input.locale))throw Error('Unsupported staff locale');
 if(typeof input.identifier!=='string'||!/^staff-[a-z0-9._-]{3,60}$/.test(input.identifier))throw Error('Use a separate staff identifier');
 if(typeof input.display_name!=='string'||input.display_name.trim().length<2||input.display_name.length>60)throw Error('Invalid staff display name');
 if(typeof input.password!=='string'||input.password.length<15||input.password.length>128)throw Error('Staff password requires 15–128 characters');
 if(!Array.isArray(input.permissions)||!input.permissions.length||input.permissions.some((value:string)=>!permissions.has(value)))throw Error('Explicit valid staff permissions required');
 if(typeof input.reason!=='string'||input.reason.trim().length<10||input.reason.length>1000)throw Error('An operator reason is required');
 const id=randomUUID(),secret=randomBytes(20),createdAt=new Date().toISOString();
 const sealed=await files.sealSecret(secret.toString('hex'),id);
 const enrollment={identifier:input.identifier,country:input.country,user_id:id,otpauth_uri:'otpauth://totp/'+encodeURIComponent('JOBA '+input.country+':'+input.identifier)+'?secret='+base32(secret)+'&issuer=JOBA&algorithm=SHA1&digits=6&period=30'};
 await store.db.exec('BEGIN');try{
  if((await store.db.query('SELECT 1 FROM credentials WHERE country=$1 AND phone=$2',[input.country,input.identifier])).rows.length)throw Error('Staff identifier already exists; existing accounts are preserved');
  await store.put({id,kind:'user',owner:id,country:input.country,version:1,created_at:createdAt,phone:input.identifier,phone_status:'not_applicable',display_name:input.display_name.trim(),city:'',locale:input.locale??'ru',roles:[],status:'active',staff_permissions:[...new Set(input.permissions)],totp_secret_sealed:sealed});
  await store.db.query('INSERT INTO credentials(country,phone,user_id,password_hash) VALUES($1,$2,$3,$4)',[input.country,input.identifier,id,await hash(input.password,{memoryCost:19456,timeCost:2,parallelism:1})]);
  await store.put({id:randomUUID(),kind:'audit',owner:id,country:input.country,version:1,created_at:createdAt,actor_id:id,action:'staff.bootstrap',target_id:id,reason:input.reason.trim(),occurred_at:createdAt});
  await saveEnrollment(enrollment);await store.db.exec('COMMIT');return {id,country:input.country};
 }catch(error){await store.db.exec('ROLLBACK');throw error;}
}
