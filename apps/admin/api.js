export function staffApi({getSession,saveSession}) {
  const retryKeys=new Map(),pendingUploads=new Map(),rotations=new WeakMap();let refreshPending;
  const error=(message,code,status=0)=>Object.assign(new Error(message),{code,status});
  async function send(path,method,body,key,session,format='json'){
    if(getSession()!==session)throw error('Сессия изменилась. Повторите запрос.','SESSION_CHANGED',401);
    let response;
    try {
      response=await fetch('/api/v1'+path,{method,redirect:'error',signal:AbortSignal.timeout(20000),
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
  const api=async function api(path,method='GET',body={},format='json') {
    const original=getSession();
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
    }catch(failure){if(fingerprint&&failure.status>=400&&failure.status<500)retryKeys.delete(fingerprint);throw failure;}
  };
  api.download=path=>api(path,'GET',{},'blob');
  api.upload=async file=>{
    const original=getSession();
    const guard=()=>{let latest=original;while(latest&&rotations.has(latest))latest=rotations.get(latest);if(!latest||getSession()!==latest)throw error('Сессия изменилась. Повторите запрос.','SESSION_CHANGED',401);};
    guard();
    if(file.type!=='image/png'||file.size>5*1024*1024)throw error('Нужен PNG до 5 MB','POLICY_REJECTED',422);
    const digest=[...new Uint8Array(await crypto.subtle.digest('SHA-256',await file.arrayBuffer()))].map(b=>b.toString(16).padStart(2,'0')).join('');guard();
    const scope=original.user.id+':'+original.user.country+':'+digest;
    let upload=pendingUploads.get(scope);
    if(!upload){upload=await api('/uploads/initiate','POST',{purpose:'brand',mime:file.type,size:file.size,content_sha256:digest});guard();pendingUploads.set(scope,upload);}
    if(upload.status!=='clean'){
      if(upload.status==='initiated'){await api('/uploads/'+upload.id+'/content','PUT',file);guard();}
      upload=await api('/uploads/'+upload.id+'/finalize','POST');guard();pendingUploads.set(scope,upload);
      if(upload.status!=='clean'){upload=await api('/uploads/'+upload.id+'/metadata');guard();pendingUploads.set(scope,upload);}
      if(upload.status!=='clean')throw error('Исходник ещё не прошёл проверку','SCANNER_UNAVAILABLE',503);
    }
    return upload;
  };
  return api;
}
