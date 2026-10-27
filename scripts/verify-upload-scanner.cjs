// Deployment smoke check: benign generated image, no account or identity documents.
const {resolve}=require('node:path');const {createRequire}=require('node:module');
async function main(){
 const root=process.env.JOBA_SCANNER_MODULE_ROOT||resolve(__dirname,'../services/api/dist');
 const fromAPI=createRequire(root+'/private-files.js'),{ClamAvScanner}=fromAPI(root+'/private-files.js');
 const bytes=await fromAPI('sharp')({create:{width:8,height:8,channels:3,background:'#245bdb'}}).jpeg().toBuffer();
 const result=await new ClamAvScanner().scan(bytes);
 if(result!=='clean')throw Error('Upload scanner did not accept the benign deployment image');
 console.log('Upload antivirus verified with a benign JPEG');
}
main().catch(error=>{console.error(error.message);process.exitCode=1;});
