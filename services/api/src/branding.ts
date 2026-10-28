import sharp from 'sharp';
import { randomUUID, createHash } from 'node:crypto';
import { Readable } from 'node:stream';
import { ZipFile } from 'yazl';
import { Store, RecordData } from './store';
import { PrivateFiles } from './private-files';
import { HttpException } from '@nestjs/common';
function fail(code:string,message:string,status=422):never{throw new HttpException({error:{code,message,details:{},retryable:false}},status);}
const checksum=(bytes:Buffer)=>createHash('sha256').update(bytes).digest('hex');
const iosSlots=[
  ['iphone',20,2],['iphone',20,3],['iphone',29,2],['iphone',29,3],['iphone',40,2],['iphone',40,3],['iphone',60,2],['iphone',60,3],
  ['ipad',20,1],['ipad',20,2],['ipad',29,1],['ipad',29,2],['ipad',40,1],['ipad',40,2],['ipad',76,1],['ipad',76,2],['ipad',83.5,2],['ios-marketing',1024,1]
] as const;
const densities=[['mdpi',1],['hdpi',1.5],['xhdpi',2],['xxhdpi',3],['xxxhdpi',4]] as const;
export class Branding {
  constructor(private store:Store,private files:PrivateFiles){}
  async version(owner:string,country:string,uploadId:string,crop:any):Promise<RecordData> {
    const upload=await this.store.get(uploadId);
    if(!upload||upload.kind!=='upload'||upload.owner!==owner||upload.country!==country||upload.purpose!=='brand'||upload.status!=='clean'||upload.mime!=='image/png')fail('UNSAFE_UPLOAD','Нужен проверенный PNG-исходник');
    const bytes=await this.files.read(uploadId),meta=await sharp(bytes,{limitInputPixels:16777216}).metadata();
    if(meta.format!=='png'||!meta.width||!meta.height||meta.width<1024||meta.height<1024||meta.width>4096||meta.height>4096)fail('IMAGE_POLICY_REJECTED','Нужен PNG от 1024 до 4096 px по каждой стороне');
    const size=crop?.size??Math.min(meta.width,meta.height),left=crop?.left??Math.floor((meta.width-size)/2),top=crop?.top??Math.floor((meta.height-size)/2);
    if(![size,left,top].every(Number.isInteger)||size<1024||left<0||top<0||left+size>meta.width||top+size>meta.height)fail('INVALID_CROP','Проверьте квадратную обрезку');
    const source=await sharp(bytes).extract({left,top,width:size,height:size}).resize(1024,1024).flatten({background:'#ffffff'}).png().toBuffer();
    const id=randomUUID();await this.files.write(id,source);
    try{return await this.store.put({id,kind:'brand_icon',owner,country,version:1,created_at:new Date().toISOString(),status:'draft',source_upload_id:uploadId,crop:{left,top,size},source_file_id:id,source_checksum:checksum(source),source_dimensions:{width:meta.width,height:meta.height},release_status:'not_built'});}
    catch(error){await this.files.remove(id);throw error;}
  }
  private async background(source:Buffer){const rgb=await sharp(source).toColourspace('srgb').extract({left:0,top:0,width:1,height:1}).removeAlpha().raw().toBuffer();return '#'+Array.from(rgb).slice(0,3).map(value=>value.toString(16).padStart(2,'0')).join('');}
  async preview(r:RecordData,mask:string) {
    const source=await this.files.read(r.source_file_id);
    if(checksum(source)!==r.source_checksum)fail('SOURCE_CHANGED','Контрольная сумма исходника изменилась',409);
    if(!['ios','android-round','android-squircle'].includes(mask))fail('VALIDATION_ERROR','Неизвестная маска',400);
    const background=await this.background(source);
    const shape=mask==='android-round'?'<circle cx="128" cy="128" r="128"/>':'<rect width="256" height="256" rx="'+(mask==='ios'?56:64)+'"/>';
    const image=mask==='ios'?await sharp(source).resize(256,256).png().toBuffer():await sharp({create:{width:256,height:256,channels:4,background}}).composite([{input:await sharp(source).resize(178,178).png().toBuffer(),left:39,top:39}]).png().toBuffer();
    return sharp(image).composite([{input:Buffer.from('<svg width="256" height="256"><g fill="white">'+shape+'</g></svg>'),blend:'dest-in'}]).png().toBuffer();
  }
  async generate(r:RecordData) {
    if(r.status!=='approved'&&r.status!=='generated')fail('APPROVAL_REQUIRED','Сначала утвердите версию',409);
    if(r.status==='generated')return r;
    const source=await this.files.read(r.source_file_id);
    if(checksum(source)!==r.source_checksum)fail('SOURCE_CHANGED','Контрольная сумма исходника изменилась',409);
    const zip=new ZipFile(),output=zip.outputStream as Readable,variants:any[]=[],created:string[]=[];
    zip.on('error',error=>output.destroy(error));
    const add=async(path:string,bytes:Buffer,platform:string,pixels?:number)=>{
      zip.addBuffer(bytes,path);const id=randomUUID();created.push(id);await this.files.write(id,bytes);
      variants.push({path,platform,pixels,file_id:id,checksum:checksum(bytes),size:bytes.length});
    };
    try{
      const images=[];
      for(const [idiom,size,scale] of iosSlots){
        const filename=`Icon-${idiom}-${size}@${scale}x.png`,pixels=Math.round(size*scale);
        await add('ios/Assets.xcassets/AppIcon.appiconset/'+filename,await sharp(source).resize(pixels,pixels).removeAlpha().png().toBuffer(),'ios',pixels);
        images.push({idiom,size:`${size}x${size}`,scale:`${scale}x`,filename});
      }
      const info={author:'xcode',version:1};
      await add('ios/Assets.xcassets/AppIcon.appiconset/Contents.json',Buffer.from(JSON.stringify({images,info},null,2)),'ios');
      await add('ios/Assets.xcassets/Contents.json',Buffer.from(JSON.stringify({info})),'ios');
      const roundPreview=await this.preview(r,'android-round'),background=await this.background(source);
      for(const [density,scale] of densities){
        const legacy=Math.round(48*scale),canvas=Math.round(108*scale),safe=Math.round(46*scale),margin=Math.round((canvas-safe)/2);
        await add(`android/res/mipmap-${density}/ic_launcher.png`,await sharp(source).resize(legacy,legacy).png().toBuffer(),'android',legacy);
        await add(`android/res/mipmap-${density}/ic_launcher_round.png`,await sharp(roundPreview).resize(legacy,legacy).png().toBuffer(),'android',legacy);
        const foreground=await sharp({create:{width:canvas,height:canvas,channels:4,background:{r:0,g:0,b:0,alpha:0}}}).composite([{input:await sharp(source).resize(safe,safe).png().toBuffer(),left:margin,top:margin}]).png().toBuffer();
        await add(`android/res/mipmap-${density}/ic_launcher_foreground.png`,foreground,'android',canvas);
      }
      await add('android/res/values/joba_icon_background.xml',Buffer.from('<resources><color name="joba_icon_background">'+background+'</color></resources>'),'android');
      const adaptive=Buffer.from('<adaptive-icon xmlns:android="http://schemas.android.com/apk/res/android"><background android:drawable="@color/joba_icon_background"/><foreground android:drawable="@mipmap/ic_launcher_foreground"/></adaptive-icon>');
      await add('android/res/mipmap-anydpi-v26/ic_launcher.xml',adaptive,'android');
      await add('android/res/mipmap-anydpi-v26/ic_launcher_round.xml',adaptive,'android');
      await add('store/google-play-512.png',await sharp(source).resize(512,512).removeAlpha().png().toBuffer(),'store',512);
      const manifest={format_version:1,source_version_id:r.id,source_checksum:r.source_checksum,safe_zone_dp:66,source_square_dp:46,adaptive_canvas_dp:108,variants,release_status:'not_built'};
      zip.addBuffer(Buffer.from(JSON.stringify(manifest,null,2)),'manifest.json');
      const bundleId=randomUUID();created.push(bundleId);
      const written=this.files.writeStream(bundleId,output);zip.end();const size=await written;
      return await this.store.put({...r,status:'generated',variants,bundle_file_id:bundleId,bundle_size:size,version:r.version+1,generated_at:new Date().toISOString(),release_status:'not_built'});
    }catch(error){output.destroy();await Promise.all(created.map(id=>this.files.remove(id)));throw error;}
  }
}
