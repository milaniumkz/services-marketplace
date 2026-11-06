// Generate crawlable, JS-independent legal pages from the same sources used for publication.
const {readFileSync,writeFileSync}=require('node:fs');
const {resolve}=require('node:path');
const root=resolve(__dirname,'..'),web=resolve(root,'apps/web');
const pages={privacy:['W03.html','Политика конфиденциальности'],payments:['W06.html','Условия оплаты'],refunds:['W07.html','Возврат и отмена'],public_offer:['W08.html','Публичная оферта'],contacts:['W09.html','Реквизиты и контакты']};
const esc=s=>s.replace(/[&<>"']/g,c=>({'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;',"'":'&#39;'}[c]));
const source=readFileSync(resolve(web,'W03.html'),'utf8');
for(const [type,[file,title]] of Object.entries(pages)){
 const content=readFileSync(resolve(root,'docs/legal/kz/'+type+'.ru.txt'),'utf8');
 const menu=Object.entries(pages).map(([key,[href,label]])=>`<a href="${href}"${key===type?' class="selected"':''}>${label}</a>`).join('')+'<a href="W03.html#terms">Условия использования</a><a href="W03.html#community">Правила сообщества</a><a href="W04.html">Удаление аккаунта</a>';
 let html=source.replace(/<title>.*?<\/title>/,`<title>${title} · JOBA</title>`).replace(/<body\b[^>]*>/,'<body data-legal-type="'+type+'">').replace(/<h1 class="page-title">.*?<\/h1>/,`<h1 class="page-title">${title}</h1>`).replace(/<nav class="legal-menu"[\s\S]*?<\/nav>/,`<nav class="legal-menu" aria-label="Документы">${menu}</nav>`).replace(/<article class="legal-paper"[\s\S]*?<\/article>/,`<article class="legal-paper" id="${type}"><h2>${title}</h2><p class="caption muted">Казахстан · Русский · редакция сайта. Реквизиты оператора заполняются до начала приёма платежей.</p><div class="legal-content">${esc(content).replace(/[ \t]+$/gm,'')}</div></article>`).replace(/<span class="badge amber">.*?<\/span>/,'<span class="badge amber">Редакция сайта</span>');
 writeFileSync(resolve(web,file),html);
}
// Every public page exposes the commercial information without requiring sign-in.
for(const file of ['index.html','W01.html','W02.html','W03.html','W04.html','W05.html','W06.html','W07.html','W08.html','W09.html']){
 let html=readFileSync(resolve(web,file),'utf8');html=html.replace(/<a href="W06.html">Условия оплаты<\/a><a href="W07.html">Возврат и отмена<\/a><a href="W08.html">Публичная оферта<\/a><a href="W09.html">Реквизиты и контакты<\/a>/g,'');html=html.replace('<div class="footer-links">','<div class="footer-links"><a href="W06.html">Условия оплаты</a><a href="W07.html">Возврат и отмена</a><a href="W08.html">Публичная оферта</a><a href="W09.html">Реквизиты и контакты</a>');writeFileSync(resolve(web,file),html);
}
console.log('Public legal pages generated from KZ source documents.');
