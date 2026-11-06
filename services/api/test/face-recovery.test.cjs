const {test}=require('node:test'),assert=require('node:assert/strict'),{randomUUID}=require('node:crypto');
const {Marketplace}=require('../dist/marketplace'),{Store}=require('../dist/store');
const {exportSnapshot}=require('../dist/privacy-export');
const photo=Buffer.from([255,216,255,0,1,2]).toString('base64');
const photos=['front','left','right','blink','smile'].map(step=>({step,photo}));
const vector=(index=0)=>Array.from({length:128},(_,i)=>i===index?1:0);
test('face recovery: consent, two failed passwords, encrypted account binding, single-use reset and session revocation',async()=>{
 let index=0,unavailable=false;
 const engine={enabled:true,describe:async(image)=>{if(unavailable)throw new (require('@nestjs/common').HttpException)({error:{code:'FACE_UNAVAILABLE',message:'Недоступно'}},503);return vector(image[image.length-1]===9?1:index);}};
 const api=new Marketplace(new Store('memory://'),undefined,undefined,engine);await api.initialize();
 const call=(account,method,path,body={})=>api.handle(method,path,body,account?'Bearer '+account.access_token:undefined,randomUUID(),{},'face-test-'+randomUUID());
 const reg=(phone)=>call(null,'POST','/auth/register',{country:'KZ',phone,password:'Original password 123'});
 const failure=async phone=>{try{await call(null,'POST','/auth/login',{country:'KZ',phone,password:'wrong password'});assert.fail('login should fail');}catch(e){assert.equal(e.getStatus(),401);return e.getResponse().error.details.face_recovery;}};
 const challenge=async phone=>{await failure(phone);const c=await failure(phone);assert.ok(c?.nonce);return c;};
 try{
 const a=await reg('+77000000871'),b=await reg('+77000000872');
 assert.equal((await call(a,'GET','/me/face-recovery')).prompt_required,true);
 await assert.rejects(()=>call(a,'POST','/me/face-recovery',{photos}),e=>e.getStatus()===422);
 await call(a,'POST','/me/face-recovery',{consent:true,photos});
 const saved=(await api.store.all('face_template','KZ'))[0];assert.ok(saved.encrypted_vector);assert.equal(saved.photo,undefined);assert.ok(!JSON.stringify(saved).includes(JSON.stringify(vector())));
 assert.equal((await call(a,'GET','/me/face-recovery')).enrolled,true);assert.equal(saved.sequence_version,2);
 await assert.rejects(()=>call(b,'POST','/me/face-recovery',{consent:true,photos:[...photos].reverse()}),e=>e.getStatus()===422);
 await assert.rejects(()=>call(b,'POST','/me/face-recovery',{consent:true,photos:photos.slice(0,4)}),e=>e.getStatus()===422);
 await assert.rejects(()=>call(a,'POST','/me/face-recovery',{consent:true,photos}),e=>e.getStatus()===403);
 // A template is bound to its account, even if someone copies its ciphertext.
 await assert.rejects(()=>api.files.unsealSecret(saved.encrypted_vector,'face-template:'+b.user.id));
 const beforeBad=saved.encrypted_vector;
 await assert.rejects(()=>call(a,'POST','/me/face-recovery',{consent:true,current_password:'Original password 123',photos:photos.map((p,i)=>i===2?{...p,photo:'invalid'}:p)}),e=>e.getResponse().error.message.includes('Направо'));
 assert.equal((await api.store.get(saved.id)).encrypted_vector,beforeBad);
 await assert.rejects(()=>call(b,'POST','/me/face-recovery',{consent:true,photos:photos.map((p,i)=>i===4?{...p,photo:Buffer.from([255,216,255,9]).toString('base64')}:p)}),e=>e.getStatus()===422);
 assert.equal((await api.store.all('face_template','KZ')).filter(r=>r.owner===b.user.id).length,0);
 const snap=await exportSnapshot(api.store,a.user.id,'KZ');assert.equal(snap.data.biometric_consent[0].accepted,true);assert.ok(!JSON.stringify(snap).includes(saved.encrypted_vector));
 assert.equal(await failure(a.user.phone),undefined);const c=await failure(a.user.phone);assert.ok(c.nonce);
 await assert.rejects(()=>call(null,'POST','/auth/face-recovery/verify',{...c,nonce:'bad',photos}),e=>e.getStatus()===403);
 index=1;assert.equal((await call(null,'POST','/auth/face-recovery/verify',{...c,photos})).verified,false);
 unavailable=true;await assert.rejects(()=>call(null,'POST','/auth/face-recovery/verify',{...c,photos}),e=>e.getStatus()===503);unavailable=false;
 index=0;const proof=await call(null,'POST','/auth/face-recovery/verify',{...c,photos});assert.equal(proof.verified,true);
 assert.equal((await call(null,'POST','/auth/face-recovery/verify',{...c,photos})).reset_token,proof.reset_token);
 await assert.rejects(()=>call(null,'POST','/auth/face-recovery/reset',{id:c.id,reset_token:'wrong',new_password:'New password 123'}),e=>e.getStatus()===403);
 assert.equal((await call(null,'POST','/auth/face-recovery/reset',{id:c.id,reset_token:proof.reset_token,new_password:'New password 123'})).changed,true);
 await assert.rejects(()=>call(null,'POST','/auth/face-recovery/reset',{id:c.id,reset_token:proof.reset_token,new_password:'Another password 123'}));
 await assert.rejects(()=>call(a,'GET','/me'),e=>e.getStatus()===401);
 await assert.rejects(()=>call(null,'POST','/auth/login',{country:'KZ',phone:a.user.phone,password:'Original password 123'}),e=>e.getStatus()===401);
 const logged=await call(null,'POST','/auth/login',{country:'KZ',phone:a.user.phone,password:'New password 123'});assert.equal(logged.user.id,a.user.id);
 const nextChallenge=await challenge(a.user.phone),nextProof=await call(null,'POST','/auth/face-recovery/verify',{...nextChallenge,photos});
 await call(logged,'POST','/me/password/change',{current_password:'New password 123',new_password:'Changed normally 123'});
 await assert.rejects(()=>call(null,'POST','/auth/face-recovery/reset',{id:nextChallenge.id,reset_token:nextProof.reset_token,new_password:'Stale reset 123'}));
 await call(logged,'DELETE','/me/face-recovery',{current_password:'Changed normally 123'});
 assert.equal((await api.store.get(saved.id)).encrypted_vector,null);
 const disabled=await challenge(a.user.phone);assert.equal((await call(null,'POST','/auth/face-recovery/verify',{...disabled,photos})).verified,false);
 const unknown=await challenge('+77000000879');assert.equal((await call(null,'POST','/auth/face-recovery/verify',{...unknown,photos})).verified,false);
 await call(b,'PATCH','/me/face-recovery');assert.equal((await call(b,'GET','/me/face-recovery')).prompt_required,false);
 // Existing accounts must supply their current password for their first reference.
 await api.store.put({...await api.store.get(b.user.id),created_at:new Date(Date.now()-86400000).toISOString()});
 await assert.rejects(()=>call(b,'POST','/me/face-recovery',{consent:true,photos}),e=>e.getStatus()===403);
 await call(b,'POST','/me/face-recovery',{consent:true,photos,current_password:'Original password 123'});
 const blocked=await challenge(b.user.phone);await api.store.put({...await api.store.get(b.user.id),admin_blocked:true});
 assert.equal((await call(null,'POST','/auth/face-recovery/verify',{...blocked,photos})).verified,false);
 await api.store.put({...await api.store.get(b.user.id),admin_blocked:false});
 const legacy=(await api.store.all('face_template','KZ')).find(r=>r.owner===b.user.id);
 await api.store.put({...legacy,sequence_version:1,encrypted_vector:await api.files.sealSecret(JSON.stringify(vector()),'face-template:'+b.user.id)});
 assert.equal((await call(b,'GET','/me/face-recovery')).update_required,true);
 const legacyChallenge=await challenge(b.user.phone);
 assert.equal((await call(null,'POST','/auth/face-recovery/verify',{...legacyChallenge,photos})).verified,true);

 }finally{await api.store.close();}
});
