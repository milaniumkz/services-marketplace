const {test}=require('node:test'),assert=require('node:assert/strict'),vm=require('node:vm');
const {bankReturnPage}=require('../dist/bank-return');
test('embedded bank return asks only its parent for scoped verification; standalone page retains a return link',()=>{
 const id='00000000-0000-4000-8000-000000000001',origin='https://joba.com.kz';
 const html=bankReturnPage(origin,id),script=html.match(/<script>([\s\S]+)<\/script>/)[1];
 assert.ok(html.includes(origin+'/?joba_payment='+id));
 for(const embedded of [true,false]){
  const messages=[],handlers={};const window={};window.parent=embedded?{postMessage:(...args)=>messages.push(args)}:window;
  vm.runInNewContext(script,{window,document:{getElementById:()=>({addEventListener:(type,callback)=>handlers[type]=callback})}});
  assert.equal(messages.length,embedded?1:0);
  let prevented=false;handlers.click({preventDefault(){prevented=true;}});assert.equal(prevented,embedded);
  if(embedded){assert.equal(messages[0][1],origin);assert.deepEqual(JSON.parse(JSON.stringify(messages[0][0])),{type:'joba.bank.return',payment_id:id});}
 }
});
