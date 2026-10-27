// Owner instruction 2026-10-27: both roles verify identity; customer plan is 500 KZT/30 days.
const {randomUUID,createHash}=require('node:crypto');
const pages=['Лицевая сторона удостоверения','Обратная сторона удостоверения','Селфи'];
const notice='Подписка заказчика открывает анкеты исполнителей и размещение заказов на 30 дней. В Казахстане базовая цена — 500 тенге. Исполнителю доступны Стандарт (1000 тенге на 30 дней) и Премиум (1500 тенге на 30 дней, включая приоритет услуг в Топ-100). Действует цена, показанная перед оплатой; владелец может менять будущие цены в админке. Завершение существующих заказов, переписки и поддержка сохраняются после окончания доступа. Обе роли проходят проверку удостоверения с двух сторон и селфи. Платёж считается подтверждённым только после проверки ответа подключённого платёжного провайдера.';
async function publishRoleAccess(store){
 await store.db.exec('BEGIN');
 try{
  await store.db.query('SELECT pg_advisory_xact_lock(1752138231)');const result=[];
  for(const country of ['KZ','KG','RU','BY']){
   if((await store.all('access_model_migration',country)).some(x=>x.model==='roles-2026-10-27')){result.push({country,status:'already_applied'});continue;}
   const owner='00000000-0000-4000-8000-000000000001',now=new Date().toISOString();
   const row=(kind,data)=>({id:randomUUID(),kind,owner,country,created_at:now,version:1,...data});
   const content='СОГЛАСИЕ НА ПРОВЕРКУ ЛИЧНОСТИ JOBA\n\nПроверка обязательна для заказчиков и исполнителей. Я передаю фотографии лицевой и обратной стороны удостоверения личности и отдельное селфи для рассмотрения уполномоченными сотрудниками JOBA. Удостоверение и исходные материалы доступны только мне и сотрудникам с правом проверки и не публикуются в профиле, поиске или переписке. Просмотры сотрудниками регистрируются в аудите.\n\nПосле одобрения из селфи создаётся отдельная фотография профиля без метаданных. Эта фотография отображается другим пользователям согласно настройкам видимости профиля; фотографии удостоверения для этого не используются. Автоматическое распознавание или сравнение лиц этим согласием не вводится. Исходные файлы хранятся в закрытом зашифрованном хранилище сервера. Сроки хранения определяются опубликованной политикой хранения; обращение об отзыве согласия или удалении данных доступно в разделе «Приватность» и через поддержку. Проверка и фотография профиля относятся к аккаунту и используются при смене роли без повторной загрузки.\n\nРеквизиты оператора и контакты для обращений публикуются в разделе «Контакты» и редактируются владельцем. Это согласие не подтверждает оплату подписки и не даёт прав платного доступа.';
   const doc=row('legal_document',{type:'verification_consent',locale:'ru',title:'Согласие на проверку личности и фото профиля',content,hash:createHash('sha256').update(content).digest('hex'),status:'published',published_at:now,publication_basis:'Owner-authorized identity and customer subscription change 2026-10-27',operator_details_pending:true});await store.put(doc);
   const old=(await store.all('verification_policy',country)).filter(x=>x.status==='effective');
   const types=old[0]?.payload?.document_types??['id_card'];
   for(const policy of old)await store.put({...policy,status:'superseded',version:policy.version+1});
   await store.put(row('verification_policy',{status:'effective',published_at:now,title:'Проверка обеих ролей: документ и селфи',payload:{...old[0]?.payload,document_id:doc.id,document_types:types,required_pages:Object.fromEntries(types.map(type=>[type,pages])),selfie_index:2}}));
   if(country==='KZ')for(const type of ['payments','public_offer']){
    const docs=(await store.all('legal_document',country)).filter(x=>x.type===type&&x.status==='published'&&x.locale==='ru').sort((a,b)=>String(b.published_at??b.created_at).localeCompare(String(a.published_at??a.created_at)));
    const original=docs[0];if(!original)continue;
    let body=String(original.content??'').split('\n').map(line=>/заказчик.{0,100}бесплат|возможности заказчика бесплат|подписка заказчика (отсутствует|не продаётся|не требуется)/i.test(line)?'':line).join('\n');
    body=body.replaceAll('выбранный исполнителем доступ','выбранный пользователем доступ').replaceAll('доступ исполнителя к функциям','доступ пользователя к функциям');
    const revised=notice+'\n\nУказанные условия заменяют прежние положения о бесплатном доступе заказчика к анкетам и размещению заказов.\n\n'+body;
    await store.put({...original,id:randomUUID(),owner,version:original.version+1,content:revised,hash:createHash('sha256').update(revised).digest('hex'),published_at:now,created_at:now,publication_basis:'Explicit owner change 2026-10-27'});
   }
   const marker=row('access_model_migration',{model:'roles-2026-10-27',status:'applied'});await store.put(marker);await store.put(row('audit',{action:'access_model.roles_published',target_id:marker.id,reason:'Owner requested customer 500 KZT / 30 days, executor tiers and three identity photographs'}));result.push({country,status:'applied'});
  }
  await store.db.exec('COMMIT');return result;
 }catch(e){await store.db.exec('ROLLBACK');throw e;}
}
module.exports={publishRoleAccess};
if(require.main===module){
 if(process.env.JOBA_ROLE_ACCESS!=='owner-authorized-2026-10-27')throw Error('Owner authorization marker required');
 const {Store}=require(process.env.JOBA_ROLE_STORE_MODULE||'../services/api/dist/store');const store=new Store();publishRoleAccess(store).then(result=>console.log(JSON.stringify(result))).catch(error=>{console.error(error.message);process.exitCode=1;}).finally(()=>store.close());
}
