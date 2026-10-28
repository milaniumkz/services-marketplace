/** Public event descriptions: no chat text, document data or private addresses. */
export const notificationTitles:Record<string,string>={
 'push.test':'Проверка push-уведомлений JOBA',
 'message.created':'Новое сообщение по заказу','support.message.created':'Поддержка ответила на обращение',
 'offer.created':'Новый отклик на ваш заказ','offer.updated':'Исполнитель изменил отклик',
 'offer.expired':'Срок вашего отклика истёк','order.offer_expired':'Срок отклика исполнителя истёк',
 'invite.created':'Заказчик предлагает вам работу','invite.accepted':'Исполнитель принял приглашение','invite.declined':'Исполнитель отказался от приглашения','invite.revoked':'Заказчик отозвал приглашение','invite.expired':'Срок приглашения истёк',
 'order.selected':'Вас выбрали исполнителем','order.selection_confirmed':'Исполнитель выбран','offer.declined':'Заказчик отказал в работе','offer.not_selected':'Заказчик выбрал другого исполнителя','order.offer_declined':'Вы отказали исполнителю','order.offer_withdrawn':'Исполнитель отказался от работы','offer.withdrawn':'Вы отозвали отклик',
 'order.published':'Ваш заказ опубликован','order.updated':'Заказчик изменил условия заказа','order.started':'Работа по заказу началась','order.completion_requested':'Исполнитель просит принять работу','order.revision_requested':'Заказчик запросил доработку','order.completed':'Работа принята, заказ завершён','order.cancelled':'Заказ отменён','order.expired':'Срок размещения заказа истёк',
 'amendment.created':'Предложено изменение условий заказа','amendment.accepted':'Изменение условий принято','amendment.rejected':'Изменение условий отклонено','amendment.expired':'Срок изменения условий истёк',
 'cancel_request.created':'Запрошена отмена заказа','cancel_request.accepted':'Отмена заказа согласована','cancel_request.rejected':'Отмена заказа отклонена','cancel_request.expired':'Срок запроса отмены истёк',
 'review.published':'Вам оставили новый отзыв',
 'verification.updated':'Обновлён результат проверки личности','verification.expired':'Подтверждение личности отозвано',
 'contractor.approved':'Ваши услуги одобрены','contractor.rejected':'Ваши услуги требуют исправлений','portfolio.approved':'Проект портфолио одобрен','portfolio.rejected':'Проект портфолио требует исправлений',
 'subscription.renewed':'Подписка продлена',
 'subscription.active':'Подписка активирована','subscription.expired':'Срок подписки закончился','subscription.revoked':'Доступ по подписке прекращён','subscription.updated':'Изменился статус подписки',
 'refund.confirmed':'Возврат оплаты подтверждён','refund.failed':'Не удалось выполнить возврат','refund.rejected':'Заявка на возврат отклонена',
 'referral.available':'Вам начислен реферальный бонус','referral.redeemed':'Реферальный бонус использован','referral.expired':'Срок реферального бонуса истёк',
 'boost.active':'Продвижение услуг включено','boost.expired':'Срок продвижения закончился','boost.paused':'Продвижение приостановлено','boost.revoked':'Продвижение отключено',
 'case.message.created':'Новое сообщение по обращению','case.updated':'Обновлено решение по обращению','content.moderated':'Обновлён результат проверки материала','support.resolved':'Обращение в поддержку закрыто','support.reopened':'Обращение в поддержку открыто снова',
 'privacy.export.ready':'Ваш архив данных готов','privacy.hold.created':'Изменились условия хранения данных','privacy.hold.released':'Ограничение удаления данных снято','sanction.created':'Изменились ограничения аккаунта'
};
export function notificationTitle(type:string){return notificationTitles[type]??'Новое событие в JOBA';}
