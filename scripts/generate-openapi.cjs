const {writeFileSync,mkdirSync}=require('node:fs');
const {resolve}=require('node:path');
const root=resolve(__dirname,'..');
const routes=[];
const add=(method,path,access='user',schema)=>routes.push({method,path,access,schema});
for(const name of ['register','login','staff-login','refresh'])add('POST','/auth/'+name,'public',name==='register'?'Registration':undefined);
for(const name of ['logout','logout-all'])add('POST','/auth/'+name);
for(const path of ['/public/config','/legal/documents'])add('GET',path,'public');
add('POST','/public/recovery-threads','public');for(const method of ['GET','POST'])add(method,'/public/recovery-threads/{id}/messages','recovery');
for(const path of ['/me','/me/sessions','/me/consents','/catalog/categories','/geo/cities','/me/monetization-config','/me/entitlements','/me/verification','/me/portfolio-projects','/contractors','/me/orders','/orders','/me/conversations','/me/support-threads','/me/notifications','/me/notification-preferences','/me/privacy-requests','/me/cases','/me/subscriptions','/me/referrals','/me/boosts','/boost-offers','/billing/offers','/top-listings','/events'])add('GET',path);
add('PATCH','/me');add('PATCH','/me/notification-preferences');add('PUT','/me/contractor-profile');
for(const path of ['/me/password/change','/me/phone-change-requests','/me/consents','/me/verification-sessions','/me/contractor-profile/publish','/me/portfolio-projects','/orders','/support/threads','/reviews','/me/privacy-requests','/cases','/reports','/me/blocks','/me/push-tokens','/me/notifications/read-all','/billing/verify-purchase','/billing/restore','/billing/refund-requests','/ads/reward-sessions','/referrals/attribute','/boost-reservations','/boost-purchases/verify','/uploads/initiate'])add('POST',path,'user',path==='/orders'?'OrderCreate':undefined);
for(const path of ['/me/sessions/{id}','/me/blocks/{id}','/me/push-tokens/{id}'])add('DELETE',path);
for(const path of ['/me/portfolio-projects/{id}','/orders/{id}','/offers/{id}','/messages/{id}','/reviews/{id}'])add('PATCH',path);
for(const path of ['/me/portfolio-projects/{id}','/messages/{id}'])add('DELETE',path);
for(const path of ['/me/portfolio-projects/{id}','/contractors/{id}','/contractors/{id}/portfolio','/customers/{id}','/users/{id}/reviews','/contractors/{id}/reviews','/customers/{id}/reviews','/orders/{id}','/orders/{id}/offers','/me/privacy-requests/{id}','/ads/reward-sessions/{id}'])add('GET',path);
for(const suffix of ['publish','cancel','start','extend','clone','invites','offers','select-offer','request-completion','confirm-completion','request-revision','cancel-requests','amendments','reviews'])add('POST','/orders/{id}/'+suffix,'user','VersionedCommand');
for(const suffix of ['acknowledge','withdraw'])add('POST','/offers/{id}/'+suffix,'user','VersionedCommand');
for(const base of ['cancel-requests','amendments'])add('POST','/'+base+'/{id}/respond','user','VersionedCommand');
add('GET','/me/order-invites');for(const suffix of ['respond','revoke'])add('POST','/order-invites/{id}/'+suffix,'user','VersionedCommand');
for(const base of ['conversations','support/threads'])for(const method of ['GET','POST'])add(method,'/'+base+'/{id}/messages','user',method==='POST'?'MessageCreate':undefined);
for(const suffix of ['read','delivered'])add('POST','/conversations/{id}/'+suffix);
for(const suffix of ['messages','appeals'])add('POST','/cases/{id}/'+suffix);
add('POST','/me/notifications/{id}/read');add('POST','/me/portfolio-projects/{id}/submit');add('POST','/me/verification-sessions/{id}/submit');add('POST','/me/referral-rewards/{id}/redeem');
for(const method of ['PUT','DELETE'])add(method,'/listing-votes/{type}/{id}');
add('PUT','/uploads/{id}/content');add('POST','/uploads/{id}/finalize');add('GET','/uploads/{id}/download');add('GET','/uploads/{id}/download-url');add('GET','/private-files/{id}','signed');
for(const type of ['billing','ads'])add('POST','/webhooks/'+type+'/{provider}','provider');
for(const path of ['/admin/dashboard','/admin/users','/admin/users/{id}','/admin/users/{id}/security-events','/admin/orders','/admin/support-threads','/admin/recovery-threads','/admin/cases','/admin/audit','/admin/blacklist','/admin/portfolio','/admin/verifications','/admin/privacy-requests','/admin/runtime-settings','/admin/boost-reports'])add('GET',path,'staff');
for(const path of ['/admin/runtime-settings','/admin/legal/documents','/admin/legal/documents/{id}/publish','/admin/users/{id}/blacklist','/admin/blacklist/{id}/decision','/admin/verifications/{id}/decision','/admin/auto-holds/{id}/decision','/admin/cases/{id}/resolve','/admin/cases/{id}/appeal-decision','/admin/entitlement-grants','/admin/entitlement-grants/{id}/approve','/admin/brand-icons','/admin/brand-icons/{id}/approve','/admin/brand-icons/{id}/generate','/admin/boost-grants','/admin/portfolio/{id}/decision','/admin/contractors/{id}/decision','/admin/recovery-threads/{id}/assign'])add('POST',path,'staff','VersionedCommand');
for(const base of ['support-threads','recovery-threads'])for(const method of ['GET','POST'])add(method,'/admin/'+base+'/{id}/messages','staff',method==='POST'?'MessageCreate':undefined);
add('POST','/admin/support-threads/{id}/commands','staff','VersionedCommand');
for(const method of ['GET','POST'])add(method,'/admin/support-threads/{id}/internal-notes','staff');
for(const config of ['categories','price-versions','monetization-configs','push-campaigns','referral-campaigns','moderation-dictionaries','ranking-configs','promotions','placement-policies','verification-policies','retention-policies']){
  add('GET','/admin/'+config,'staff');add('POST','/admin/'+config,'staff');
  for(const command of ['validate','preview','publish','stop','cancel','rollback'])add('POST','/admin/'+config+'/{id}/'+command,'staff','VersionedCommand');
}
const uuid={type:'string',format:'uuid'};
const schemas={
  Registration:{type:'object',required:['country','phone','password'],properties:{country:{type:'string',enum:['KZ','RS','RU','BY']},phone:{type:'string',pattern:'^\\+[1-9]\\d{7,14}$'},password:{type:'string',minLength:15,maxLength:128,writeOnly:true},display_name:{type:'string',minLength:2,maxLength:60},locale:{type:'string',enum:['ru','kk','sr','be']}}},
  VersionedCommand:{type:'object',properties:{expected_version:{type:'integer',minimum:1},reason:{type:'string',maxLength:3000}},additionalProperties:true},
  MessageCreate:{type:'object',required:['client_message_id','text'],properties:{client_message_id:uuid,text:{type:'string',minLength:1,maxLength:3000},upload_ids:{type:'array',items:uuid,maxItems:5}}},
  OrderCreate:{type:'object',required:['title','description','category_id'],properties:{title:{type:'string',minLength:5,maxLength:120},description:{type:'string',minLength:20,maxLength:5000},category_id:uuid,city:{type:'string',minLength:2,maxLength:100},city_id:uuid,budget_amount:{type:['integer','null'],minimum:0,description:'Legacy flat minor-unit amount; use budget for new clients.'},budget:{type:'object',properties:{mode:{enum:['fixed','hourly','per_unit','negotiable']},amount_minor:{type:'integer',minimum:0},currency:{enum:['KZT','RSD','RUB','BYN']}}},work_mode:{enum:['onsite','remote','hybrid']},attributes:{type:'object'},time_window:{type:'object',required:['start','end','time_zone'],properties:{start:{type:'string',format:'date-time'},end:{type:'string',format:'date-time'},time_zone:{type:'string'}}},upload_ids:{type:'array',items:uuid,maxItems:10}}},
  Envelope:{type:'object',required:['data','meta'],properties:{data:{},meta:{type:'object',required:['request_id','server_time'],properties:{request_id:uuid,server_time:{type:'string',format:'date-time'}}}}},
  Error:{type:'object',required:['error'],properties:{error:{type:'object',required:['code','message','request_id','retryable'],properties:{code:{type:'string'},message:{type:'string'},details:{type:'object'},request_id:uuid,retryable:{type:'boolean'}}}}}
};
const paths={};
for(const r of routes){
  const parameters=[...r.path.matchAll(/\{(\w+)\}/g)].map(m=>({name:m[1],in:'path',required:true,schema:m[1]==='id'?uuid:{type:'string'}}));
  if(!['GET'].includes(r.method)&&['user','staff'].includes(r.access))parameters.push({name:'Idempotency-Key',in:'header',required:true,schema:{type:'string',minLength:8,maxLength:128}});
  const security=r.access==='public'||r.access==='signed'?[]:r.access==='provider'?[{ProviderSignature:[]}]:[{BearerAuth:[]}];
  const op={operationId:r.method.toLowerCase()+'_'+r.path.replace(/[^A-Za-z0-9]+/g,'_'),tags:[r.path.split('/')[1]],description:r.access==='staff'?'Requires MFA and country-scoped staff permission. Sensitive identity reads require an additional permission.':r.access==='provider'?'Requires a registered server-side provider adapter and verified raw request evidence. Unconfigured providers return 503.':undefined,security,parameters,responses:{200:{description:'Successful command or query',content:{'application/json':{schema:{$ref:'#/components/schemas/Envelope'}}}},...Object.fromEntries([400,401,403,404,409,413,422,429,503].map(code=>[code,{description:'Structured error',content:{'application/json':{schema:{$ref:'#/components/schemas/Error'}}}}]))}};
  if(r.method!=='GET'&&r.method!=='DELETE')op.requestBody={required:true,content:r.path.endsWith('/content')?{'application/octet-stream':{schema:{type:'string',format:'binary'}}}:{'application/json':{schema:r.schema?{$ref:'#/components/schemas/'+r.schema}:{type:'object',additionalProperties:true}}}};
  op.responses={200:{$ref:'#/components/responses/Success'},...Object.fromEntries([400,401,403,404,409,413,422,429,503].map(code=>[code,{$ref:'#/components/responses/Failure'}]))};
  (paths[r.path]??={})[r.method.toLowerCase()]=op;
}
const document={openapi:'3.1.0',info:{title:'JOBA backend API',version:'0.1.0',description:'Development backend for JOBA specification 1.1. Provider integrations and production launch gates are intentionally closed until configured. Some command DTOs remain permissive during implementation; see docs/backend-status.md.'},servers:[{url:'/api/v1'}],paths,components:{schemas,responses:{Success:{description:'Successful command or query',content:{'application/json':{schema:{$ref:'#/components/schemas/Envelope'}}}},Failure:{description:'Structured error',content:{'application/json':{schema:{$ref:'#/components/schemas/Error'}}}}},securitySchemes:{BearerAuth:{type:'http',scheme:'bearer',description:'Opaque access token. Staff sessions additionally require verified MFA.'},ProviderSignature:{type:'apiKey',in:'header',name:'X-Provider-Signature',description:'Actual signature header and verification are provider-specific.'}}}};
mkdirSync(resolve(root,'docs/api'),{recursive:true});writeFileSync(resolve(root,'docs/api/openapi.json'),JSON.stringify(document,null,2)+'\n');
console.log('OpenAPI 3.1 inventory generated:',routes.length,'operations');
