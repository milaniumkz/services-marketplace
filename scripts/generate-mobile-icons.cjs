const sharp=require('sharp');
const {readFileSync}=require('node:fs');
const {resolve}=require('node:path');
const root=resolve(__dirname,'../apps/mobile');
const source=resolve(root,'assets/joba-logo-original.jpeg');
async function main(){
  const jobs=[];
  for(const [density,size] of Object.entries({mdpi:48,hdpi:72,xhdpi:96,xxhdpi:144,xxxhdpi:192})) jobs.push(sharp(source).resize(size,size,{fit:'contain',background:'#ffffff'}).png().toFile(resolve(root,'android/app/src/main/res/mipmap-'+density+'/ic_launcher.png')));
  const ios=resolve(root,'ios/Runner/Assets.xcassets/AppIcon.appiconset');
  for(const icon of JSON.parse(readFileSync(resolve(ios,'Contents.json'),'utf8')).images){
    const size=Math.round(Number(icon.size.split('x')[0])*Number(icon.scale.replace('x','')));
    jobs.push(sharp(source).resize(size,size,{fit:'contain',background:'#ffffff'}).flatten({background:'#ffffff'}).png().toFile(resolve(ios,icon.filename)));
  }
  for(const size of [192,512])for(const mask of ['', '-maskable']) jobs.push(sharp(source).resize(size,size,{fit:'contain',background:'#ffffff'}).png().toFile(resolve(root,`web/icons/Icon${mask}-${size}.png`)));
  jobs.push(sharp(source).resize(32,32).png().toFile(resolve(root,'web/favicon.png')));
  await Promise.all(jobs);console.log('Mobile icon sizes generated from the original JOBA artwork');
}
main().catch(e=>{console.error(e.message);process.exitCode=1;});
