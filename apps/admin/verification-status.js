const labels={not_started:'Не начата',not_requested:'Не запрошена',consent_required:'Нужно согласие',pending_upload:'Ожидаются фотографии',draft:'Фотографии ещё не отправлены',pending_review:'Ожидает проверки',passed:'Личность подтверждена',rejected:'Нужны исправления',needs_resubmission:'Нужна повторная отправка',expired:'Прежний срок истёк',revoked:'Подтверждение отозвано'};
export const verificationStatus=value=>labels[value]||'Статус уточняется';

export const verificationStatuses=['draft','pending_review','passed','rejected','expired','revoked'];
