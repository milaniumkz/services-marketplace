const {test}=require('node:test'),assert=require('node:assert/strict'),vm=require('node:vm'),fs=require('node:fs');
function fixture(){const scripts=[],timers=new Map(),calls=[];let sequence=0;const window={},host={isConnected:true};const document={createElement:()=>({dataset:{},remove(){this.removed=true;}}),head:{append:s=>scripts.push(s)},getElementById:()=>host};
 const context={window,document,MutationObserver:class{observe(){} disconnect(){}},setTimeout:(fn)=>{timers.set(++sequence,fn);return sequence;},clearTimeout:id=>timers.delete(id),console};vm.runInNewContext(fs.readFileSync('apps/mobile/web/joba-web-ads.js','utf8'),context);
 const manager={getPlatform:()=> 'touch',render:args=>calls.push(args)};
 return {window,scripts,timers,calls,manager,host,load(){window.Ya={Context:{AdvManager:manager}};for(const fn of window.yaContextCb)fn();}};
}
test('bridge does not contact Yandex on load; concurrent banner/platform operations load the SDK once for an active placement',async()=>{
 const f=fixture();assert.equal(f.scripts.length,0);const p=f.window.JobaWebAds.platform(),b=f.window.JobaWebAds.banner('host','R-A-20302217-1');assert.equal(f.scripts.length,1);assert.equal(f.scripts[0].src,'https://yandex.ru/ads/system/context.js');f.load();assert.equal(await p,'touch');for(let i=0;i<5;i++)await Promise.resolve();f.calls[0].onError({type:'warning'});f.calls[0].onRender({product:'rtb'});assert.equal(await b,true);assert.equal(f.calls[0].renderTo,'host');assert.equal(f.timers.size,0);
});
test('rewarded uses official platform and true callback only; no-fill, early close, timeout and repeated callbacks never become completion',async()=>{
 const f=fixture();f.window.Ya={Context:{AdvManager:f.manager}};
 const p=f.window.JobaWebAds.rewarded('R-A-20302217-2','touch');await Promise.resolve();assert.equal(f.calls[0].type,'rewarded');assert.equal(f.calls[0].platform,'touch');
 await assert.rejects(f.window.JobaWebAds.rewarded('R-A-20302217-2','touch'));
 f.calls[0].onRewarded(false);f.calls[0].onRewarded(true);assert.equal(await p,false);
 const complete=f.window.JobaWebAds.rewarded('R-A-20302217-3','desktop');await Promise.resolve();f.calls[1].onError({type:'warning'});f.calls[1].onRewarded(true);f.calls[1].onRewarded(false);assert.equal(await complete,true);
 const expired=f.window.JobaWebAds.rewarded('R-A-20302217-3','desktop');await Promise.resolve();for(const fn of [...f.timers.values()])fn();assert.equal(await expired,false);
 assert.equal(f.timers.size,0);
});
test('SDK failure is recoverable and invalid block IDs never load third-party code',async()=>{
 const f=fixture();await assert.rejects(f.window.JobaWebAds.banner('host','https://evil.invalid'));assert.equal(f.scripts.length,0);
 const p=f.window.JobaWebAds.platform();f.scripts[0].onerror();await assert.rejects(p);assert.equal(f.scripts[0].removed,true);
 const retry=f.window.JobaWebAds.platform();assert.equal(f.scripts.length,2);f.load();assert.equal(await retry,'touch');
 f.host.isConnected=false;const removed=f.window.JobaWebAds.banner('removed','R-A-20302217-1');await Promise.resolve();for(const fn of [...f.timers.values()])fn();assert.equal(await removed,false);assert.equal(f.calls.length,0);
});
