export function staffApi({getSession,saveSession,getCountryScope=()=>undefined}) {
  const retryKeys=new Map(),pendingUploads=new Map(),rotations=new WeakMap();let refreshPending;
  const error=(message,code,status=0)=>Object.assign(new Error(message),{code,status});
  async function send(path,method,body,key,session,format='json'){
    if(getSession()!==session)throw error('Сессия изменилась. Повторите запрос.','SESSION_CHANGED',401);
    let response;
    try {
      response=await fetch('/api/v1'+path,{method,cache:'no-store',redirect:'error',signal:AbortSignal.timeout(20000),
        headers:{'Content-Type':body instanceof Blob?'application/octet-stream':'application/json',...(session?{Authorization:'Bearer '+session.access_token}:{}),...(key?{'Idempotency-Key':key}:{})},
        body:method==='GET'?undefined:body instanceof Blob?body:JSON.stringify(body)});
    }catch{throw error('Нет соединения с сервером. Повторите запрос.','NETWORK_ERROR');}
    if(getSession()!==session)throw error('Сессия изменилась. Повторите запрос.','SESSION_CHANGED',401);
    if(response.ok&&format==='blob'){const blob=await response.blob();if(getSession()!==session)throw error('Сессия изменилась. Повторите запрос.','SESSION_CHANGED',401);return blob;}
    let envelope;try{envelope=await response.json();}catch{throw error('Сервис вернул некорректный ответ.','INVALID_RESPONSE',response.status);}
    if(!response.ok)throw error(envelope.error?.message||'Ошибка сервиса',envelope.error?.code||'SERVER_ERROR',response.status);
    return envelope.data;
  }
  async function refresh(original){
    if(!refreshPending){
      const pending=send('/auth/refresh','POST',{refresh_token:original.refresh_token},undefined,original).then(result=>{
        if(getSession()!==original)throw error('Сессия изменилась. Повторите вход.','TOKEN_EXPIRED',401);
        const next={...original,...result};rotations.set(original,next);saveSession(next);
      }).catch(failure=>{if(failure.status===401&&getSession()===original)saveSession(undefined);throw failure;});
      refreshPending=pending.finally(()=>{refreshPending=undefined;});
    }
    return refreshPending;
  }
  const api=async function api(path,method='GET',body={},format='json',scopeOverride) {
    const original=getSession();
    const countryScope=scopeOverride??getCountryScope();
    if(countryScope&&(path.startsWith('/admin/')||path.startsWith('/uploads/'))&&!path.startsWith('/admin/access/')){const scoped=new URL(path,'https://joba.invalid');scoped.searchParams.set('admin_country',countryScope);path=scoped.pathname+scoped.search;}
    if(path.startsWith('/admin/')&&method!=='GET'&&body&&!(body instanceof Blob)&&typeof body==='object'&&!String(body.reason||'').trim())body={...body,reason:'Действие администратора в панели управления'};
    const cacheable=method!=='GET'&&!['/auth/login','/auth/staff-login','/auth/register','/auth/refresh'].includes(path);
    let fingerprint,key;
    if(cacheable){
      const digest=body instanceof Blob?[...new Uint8Array(await crypto.subtle.digest('SHA-256',await body.arrayBuffer()))].map(b=>b.toString(16).padStart(2,'0')).join(''):JSON.stringify(body);
      const input=new TextEncoder().encode((original?.user?.id||'anonymous')+':'+method+':'+path+':'+digest);
      fingerprint=[...new Uint8Array(await crypto.subtle.digest('SHA-256',input))].map(byte=>byte.toString(16).padStart(2,'0')).join('');
      key=retryKeys.get(fingerprint)||crypto.randomUUID();retryKeys.set(fingerprint,key);
      while(retryKeys.size>200)retryKeys.delete(retryKeys.keys().next().value);
    }
    try{
      let result;
      try{result=await send(path,method,body,key,original,format);}catch(failure){
        if(failure.status!==401||failure.code!=='TOKEN_EXPIRED'||!original?.refresh_token||['/auth/login','/auth/staff-login','/auth/register','/auth/refresh'].includes(path))throw failure;
        await refresh(original);const current=getSession();
        if(current?.user?.id!==original.user.id)throw error('Сессия изменилась. Повторите вход.','TOKEN_EXPIRED',401);
        result=await send(path,method,body,key,current,format);
      }
      if(fingerprint)retryKeys.delete(fingerprint);return result;
    }catch(failure){if(fingerprint&&failure.status>=400&&failure.status<500&&failure.status!==429)retryKeys.delete(fingerprint);throw failure;}
  };
  api.download=path=>api(path,'GET',{},'blob');
  api.upload=async (file,purpose='brand',country)=>{
    const uploadRequest=(path,method='GET',body={})=>api(path,method,body,'json',country);
    const original=getSession();
    const guard=()=>{let latest=original;while(latest&&rotations.has(latest))latest=rotations.get(latest);if(!latest||getSession()!==latest)throw error('Сессия изменилась. Повторите запрос.','SESSION_CHANGED',401);};
    guard();
    if(!['brand','banner','chat'].includes(purpose)||!(purpose==='chat'?['image/png','image/jpeg','application/pdf']:purpose==='banner'?['image/png','image/jpeg']:['image/png']).includes(file.type)||file.size>5*1024*1024)throw error(purpose==='chat'?'Нужны PNG, JPEG или PDF до 5 MB':purpose==='banner'?'Нужен PNG или JPEG до 5 MB':'Нужен PNG до 5 MB','POLICY_REJECTED',422);
    const digest=[...new Uint8Array(await crypto.subtle.digest('SHA-256',await file.arrayBuffer()))].map(b=>b.toString(16).padStart(2,'0')).join('');guard();
    const scope=original.user.id+':'+(country??getCountryScope()??original.user.country)+':'+purpose+':'+digest;
    let upload=pendingUploads.get(scope);
    const remember=result=>{guard();upload={...upload,...result};pendingUploads.set(scope,upload);return upload;};
    const metadata=()=>uploadRequest('/uploads/'+upload.id+'/metadata').then(remember);
    // A retry must use the server's state: the previous response may have been lost.
    if(upload)await metadata();
    else remember(await uploadRequest('/uploads/initiate','POST',{purpose,mime:file.type,size:file.size,content_sha256:digest}));
    if(upload.status==='initiated'){
      try{remember(await uploadRequest('/uploads/'+upload.id+'/content','PUT',file));}
      catch(failure){
        if(!['NETWORK_ERROR','INVALID_RESPONSE','STATE_CONFLICT'].includes(failure.code))throw failure;
        await metadata();if(upload.status==='initiated')throw failure;
      }
    }
    if(upload.status==='uploaded'){
      try{remember(await uploadRequest('/uploads/'+upload.id+'/finalize','POST'));}
      catch(failure){
        if(!['NETWORK_ERROR','INVALID_RESPONSE','STATE_CONFLICT','SCANNER_UNAVAILABLE'].includes(failure.code))throw failure;
        await metadata();if(upload.status==='uploaded')throw failure;
      }
    }
    const deadline=Date.now()+90000;
    while(['processing','scanning'].includes(upload.status)&&Date.now()<deadline){
      await new Promise(resolve=>setTimeout(resolve,1500));guard();await metadata();
    }
    if(['infected','rejected','failed'].includes(upload.status)){pendingUploads.delete(scope);throw error('Файл не прошёл проверку. Выберите другое изображение.','FILE_REJECTED',422);}
    if(upload.status!=='clean')throw error('Файл загружен и ещё проверяется. Повторите проверку чуть позже — заново загружать файл не нужно.','UPLOAD_PROCESSING',503);
    return upload;
  };
  return api;
}
