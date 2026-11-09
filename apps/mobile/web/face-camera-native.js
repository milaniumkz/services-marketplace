/* Dedicated first-party camera surface. No upload, analytics, ads or stored photos. */
(() => {
  const video=document.querySelector('video');let stream,tracker,stopped=false,last=-1,analyzed=-1;
  const send=value=>window.JobaFace?.postMessage(JSON.stringify(value));
  function stop(){stopped=true;stream?.getTracks().forEach(t=>t.stop());video.pause();video.srcObject=null;try{tracker?.close();}catch(_){}tracker=null;}
  window.JobaNativeFace={stop,capture(step){
    if(stopped||!video.videoWidth)return;
    const scale=Math.min(1,960/Math.max(video.videoWidth,video.videoHeight));
    const canvas=document.createElement('canvas');canvas.width=Math.round(video.videoWidth*scale);canvas.height=Math.round(video.videoHeight*scale);
    canvas.getContext('2d').drawImage(video,0,0,canvas.width,canvas.height);
    send({type:'frame',step,photo:canvas.toDataURL('image/jpeg',.85).split(',')[1],time:performance.now()});
  }};
  async function start(){try{
    stream=await navigator.mediaDevices.getUserMedia({audio:false,video:{facingMode:{exact:'user'},width:{ideal:1280},height:{ideal:1280}}});
    if(stopped){stream.getTracks().forEach(t=>t.stop());return;}
    video.srcObject=stream;await video.play();tracker=await window.jobaCreateFaceTracker();
    if(stopped){tracker.close();return;}send({type:'ready'});
    function tick(now){if(stopped)return;
      if(video.readyState>=2&&now-analyzed>=65&&video.currentTime!==last){
        analyzed=now;last=video.currentTime;
        try{send({type:'metrics',time:now,metrics:tracker.detect(video,now)});}catch(_){send({type:'error',message:'Не удалось обработать видео. Откройте камеру повторно.'});stop();}
      }
      if(!stopped)requestAnimationFrame(tick);
    }requestAnimationFrame(tick);
  }catch(_){send({type:'error',message:'Не удалось открыть фронтальную камеру. Разрешите камеру и повторите попытку.'});stop();}}
  window.addEventListener('pagehide',stop);document.addEventListener('visibilitychange',()=>{if(document.hidden)stop();});
  start();
})();
