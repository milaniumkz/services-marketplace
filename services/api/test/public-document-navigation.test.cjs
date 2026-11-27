const {test}=require('node:test'),assert=require('node:assert/strict'),vm=require('node:vm'),fs=require('node:fs');
test('legacy legal links resolve both on first load and after a fragment changes in the already open reader',()=>{
 const source=fs.readFileSync('apps/web/public/public-live.js','utf8'),events={},redirects=[];
 const location={pathname:'/site/W03.html',hash:'',search:'?country=BY',replace:value=>redirects.push(value)};
 vm.runInNewContext(source,{location,window:{addEventListener:(name,handler)=>events[name]=handler},document:{getElementById:()=>null}});
 assert.deepEqual(redirects,[]);location.hash='#terms';events.hashchange();assert.deepEqual(redirects,['/site/terms.html?country=BY']);
 location.hash='#privacy';events.hashchange();assert.equal(redirects.at(-1),'/site/privacy.html?country=BY');
 location.pathname='/site/terms.html';location.hash='#terms';events.hashchange();assert.equal(redirects.length,2);
});
