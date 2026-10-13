import { createCipheriv,createDecipheriv,randomBytes,createHmac } from 'node:crypto';
import { mkdir,readFile,writeFile,open,rename,rm } from 'node:fs/promises';
import { createWriteStream } from 'node:fs';
import { Readable,Transform } from 'node:stream';
import { pipeline } from 'node:stream/promises';
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
  async readStream(id:string):Promise<Readable> {
    if(!this.key)await this.initialize();
    const handle=await open(this.path(id),'r');
    const header=Buffer.alloc(28);
    try {
      const result=await handle.read(header,0,28,0);if(result.bytesRead!==28)throw Error('Invalid encrypted file');
      const decipher=createDecipheriv('aes-256-gcm',this.key!,header.subarray(0,12));decipher.setAuthTag(header.subarray(12));
      pipeline(handle.createReadStream({start:28}),decipher).catch(error=>decipher.destroy(error));
      return decipher;
    }catch(error){await handle.close();throw error;}
  }
  async writeStream(id:string,source:Readable):Promise<number> {
    if(!this.key)await this.initialize();
    const destination=this.path(id),temporary=destination+'.pending-'+randomBytes(12).toString('hex');
    const iv=randomBytes(12),cipher=createCipheriv('aes-256-gcm',this.key!,iv);
    let size=0;
    const counter=new Transform({transform(chunk,_encoding,done){size+=chunk.length;done(null,chunk);}});
    try {
      const output=createWriteStream(temporary,{flags:'wx',mode:0o600});output.write(Buffer.concat([iv,Buffer.alloc(16)]));
      await pipeline(source,counter,cipher,output);
      const handle=await open(temporary,'r+');try{await handle.write(cipher.getAuthTag(),0,16,12);}finally{await handle.close();}
      await rename(temporary,destination);return size;
    }finally{await rm(temporary,{force:true});}
  }
  async remove(id:string){await rm(this.path(id),{force:true});}
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
