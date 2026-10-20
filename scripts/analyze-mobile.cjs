const {spawn}=require('node:child_process');
const {createInterface}=require('node:readline');
const {resolve}=require('node:path');
const sdk=process.env.FLUTTER_ROOT||'/workspace/flutter-sdk';
const root=resolve(__dirname,'../apps/mobile');
const server=spawn(sdk+'/bin/cache/dart-sdk/bin/dart',[sdk+'/bin/cache/dart-sdk/bin/snapshots/analysis_server.dart.snapshot','--cache=/workspace/.dart-analysis','--suppress-analytics'],{cwd:root,stdio:['pipe','pipe','inherit']});
const errors=new Map();let analyzing=false,finished=false,id=0;
const send=(method,params={})=>server.stdin.write(JSON.stringify({id:String(++id),method,params})+'\n');
const timer=setTimeout(()=>{console.error('Analysis did not complete');server.kill();process.exitCode=1;},60000);
createInterface({input:server.stdout}).on('line',line=>{
  const r=JSON.parse(line);
  if(r.event==='server.connected'){send('server.setSubscriptions',{subscriptions:['STATUS']});send('analysis.setAnalysisRoots',{included:[root],excluded:[root+'/build']});}
  if(r.event==='analysis.errors') errors.set(r.params.file,r.params.errors);
  if(r.event==='server.status'){
    if(r.params.analysis?.isAnalyzing) analyzing=true;
    if(analyzing&&r.params.analysis?.isAnalyzing===false&&!finished){finished=true;clearTimeout(timer);let count=0;
      for(const [file,list] of errors)for(const e of list){console.log(file+':'+e.location.startLine+' '+e.severity+' '+e.message);count++;}
      console.log('Mobile analysis completed:',count,'issues');process.exitCode=count?1:0;send('server.shutdown');
    }
  }
});
server.on('exit',code=>{clearTimeout(timer);if(!finished)process.exitCode=code||1;});
