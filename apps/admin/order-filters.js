import {orderStatuses} from './order-status.js';
export function orderFilters(values={},esc){
 const input=(label,name,type='text',attributes='')=>`<label class="formfield"><span>${label}</span><input name="${name}" type="${type}" aria-label="${label}" value="${esc(values[name]||'')}" ${attributes}></label>`;
 const select=(label,name,options)=>`<label class="formfield"><span>${label}</span><select name="${name}" aria-label="${label}">${options.map(([value,title])=>`<option value="${value}" ${values[name]===value?'selected':''}>${title}</option>`).join('')}</select></label>`;
 const yesno=[['','Все'],['yes','Да'],['no','Нет']];
 const advanced=['customer','executor','address','order_id','customer_id','executor_id','category_id','category','budget_min','budget_max','agreed_min','agreed_max','currency','work_mode','moderation_status','has_executor','has_photos','has_address','budget_mode','date_from','date_to'].some(k=>values[k]);
 return `<form id="list-filters" class="filters order-filters">${input('Поиск по ID, названию и описанию','q')}${select('Статус записи','status',[['','Все статусы'],...Object.entries(orderStatuses).filter(([k])=>k!=='deleted')])}${input('Город','city')}<details ${advanced?'open':''}><summary>Расширенные фильтры</summary><div class="formgrid">
 ${input('Заказчик — имя или ID','customer')}${input('Исполнитель — имя или ID','executor')}${input('Адрес содержит','address')}${input('ID заказа','order_id')}${input('ID заказчика','customer_id')}${input('ID исполнителя','executor_id')}${input('Категория — название','category')}${input('ID категории','category_id')}
 ${select('Валюта','currency',[['','Все валюты'],['KZT','Тенге — KZT'],['BYN','Белорусский рубль — BYN'],['RUB','Российский рубль — RUB'],['KGS','Сом — KGS']])}
 ${input('Бюджет от','budget_min','number','min="0" step="0.01"')}${input('Бюджет до','budget_max','number','min="0" step="0.01"')}${input('Согласованная сумма от','agreed_min','number','min="0" step="0.01"')}${input('Согласованная сумма до','agreed_max','number','min="0" step="0.01"')}
 ${select('Тип бюджета','budget_mode',[['','Любой'],['fixed','Указана сумма'],['negotiable','По договорённости']])}${select('Формат работы','work_mode',[['','Все форматы'],['onsite','На месте'],['remote','Удалённо'],['hybrid','Смешанный']])}${select('Исполнитель назначен','has_executor',yesno)}${select('Есть фотографии','has_photos',yesno)}${select('Есть адрес','has_address',yesno)}
 ${select('Модерация','moderation_status',[['','Все состояния'],['approved','Одобрено'],['pending_review','Ожидает проверки'],['pending_moderation','Ожидает модерации'],['quarantined','На проверке содержания'],['hidden','Скрыто'],['rejected','Отклонено'],['clean','Проверено']])}
 ${select('Тип даты','date_field',[['created_at','Создание'],['published_at','Публикация'],['started_at','Начало работы'],['completed_at','Завершение'],['cancelled_at','Отмена'],['expires_at','Истечение срока'],['updated_at','Обновление']])}${input('Дата с (UTC)','date_from','date')}${input('Дата по (UTC), включительно','date_to','date')}
 </div><p class="muted">Суммы указаны в единицах выбранной валюты. Для поиска по сумме во всех странах выберите валюту. Даты включают весь выбранный день по UTC.</p></details><button type="submit">Найти</button><button id="reset-filters" type="button">Сбросить</button></form>`;
}
export function orderFilterError(values,country){
 const amounts=['budget_min','budget_max','agreed_min','agreed_max'];
 if(country==='ALL'&&!values.currency&&amounts.some(key=>values[key]))return {field:'currency',message:'Для фильтра по сумме во всех странах выберите валюту.'};
 for(const prefix of ['budget','agreed'])if(values[prefix+'_min']&&values[prefix+'_max']&&Number(values[prefix+'_min'])>Number(values[prefix+'_max']))return {field:prefix+'_max',message:'Максимальная сумма должна быть не меньше минимальной.'};
 if(values.date_from&&values.date_to&&values.date_from>values.date_to)return {field:'date_to',message:'Конечная дата должна быть не раньше начальной.'};
 for(const field of ['order_id','customer_id','executor_id','category_id'])if(values[field]&&!/^[0-9a-f]{8}-[0-9a-f-]{27}$/i.test(values[field]))return {field,message:'Укажите корректный ID или очистите это поле.'};
 return null;
}
