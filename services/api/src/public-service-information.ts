import {createHash,randomUUID} from 'node:crypto';
import {Store} from './store';
import {currentLegalDocuments} from './legal-documents';

// Correct only known, obsolete descriptions. Custom operator clauses and bank
// application documents are not replaced. Prior published versions stay intact.
export function currentServiceText(content:string):string {
 return content
  .replace(/В Казахстане базовая цена — 500 тенге\./g,'Актуальная стоимость указана в действующем каталоге услуг на странице «Услуги и стоимость» и перед подтверждением оплаты.')
  .replace(/в Казахстане базовая цена — 500 тенге\./g,'актуальная стоимость указана в действующем каталоге услуг и перед подтверждением оплаты.')
  .replace('Основные возможности заказчика бесплатны; подписка заказчика не продаётся.','Подписка заказчика предоставляет доступ к анкетам исполнителей и размещению заказов на 30 дней. Актуальная цена опубликована в каталоге услуг и показывается перед оплатой.')
  .replace('Собственные электронные услуги платформы JOBA: доступ исполнителя к функциям сервиса на определённый срок и отдельное продвижение допустимых карточек.','Собственные электронные услуги платформы JOBA: подписка заказчика, Стандарт и Премиум исполнителя на 30 дней, отдельное продвижение Топ-100 и другие предложения действующего каталога.')
  .replace('(для подписки — в роль исполнителя)','(в роль заказчика или исполнителя для выбранной подписки)')
  .replace('Платёжный провайдер ещё не подключён. До начала фактического приёма платежей этот документ описывает порядок обработки будущих обращений и не подтверждает наличие уже проведённых операций.','Режим оплаты и доступные способы показываются перед подтверждением покупки. В тестовой среде используются только тестовые карты банка; тестовая операция не подтверждает реальное списание. Возврат по реальной операции оформляется через обслуживающего её платёжного провайдера.')
  .replace('Платёжная интеграция находится в подготовке; название конкретного банка не является подтверждением подключения либо гарантией одобрения сайта этим банком.','Доступный платёжный провайдер и режим оплаты указываются перед подтверждением покупки. Название банка само по себе не подтверждает выполнение реального платежа.')
  .replace('Платёжные провайдеры, рекламная сеть и Firebase первоначально не подключены. Политика не является согласием на будущую передачу этим организациям. До подключения оператор должен определить получателей, страны, цели, состав данных, основания и необходимые отдельные согласия и обновить информацию для пользователя.','Для проведения оплаты подключённый банк получает сведения о платёжной операции: её идентификатор, сумму, валюту и назначение. Карточные реквизиты вводятся в защищённой форме банка. Для push-уведомлений используется Firebase Cloud Messaging (Google): токен устройства и технические сведения доставки. Для рекламы используются Яндекс и Google: IP-адрес, сведения об устройстве и браузере, рекламные идентификаторы и cookies в пределах настроек и применимых оснований. В параметрах рекламной интеграции JOBA не передаёт документы личности, селфи, телефон, переписку или платёжные реквизиты. Внешние сервисы могут обрабатывать данные за пределами страны пользователя; общая политика не заменяет отдельного согласия, когда оно требуется. Политики получателей: https://policies.google.com/privacy и https://yandex.ru/legal/confidential/. Настройки уведомлений и рекламы доступны в приложении.');
}
export async function refreshPublicServiceInformation(store:Store){
 await store.db.exec('BEGIN');
 try {
  await store.db.query('SELECT pg_advisory_xact_lock(1752138231)');
  for(const old of currentLegalDocuments(await store.all('legal_document','KZ'),'KZ','ru')){
   if(!['payments','public_offer','contacts','refunds','privacy','privacy_policy'].includes(old.type))continue;
   const content=currentServiceText(String(old.content??''));if(content===old.content)continue;
   const now=new Date().toISOString(),id=randomUUID();
   await store.put({...old,id,version:old.version+1,created_at:now,published_at:now,content,hash:createHash('sha256').update(content).digest('hex'),operator_contacts_only:false,operator_contact_previous_hashes:[],publication_basis:'Owner requested accurate public service information for bank review 2026-11-09'});
   await store.put({id:randomUUID(),kind:'audit',country:old.country,owner:old.owner,version:1,created_at:now,action:'legal.service_information_updated',target_id:id,source_id:old.id,reason:'Correct stale published service, price and provider descriptions; preserve previous version and operator details'});
  }
  await store.db.exec('COMMIT');
 }catch(e){await store.db.exec('ROLLBACK');throw e;}
}
