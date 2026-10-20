import { spawn } from 'node:child_process';
import { mkdtemp,readdir,readFile,rm,stat } from 'node:fs/promises';
import { join } from 'node:path';
import { tmpdir } from 'node:os';
import { PDFDocument } from 'pdf-lib';
import { PdfSanitizer } from './providers';

function execute(executable:string,args:string[],input:Buffer,timeout=30000):Promise<string>{
 return new Promise((resolve,reject)=>{
  const child=spawn(executable,args,{stdio:['pipe','pipe','ignore'],env:{PATH:process.env.PATH,LANG:'C'}});
  let output='',settled=false;
  const finish=(error?:Error)=>{if(settled)return;settled=true;clearTimeout(timer);error?reject(error):resolve(output);};
  const timer=setTimeout(()=>{child.kill('SIGKILL');finish(Error('PDF processing timeout'));},timeout);
  child.once('error',()=>finish(Error('PDF processor unavailable')));
  child.stdout.on('data',chunk=>{output+=chunk.toString();if(output.length>65536){child.kill('SIGKILL');finish(Error('PDF metadata limit exceeded'));}});
  child.once('close',code=>finish(code===0?undefined:Error('PDF could not be processed')));
  child.stdin.on('error',()=>{});child.stdin.end(input);
 });
}
/** Render pages and build a new image-only PDF; source actions, links and attachments are never copied. */
export class PopplerPdfSanitizer implements PdfSanitizer {
 constructor(private renderer=process.env.JOBA_PDFTOPPM_PATH??'pdftoppm',private inspector=process.env.JOBA_PDFINFO_PATH??'pdfinfo'){}
 async sanitize(source:Buffer):Promise<Buffer>{
  if(source.length>10*1024*1024)throw Error('PDF input size limit exceeded');
  const info=await execute(this.inspector,['-f','1','-l','20','-'],source);
  // Metadata precedes Poppler's own fields; taking the last page field prevents title injection.
  const pages=Number([...info.matchAll(/^Pages:\s+(\d+)\s*$/gm)].at(-1)?.[1]);
  if(!Number.isInteger(pages)||pages<1||pages>20||/^Encrypted:\s+yes/m.test(info))throw Error('PDF page or encryption policy rejected');
  const dimensions=new Map<number,[number,number]>();for(const match of info.matchAll(/^Page\s+(?:(\d+)\s+)?size:\s+([\d.]+) x ([\d.]+) pts/gm))dimensions.set(Number(match[1]??1),[Number(match[2]),Number(match[3])]);
  const rotations=new Map<number,number>();for(const match of info.matchAll(/^Page\s+(?:(\d+)\s+)?rot:\s+(-?\d+)/gm))rotations.set(Number(match[1]??1),Number(match[2]));
  const directory=await mkdtemp(join(tmpdir(),'joba-pdf-'));
  try{
   await execute(this.renderer,['-jpeg','-jpegopt','quality=85','-scale-to','2048','-f','1','-l',String(pages),'-',join(directory,'page')],source);
   const names=(await readdir(directory)).filter(name=>/^page-\d+\.jpg$/.test(name)).sort((a,b)=>Number(a.match(/\d+/)![0])-Number(b.match(/\d+/)![0]));
   if(names.length!==pages)throw Error('PDF page rendering incomplete');
   const document=await PDFDocument.create();let total=0;
   for(const name of names){
    const path=join(directory,name);total+=(await stat(path)).size;if(total>10*1024*1024)throw Error('PDF output size limit exceeded');
    const image=await document.embedJpg(await readFile(path));
    let [width,height]=dimensions.get(Number(name.match(/\d+/)![0]))??[image.width*72/150,image.height*72/150];
    const rotation=rotations.get(Number(name.match(/\d+/)![0]))??0;if(Math.abs(rotation)%180===90)[width,height]=[height,width];
    if(!Number.isFinite(width)||!Number.isFinite(height)||width<18||height<18||width>2000||height>2000)throw Error('PDF page dimensions rejected');
    const page=document.addPage([width,height]);page.drawImage(image,{x:0,y:0,width,height});
   }
   document.setProducer('JOBA safe document renderer');document.setCreator('JOBA');
   const result=Buffer.from(await document.save());if(result.length>10*1024*1024)throw Error('PDF output size limit exceeded');return result;
  }finally{await rm(directory,{recursive:true,force:true});}
 }
}
