import { createCipheriv,createDecipheriv,randomBytes,createHmac } from 'node:crypto';
import { mkdir,readFile,writeFile } from 'node:fs/promises';
import { resolve } from 'node:path';
import { spawn } from 'node:child_process';
import { FileScanner } from './providers';

/** Storage is never mounted as a static web directory. Key material stays outside Git. */
export class PrivateFiles {
  private key?:Buffer;
  readonly directory:string;
  constructor(directory=process.env.JOBA_UPLOAD_DIR??resolve(__dirname,'../../../.local/private-files')) {this.directory=directory;}
  async initialize() {
    await mkdir(this.directory,{recursive:true,mode:0o700});
    if(process.env.JOBA_FILE_KEY){this.key=Buffer.from(process.env.JOBA_FILE_KEY,'hex');if(this.key.length!==32)throw Error('JOBA_FILE_KEY must be 32 bytes encoded as hex');return;}
    if(process.env.NODE_ENV==='production')throw Error('Production requires JOBA_FILE_KEY supplied outside Git');
    const path=resolve(this.directory,'storage.key');
    try {this.key=await readFile(path);}catch(e:any){if(e.code!=='ENOENT')throw e;this.key=randomBytes(32);try{await writeFile(path,this.key,{mode:0o600,flag:'wx'});}catch(writeError:any){if(writeError.code!=='EEXIST')throw writeError;this.key=await readFile(path);}}
    if(this.key.length!==32)throw Error('Invalid private storage key');
  }
  private path(id:string) {if(!/^[0-9a-f-]{36}$/i.test(id))throw Error('Invalid upload id');return resolve(this.directory,id+'.encrypted');}
  async write(id:string,data:Buffer) {
    if(!this.key)await this.initialize();
    const iv=randomBytes(12),cipher=createCipheriv('aes-256-gcm',this.key!,iv);
    const encrypted=Buffer.concat([cipher.update(data),cipher.final()]);
    await writeFile(this.path(id),Buffer.concat([iv,cipher.getAuthTag(),encrypted]),{mode:0o600});
  }
  async read(id:string) {
    if(!this.key)await this.initialize();const data=await readFile(this.path(id));
    const decipher=createDecipheriv('aes-256-gcm',this.key!,data.subarray(0,12));decipher.setAuthTag(data.subarray(12,28));
    return Buffer.concat([decipher.update(data.subarray(28)),decipher.final()]);
  }
  async requestDigest(body:string) {if(!this.key)await this.initialize();return createHmac('sha256',this.key!).update('joba-idempotency-v1\0').update(body).digest('hex');}
}
/** Configure a maintained ClamAV executable and signature database on the future server. */
export class ClamAvScanner implements FileScanner {
  constructor(private executable=process.env.JOBA_CLAMSCAN_PATH??'clamscan'){}
  async scan(file:Buffer):Promise<'clean'|'infected'> {
    return new Promise((resolve,reject)=>{
      const child=spawn(this.executable,['--no-summary','-'],{stdio:['pipe','ignore','ignore']});
      const timer=setTimeout(()=>{child.kill('SIGKILL');reject(Error('Antivirus timeout'));},30000);
      child.once('error',e=>{clearTimeout(timer);reject(e);});
      child.once('close',code=>{clearTimeout(timer);if(code===0)resolve('clean');else if(code===1)resolve('infected');else reject(Error('Antivirus unavailable or invalid signature database'));});
      child.stdin.on('error',()=>{});child.stdin.end(file);
    });
  }
}
