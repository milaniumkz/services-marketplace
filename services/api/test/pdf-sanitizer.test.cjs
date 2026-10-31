const {test}=require('node:test');
const assert=require('node:assert/strict');
const {PDFDocument,PDFName,PDFString}=require('pdf-lib');
const {PopplerPdfSanitizer}=require('../dist/pdf-sanitizer');
test('real PDF rendering preserves pages and removes active source objects',async()=>{
 const document=await PDFDocument.create();document.addPage([400,600]).drawText('Native renderer validation',{x:30,y:300});document.addPage([600,400]).drawText('Second page',{x:30,y:200});
 document.setAuthor('Private original author');
 document.catalog.set(PDFName.of('OpenAction'),document.context.obj({S:PDFName.of('JavaScript'),JS:PDFString.of('app.alert("isolated test only")')}));
 document.getForm().createTextField('private-original-field').setText('Original form value');
 const source=Buffer.from(await document.save());
 const sanitizer=new PopplerPdfSanitizer('/usr/bin/pdftoppm','/usr/bin/pdfinfo');
 const safe=await sanitizer.sanitize(source);const output=await PDFDocument.load(safe);
 assert.equal(output.getPageCount(),2);assert.equal(output.catalog.has(PDFName.of('OpenAction')),false);assert.equal(output.catalog.has(PDFName.of('AcroForm')),false);assert.equal(output.getAuthor(),undefined);
 assert.deepEqual(output.getPages().map(page=>[page.getWidth(),page.getHeight()]),[[400,600],[600,400]]);
 await assert.rejects(()=>sanitizer.sanitize(Buffer.from('%PDF-invalid')),/could not be processed/);
 const oversized=await PDFDocument.create();for(let i=0;i<21;i++)oversized.addPage([400,600]);
 const oversizedBytes=Buffer.from(await oversized.save());await assert.rejects(()=>sanitizer.sanitize(oversizedBytes),/page or encryption policy/);
});
