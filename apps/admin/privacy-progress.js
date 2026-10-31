const stageLabels={security:'События безопасности',notifications:'Уведомления',documents:'История проверки личности',optional_consents:'Необязательные согласия',support:'Поддержка и материалы дел',case_text:'Переписка и протоколы дел',work:'Закрытые заказы и переписки',work_files:'Физическое удаление вложений'};
const states={physically_purged:'Байты удалены',waiting_references_retention_or_retry:'Ожидание ссылок, срока или повтора удаления',awaiting_policy:'Нужен опубликованный срок хранения',awaiting_account_deletion:'Аккаунт ещё не удалён',minimized:'Минимизация этого этапа выполнена',waiting_retention_or_protection:'Ожидание срока или снятия защиты',waiting_retention_files_protection_or_review:'Ожидание срока, удаления файлов, снятия защиты или разбора старых данных',waiting_retention_protection_or_review:'Ожидание срока, снятия защиты или разбора старых данных',waiting_retention_protection_or_other_parties:'Ожидание срока, снятия защиты или удаления других участников',partial_minimization:'Частичная минимизация',pending_category_worker:'Обработка категории ещё не подтверждена',immediate_done:'Первичный этап выполнен',planned_immediate_step:'После подтверждения удаления',personal_media_step:'Очистка личных файлов запланирована',planned_personal_media_step:'После удаления аккаунта'};
const number=value=>Number.isSafeInteger(value)&&value>=0?String(value):'—';
export function privacyProgress({record,esc,card,note}){
 if(record.type!=='delete')return '';
 const plan=record.retention_plan,progress=record.category_progress??{};
 const table=(headers,rows)=>`<div class="tablewrap"><table><thead><tr>${headers.map(h=>`<th scope="col">${esc(h)}</th>`).join('')}</tr></thead><tbody>${rows.map(row=>`<tr>${row.map(v=>`<td>${esc(v)}</td>`).join('')}</tr>`).join('')}</tbody></table></div>`;
 const summary=record.fully_erased===true?'Все предусмотренные этапы удаления подтверждены.':'Полное удаление не подтверждено. Удаление доступа, минимизация записей и удаление байтов — разные этапы. Данные с действующим основанием хранения сохраняются.';
 const categories=Array.isArray(plan?.categories)?plan.categories:[];
 const files=Array.isArray(plan?.file_categories)?plan.file_categories:[];
 const categoryRows=categories.map(c=>[c.label??c.category,number(c.count),Number.isSafeInteger(c.retention_days)?`${c.retention_days} дн.`:c.policy_required?'Не опубликован':'Отдельное основание',states[c.execution_state]??c.execution_state??'Не подтверждено']);
 const stageRows=Object.entries(progress).map(([key,value])=>[stageLabels[key]??key,states[value.state]??value.state??'Не подтверждено',number(value.processed),number(value.remaining),value.last_run_at??'—']);
 return card('План и выполнение удаления',note(summary)+
  `<dl><dt>Необратимый этап / состояние</dt><dd>${esc(record.status)}</dd><dt>Запланировано не ранее</dt><dd>${esc(record.execute_after??'—')}</dd><dt>Последний проход обработки</dt><dd>${esc(record.last_retention_run_at??'—')}</dd><dt>Активные удержания в сохранённом плане</dt><dd>${esc(number(plan?.active_holds))}</dd></dl>`+
  (categories.length?table(['Категория','Записей в плане','Срок','Состояние'],categoryRows):note('Сохранённый план пока не сформирован.'))+
  (stageRows.length?table(['Этап','Результат','Обработано накопительно','Осталось','Последний проход'],stageRows):note('Результаты фоновых этапов ещё не записаны.'))+
  (files.length?table(['Файлы','В плане','Действие','Физически удалено','Ожидает удаления'],files.map(f=>[f.label??f.category,number(f.count),f.action??'—',number(f.physical_purged_count),number(f.physical_pending_count)])):'')+
  note('Количество в плане — снимок на момент его составления. «Обработано» относится к отдельному этапу, а не ко всем данным аккаунта. Необязательные согласия не заменяют отдельную проверку обязательных согласий и неизменяемого аудита.')+
  `<a class="btn" href="#legal-holds">Открыть очередь удержаний</a>`);
}
