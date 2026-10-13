export function staffApi({getSession,saveSession}) {
  const retryKeys=new Map();let refreshPending;
  const error=(message,code,status=0)=>Object.assign(new Error(message),{code,status});
  async function send(path,method,body,key,session){
    let response;
    try {
      response=await fetch('/api/v1'+path,{method,redirect:'error',signal:AbortSignal.timeout(20000),
        headers:{'Content-Type':'application/json',...(session?{Authorization:'Bearer '+session.access_token}:{}),...(key?{'Idempotency-Key':key}:{})},
        body:method==='GET'?undefined:JSON.stringify(body)});
    }catch{throw error('Нет соединения с сервером. Повторите запрос.','NETWORK_ERROR');}
    if(getSession()!==session)throw error('Сессия изменилась. Повторите запрос.','SESSION_CHANGED',401);
    let envelope;try{envelope=await response.json();}catch{throw error('Сервис вернул некорректный ответ.','INVALID_RESPONSE',response.status);}
    if(!response.ok)throw error(envelope.error?.message||'Ошибка сервиса',envelope.error?.code||'SERVER_ERROR',response.status);
    return envelope.data;
  }
  async function refresh(original){
    if(!refreshPending){
      const pending=send('/auth/refresh','POST',{refresh_token:original.refresh_token},undefined,original).then(result=>{
        if(getSession()!==original)throw error('Сессия изменилась. Повторите вход.','TOKEN_EXPIRED',401);
        saveSession({...original,...result});
      }).catch(failure=>{if(failure.status===401&&getSession()===original)saveSession(undefined);throw failure;});
      refreshPending=pending.finally(()=>{refreshPending=undefined;});
    }
    return refreshPending;
  }
  return async function api(path,method='GET',body={}) {
    const original=getSession();
    const cacheable=method!=='GET'&&!['/auth/login','/auth/staff-login','/auth/register','/auth/refresh'].includes(path);
    let fingerprint,key;
    if(cacheable){
      const input=new TextEncoder().encode((original?.user?.id||'anonymous')+':'+method+':'+path+':'+JSON.stringify(body));
      fingerprint=[...new Uint8Array(await crypto.subtle.digest('SHA-256',input))].map(byte=>byte.toString(16).padStart(2,'0')).join('');
      key=retryKeys.get(fingerprint)||crypto.randomUUID();retryKeys.set(fingerprint,key);
      while(retryKeys.size>200)retryKeys.delete(retryKeys.keys().next().value);
    }
    try{
      let result;
      try{result=await send(path,method,body,key,original);}catch(failure){
        if(failure.status!==401||failure.code!=='TOKEN_EXPIRED'||!original?.refresh_token||['/auth/login','/auth/staff-login','/auth/register','/auth/refresh'].includes(path))throw failure;
        await refresh(original);const current=getSession();
        if(current?.user?.id!==original.user.id)throw error('Сессия изменилась. Повторите вход.','TOKEN_EXPIRED',401);
        result=await send(path,method,body,key,current);
      }
      if(fingerprint)retryKeys.delete(fingerprint);return result;
    }catch(failure){if(fingerprint&&failure.status&&failure.status<500)retryKeys.delete(fingerprint);throw failure;}
  };
}
