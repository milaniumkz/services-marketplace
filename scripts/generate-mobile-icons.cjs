// Deterministic platform sizes from the approved artwork. Never crops or redraws it.
const sharp=require('sharp');
const fs=require('node:fs/promises');
const {readFileSync}=require('node:fs');
const {resolve,dirname}=require('node:path');
const {createHash}=require('node:crypto');
const root=resolve(__dirname,'..'),mobile=resolve(root,'apps/mobile');
const source=resolve(root,'branding/joba-source.png'),background='#202326';
const outputs=[];
async function write(path,bytes,size,role){await fs.mkdir(dirname(path),{recursive:true});await fs.writeFile(path,bytes);outputs.push({path:path.slice(root.length+1),pixels:size,role,bytes:bytes.length,sha256:createHash('sha256').update(bytes).digest('hex')});}
async function png(size){return sharp(source).resize(size,size,{fit:'contain',background,kernel:'lanczos3'}).removeAlpha().png({compressionLevel:9}).toBuffer();}
async function inset(size,fraction,alpha=false){const side=Math.floor(size*fraction),margin=Math.floor((size-side)/2);return sharp({create:{width:size,height:size,channels:4,background:alpha?{r:0,g:0,b:0,alpha:0}:background}}).composite([{input:await png(side),left:margin,top:margin}]).png({compressionLevel:9}).toBuffer();}
async function main(){
 const master=await png(4096);await write(resolve(root,'branding/joba-master-4096.png'),master,4096,'master');
 await write(resolve(mobile,'assets/joba-logo.png'),await png(512),512,'app-logo');
 const legacy=await sharp(source).resize(768,768,{fit:'contain',background}).jpeg({quality:96,chromaSubsampling:'4:4:4'}).toBuffer();
 for(const folder of ['apps/admin/public/assets','apps/web/public/assets','apps/web/assets','apps/client/public/assets','apps/client/assets']){
  await write(resolve(root,folder,'joba-logo.png'),await png(512),512,'web-logo');
  await write(resolve(root,folder,'joba-logo-192.png'),await png(192),192,'header-logo');
  await write(resolve(root,folder,'joba-logo-source.png'),await png(1024),1024,'branding-reference');
  await write(resolve(root,folder,'joba-favicon.png'),await png(48),48,'favicon');
  await write(resolve(root,folder,'joba-logo-original.jpeg'),legacy,768,'legacy-url');
 }
 await write(resolve(mobile,'assets/joba-logo-original.jpeg'),legacy,768,'legacy-source');
 for(const[density,scale]of Object.entries({mdpi:1,hdpi:1.5,xhdpi:2,xxhdpi:3,xxxhdpi:4})){
  const dir=resolve(mobile,'android/app/src/main/res/mipmap-'+density),size=Math.round(48*scale),canvas=Math.round(108*scale);
  await write(resolve(dir,'ic_launcher.png'),await png(size),size,'android-legacy');
  await write(resolve(dir,'ic_launcher_round.png'),await inset(size,.70),size,'android-round');
  // Full square inside the 66dp guaranteed-visible circle; no part of the artwork is clipped.
  await write(resolve(dir,'ic_launcher_foreground.png'),await inset(canvas,46/108,true),canvas,'android-adaptive');
  await write(resolve(mobile,'android/app/src/main/res/drawable-'+density+'/joba_launch_logo.png'),await png(Math.round(140*scale)),Math.round(140*scale),'android-launch');
 }
 const adaptive='<adaptive-icon xmlns:android="http://schemas.android.com/apk/res/android"><background android:drawable="@color/joba_icon_background"/><foreground android:drawable="@mipmap/ic_launcher_foreground"/></adaptive-icon>\n';
 const adaptiveDir=resolve(mobile,'android/app/src/main/res/mipmap-anydpi-v26');await fs.mkdir(adaptiveDir,{recursive:true});
 await fs.writeFile(resolve(adaptiveDir,'ic_launcher.xml'),adaptive);await fs.writeFile(resolve(adaptiveDir,'ic_launcher_round.xml'),adaptive);
 await fs.writeFile(resolve(mobile,'android/app/src/main/res/values/joba_icon_background.xml'),'<resources><color name="joba_icon_background">'+background+'</color></resources>\n');
 const ios=resolve(mobile,'ios/Runner/Assets.xcassets/AppIcon.appiconset');
 for(const icon of JSON.parse(readFileSync(resolve(ios,'Contents.json'),'utf8')).images){const size=Math.round(Number(icon.size.split('x')[0])*Number(icon.scale.replace('x','')));await write(resolve(ios,icon.filename),await png(size),size,'ios-icon');}
 const launch=resolve(mobile,'ios/Runner/Assets.xcassets/LaunchImage.imageset');
 for(const entry of JSON.parse(readFileSync(resolve(launch,'Contents.json'),'utf8')).images){if(entry.filename){const size=140*Number(entry.scale.replace('x',''));await write(resolve(launch,entry.filename),await png(size),size,'ios-launch');}}
 for(const size of [192,512]){
  for(const[name,bytes]of [['joba-',await png(size)],['joba-maskable-',await inset(size,.56)]])await write(resolve(mobile,`web/icons/${name}${size}.png`),bytes,size,'web-install');
  await write(resolve(mobile,`web/icons/Icon-${size}.png`),await png(size),size,'legacy-web-icon');
  await write(resolve(mobile,`web/icons/Icon-maskable-${size}.png`),await inset(size,.56),size,'legacy-web-maskable');
 }
 await write(resolve(mobile,'web/favicon-joba.png'),await png(48),48,'web-favicon');
 await write(resolve(mobile,'web/favicon.png'),await png(48),48,'legacy-favicon');
 await write(resolve(mobile,'web/icons/joba-180.png'),await png(180),180,'apple-touch');
 await write(resolve(root,'branding/google-play-512.png'),await png(512),512,'store');
 await write(resolve(root,'branding/app-store-1024.png'),await png(1024),1024,'store');
 await fs.writeFile(resolve(root,'branding/manifest.json'),JSON.stringify({source:'branding/joba-source.png',source_sha256:createHash('sha256').update(await fs.readFile(source)).digest('hex'),artwork:'full image preserved; resizing and platform padding only',outputs},null,2)+'\n');
 console.log(JSON.stringify({generated:outputs.length,master_pixels:4096,apk_built:false}));
}
main().catch(error=>{console.error(error.message);process.exitCode=1;});
