import 'package:flutter/material.dart';
import '../core/api.dart';
import '../core/design_states.dart';
import '../core/widgets.dart';

class ContentReviewReceipt extends StatelessWidget {
  final JobaApi api;
  final bool profile;
  final String? id;
  final VoidCallback onContinue;
  const ContentReviewReceipt(
      {required this.api,
      required this.profile,
      required this.onContinue,
      this.id,
      super.key});
  @override
  Widget build(BuildContext context) => ApiView(
      key: ValueKey('content-review:$profile:$id'),
      load: () => api.request(
          profile ? '/me/contractor-profile' : '/me/portfolio-projects/$id'),
      builder: (context, data, reload) {
        final Json? record = profile ? (data as Json)['profile'] : data as Json;
        final pending = record != null &&
            (['pending_review', 'pending_moderation']
                    .contains(record['status']) ||
                record['moderation_status'] == 'quarantined');
        final visible = record?['public_visible'] == true;
        final published = visible &&
            record?['status'] == 'published' &&
            !['hidden', 'quarantined', 'rejected']
                .contains(record?['moderation_status']);
        final title = record == null
            ? 'Профиль не найден'
            : pending
                ? (profile ? 'Получили изменения' : 'Проверяем ваш проект')
                : published
                    ? 'Публикация подтверждена'
                    : 'Статус проверки изменился';
        final message = pending
            ? profile
                ? visible
                    ? 'Текущая опубликованная версия профиля остаётся видимой до решения по обновлению.'
                    : 'Новая версия профиля не будет показана до проверки. Статус доступен в ваших услугах.'
                : visible
                    ? 'Фотографии и текст новой версии не будут показаны до проверки. Предыдущая безопасная версия остаётся доступна.'
                    : 'Фотографии и текст проекта не будут показаны до проверки. Статус доступен в вашем портфолио.'
            : record == null
                ? 'Заполните профиль, чтобы предложить свои услуги.'
                : published
                    ? 'Текущая версия опубликована.'
                    : 'Откройте запись, чтобы посмотреть актуальный статус и причину решения.';
        return ListView(padding: const EdgeInsets.all(20), children: [
          JobaStatePanel(
              title: title,
              message: message,
              icon: profile ? 'clock' : 'image',
              primaryLabel: profile ? 'Мои услуги' : 'Моё портфолио',
              onPrimary: onContinue)
        ]);
      });
}
