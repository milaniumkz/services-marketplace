const {test}=require('node:test'),assert=require('node:assert/strict'),vm=require('node:vm'),fs=require('node:fs');
const source=fs.readFileSync(require('node:path').join(__dirname,'../apps/mobile/web/face-camera-native.js'),'utf8');
function fixture({denied=false}={}){
 const messages=[],events={},frames=[];let requests=0,stops=0,closes=0;const video={videoWidth:640,videoHeight:480,readyState:2,currentTime:1,play:async()=>{},pause(){},srcObject:null};
 const stream={getTracks:()=>[{stop(){stops++}}]},window={JobaFace:{postMessage:s=>messages.push(JSON.parse(s))},jobaCreateFaceTracker:async()=>({detect:()=>({faces:1}),close(){closes++}}),addEventListener:(n,f)=>events[n]=f};
 const document={hidden:false,querySelector:()=>video,addEventListener:(n,f)=>events[n]=f,createElement:()=>({getContext:()=>({drawImage(){}}),toDataURL:()=> 'data:image/jpeg;base64,/9j/'})};
 const context={window,document,navigator:{mediaDevices:{getUserMedia:async options=>{requests++;assert.equal(options.video.facingMode.exact,'user');assert.equal(options.audio,false);if(denied)throw Error('denied');return stream;}}},performance:{now:()=>1000},requestAnimationFrame:f=>frames.push(f)};vm.runInNewContext(source,context);
 return {messages,video,window,events,frames,get requests(){return requests},get stops(){return stops},get closes(){return closes}};
}
const tick=()=>new Promise(resolve=>setImmediate(resolve));
test('one front camera stream supplies all five frames, rejects repeated video times, and stops tracks/model on close',async()=>{
 const f=fixture();await tick();assert.equal(f.requests,1);assert.equal(f.messages[0].type,'ready');
 for(let step=0;step<5;step++){f.video.currentTime++;f.frames.shift()(1000+step*100);f.window.JobaNativeFace.capture(step);}
 assert.deepEqual(f.messages.filter(m=>m.type==='frame').map(m=>m.step),[0,1,2,3,4]);assert.equal(f.requests,1);const before=f.messages.length;f.frames.shift()(3000);assert.equal(f.messages.length,before);
 f.events.pagehide();assert.equal(f.stops,1);assert.equal(f.closes,1);assert.equal(f.video.srcObject,null);
});
test('permission rejection reports an actionable error and never returns a face frame',async()=>{const f=fixture({denied:true});await tick();assert.equal(f.messages.length,1);assert.equal(f.messages[0].type,'error');assert.equal(f.messages.some(m=>m.type==='frame'),false);});
