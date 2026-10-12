import sharp from 'sharp';
import { randomUUID } from 'node:crypto';
import { Store, RecordData } from './store';
import { PrivateFiles } from './private-files';
import { HttpException } from '@nestjs/common';
function fail(code:string,message:string,status=422):never{throw new HttpException({error:{code,message,details:{},retryable:false}},status);};
export class Branding {
  constructor(private store:Store,private files:PrivateFiles){}
  async version(owner:string,country:string,uploadId:string,crop:any):Promise<RecordData> {
    const upload=await this.store.get(uploadId);if(!upload||upload.kind!=='upload'||upload.owner!==owner||upload.country!==country||upload.purpose!=='brand'||upload.status!=='clean')fail('UNSAFE_UPLOAD','Нужен проверенный исходник',422);
    const bytes=await this.files.read(uploadId),meta=await sharp(bytes,{limitInputPixels:16777216}).metadata();
    if(!meta.width||!meta.height||meta.width<1024||meta.height<1024)fail('IMAGE_TOO_SMALL','Исходник должен быть не меньше 1024×1024');
    const size=crop?.size??Math.min(meta.width,meta.height),left=crop?.left??Math.floor((meta.width-size)/2),top=crop?.top??Math.floor((meta.height-size)/2);
    if(![size,left,top].every(Number.isInteger)||size<1024||left<0||top<0||left+size>meta.width||top+size>meta.height)fail('INVALID_CROP','Проверьте квадратную обрезку');
    const source=await sharp(bytes).extract({left,top,width:size,height:size}).resize(1024,1024).flatten({background:'#ffffff'}).png().toBuffer();
    const id=randomUUID();await this.files.write(id,source);
    return this.store.put({id,kind:'brand_icon',owner,country,version:1,created_at:new Date().toISOString(),status:'draft',source_upload_id:uploadId,crop:{left,top,size},source_file_id:id});
  }
  async generate(r:RecordData) {
    if(r.status!=='approved'&&r.status!=='generated')fail('APPROVAL_REQUIRED','Сначала утвердите версию',409);
    if(r.status==='generated')return r;
    const bytes=await this.files.read(r.source_file_id),variants=[];
    for(const [platform,sizes] of [['ios',[20,29,40,60,76,83.5,1024]],['android',[48,72,96,144,192,512]]] as const)for(const size of sizes) {
      const pixels=Math.round(size*(platform==='ios'&&size!==1024?2:1)),id=randomUUID();
      await this.files.write(id,await sharp(bytes).resize(pixels,pixels).png().toBuffer());variants.push({platform,pixels,file_id:id});
    }
    return this.store.put({...r,status:'generated',variants,version:r.version+1,generated_at:new Date().toISOString(),release_status:'not_built'});
  }
}
