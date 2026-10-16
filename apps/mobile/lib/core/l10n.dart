import 'package:flutter/material.dart';
import 'ui_translations.dart';
import 'api.dart';

/// Apply only to interface labels. User descriptions and messages remain verbatim.
String localize(BuildContext context, String source) =>
    uiTranslations[source]?[Localizations.localeOf(context).languageCode] ??
    source;

String errorText(BuildContext context, Object error) {
  if (error is! ApiException)
    return localize(context, 'Не удалось выполнить действие');
  final source = error.toString(), translated = localize(context, source);
  if (Localizations.localeOf(context).languageCode == 'ru' ||
      translated != source) return translated;
  final message = const {
        'INVALID_CREDENTIALS': 'Неверный номер или пароль',
        'REAUTH_REQUIRED': 'Подтвердите текущий пароль',
        'REGISTRATION_UNAVAILABLE':
            'Не удалось зарегистрироваться. Обратитесь в поддержку.',
        'SESSION_SUPERSEDED': 'Войдите снова с номером и паролем.',
        'TOKEN_EXPIRED': 'Войдите снова с номером и паролем',
        'REFRESH_REPLAY': 'Войдите снова с номером и паролем',
        'STATE_CONFLICT':
            'Данные изменились. Обновите экран и повторите действие.',
        'OFFER_CHANGED':
            'Данные изменились. Обновите экран и повторите действие.',
        'REVISION_NOT_ACKNOWLEDGED':
            'Данные изменились. Обновите экран и повторите действие.',
        'IDEMPOTENCY_CONFLICT':
            'Данные изменились. Обновите экран и повторите действие.',
        'VALIDATION_ERROR': 'Проверьте заполненные поля.',
        'ENTITLEMENT_REQUIRED':
            'Нужен действующий доступ. Откройте «Мой доступ».',
        'CONSENT_REQUIRED':
            'Чтобы продолжить, примите условия использования и политику конфиденциальности.',
        'LEGAL_VERSION_CHANGED':
            'Данные изменились. Обновите экран и повторите действие.',
        'VERIFICATION_REQUIRED': 'Требуется проверка документа исполнителя.',
        'EXECUTOR_ROLE_REQUIRED': 'Настройте профиль исполнителя.',
        'FORBIDDEN': 'Действие недоступно для вашего аккаунта.',
        'NOT_FOUND': 'Объект не найден или недоступен.',
        'PAIR_BLOCKED': 'Прямой контакт ограничен. Поддержка доступна.',
        'RATE_LIMITED': 'Слишком много попыток. Повторите позже.',
        'FILE_TOO_LARGE': 'Файл слишком большой.',
        'UNSAFE_UPLOAD': 'Файл ещё не прошёл безопасную проверку.',
        'SCANNER_UNAVAILABLE': 'Проверка файлов недоступна. Попробуйте позже.',
        'FILE_PROCESSING_UNAVAILABLE':
            'Проверка файлов недоступна. Попробуйте позже.',
        'PDF_SANITIZER_UNAVAILABLE':
            'Проверка файлов недоступна. Попробуйте позже.',
        'PROVIDER_UNAVAILABLE': 'Сервис ещё не подключён.',
        'ATTRIBUTION_WINDOW_EXPIRED': 'Срок ввода кода после регистрации истёк',
        'ATTRIBUTION_ALREADY_SET': 'Пригласивший уже закреплён',
        'REFERRAL_BUDGET_EXHAUSTED': 'Бюджет новых приглашений исчерпан',
        'CAMPAIGN_UNAVAILABLE': 'Активной реферальной кампании нет',
        'REFERRAL_INELIGIBLE': 'Код недоступен',
        'POLICY_REJECTED': 'Действие не разрешено действующими правилами.',
      }[error.code] ??
      'Не удалось выполнить запрос';
  final label = const {
    'title': 'Название',
    'description': 'Описание',
    'city': 'Город',
    'city_id': 'Город',
    'phone': 'Номер телефона',
    'password': 'Пароль',
    'new_password': 'Новый пароль',
    'category_id': 'Категория',
    'languages': 'Языки общения (ru, kk, sr, be, en)',
    'travel_radius_km': 'Радиус выезда, км'
  }[error.details['field']];
  return localize(context, message) +
      (label == null ? '' : '\n' + localize(context, label));
}

class UiText extends StatelessWidget {
  final String source;
  final TextStyle? style;
  final TextAlign? textAlign;
  final int? maxLines;
  final TextOverflow? overflow;
  final bool? softWrap;
  const UiText(this.source,
      {this.style,
      this.textAlign,
      this.maxLines,
      this.overflow,
      this.softWrap,
      super.key});
  @override
  Widget build(BuildContext context) => Text(localize(context, source),
      style: style,
      textAlign: textAlign,
      maxLines: maxLines,
      overflow: overflow,
      softWrap: softWrap);
}
