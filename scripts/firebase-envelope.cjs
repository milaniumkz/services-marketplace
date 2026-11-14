// Hybrid encryption for a single identified Actions job. Plaintext only uses stdin/stdout
// captured by the caller; never invoke this helper directly in a CI logging step.
const crypto=require('node:crypto'),fs=require('node:fs');
const input=JSON.parse(fs.readFileSync(0,'utf8'));
try {
 if(input.mode==='encrypt') {
  const key=crypto.randomBytes(32),iv=crypto.randomBytes(12),cipher=crypto.createCipheriv('aes-256-gcm',key,iv);
  cipher.setAAD(Buffer.from(input.aad));
  const ciphertext=Buffer.concat([cipher.update(JSON.stringify(input.payload),'utf8'),cipher.final()]);
  const wrapped=crypto.publicEncrypt({key:crypto.createPublicKey({key:Buffer.from(input.public_key_der,'base64'),type:'spki',format:'der'}),padding:crypto.constants.RSA_PKCS1_OAEP_PADDING,oaepHash:'sha256'},key);
  process.stdout.write(JSON.stringify({aad:input.aad,wrapped_key:wrapped.toString('base64'),iv:iv.toString('base64'),tag:cipher.getAuthTag().toString('base64'),ciphertext:ciphertext.toString('base64')}));
 } else if(input.mode==='decrypt') {
  const key=crypto.privateDecrypt({key:fs.readFileSync(input.private_path),padding:crypto.constants.RSA_PKCS1_OAEP_PADDING,oaepHash:'sha256'},Buffer.from(input.envelope.wrapped_key,'base64'));
  const decipher=crypto.createDecipheriv('aes-256-gcm',key,Buffer.from(input.envelope.iv,'base64'));
  decipher.setAAD(Buffer.from(input.aad));decipher.setAuthTag(Buffer.from(input.envelope.tag,'base64'));
  process.stdout.write(Buffer.concat([decipher.update(Buffer.from(input.envelope.ciphertext,'base64')),decipher.final()]));
 } else throw Error();
} catch {process.stderr.write('Protected Firebase envelope rejected\n');process.exitCode=1;}
