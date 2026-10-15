import 'package:flutter/material.dart';
import '../core/api.dart';
import '../core/design_states.dart';
import '../core/l10n.dart';
import '../core/theme.dart';
import '../core/widgets.dart';

class ExportIntro extends StatelessWidget {
  final VoidCallback onRequest;
  const ExportIntro({required this.onRequest, super.key});
  Widget step(String title, String message, bool last) =>
      Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        SizedBox(
            width: 25,
            child: Column(children: [
              Container(
                  width: 18,
                  height: 18,
                  decoration: BoxDecoration(
                      color: primary,
                      border: Border.all(color: Colors.white, width: 3),
                      shape: BoxShape.circle,
                      boxShadow: const [
                        BoxShadow(color: line, spreadRadius: 1)
                      ])),
              if (!last) Container(width: 1, height: 46, color: line)
            ])),
        const SizedBox(width: 8),
        Expanded(
            child: Padding(
                padding: const EdgeInsets.only(bottom: 20),
                child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      UiText(title,
                          style: const TextStyle(
                              fontSize: 14, fontWeight: FontWeight.w700)),
                      const SizedBox(height: 4),
                      UiText(message,
                          style: const TextStyle(
                              fontSize: 11,
                              color: Color(0xFF627187),
                              height: 1.55))
                    ])))
      ]);
  @override
  Widget build(BuildContext context) => Column(children: [
        Expanded(
            child: ListView(padding: const EdgeInsets.all(20), children: [
          const JobaStatePanel(
              title: 'Копия ваших данных',
              message:
                  'Подготовим профиль, заказы, переписку и собственные вложения в доступном формате.',
              icon: 'download',
              contentPadding:
                  EdgeInsets.symmetric(horizontal: 23, vertical: 18)),
          const SizedBox(height: 20),
          Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                  color: Colors.white,
                  border: Border.all(color: line),
                  borderRadius: BorderRadius.circular(16)),
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const UiText('Как это работает',
                        style: TextStyle(
                            fontSize: 16, fontWeight: FontWeight.w700)),
                    const SizedBox(height: 12),
                    step('Подтвердите вход', 'Текущий пароль для безопасности',
                        false),
                    step('Дождитесь подготовки',
                        'Готовность появится в приложении', false),
                    step('Скачайте архив',
                        'Ссылка действует ограниченное время', true)
                  ])),
          const SizedBox(height: 16),
          const UiText(
              'В архив не входят чужие закрытые данные и внутренние сигналы безопасности.',
              style: TextStyle(
                  fontSize: 10, height: 1.4, color: Color(0xFF627187)))
        ])),
        SafeArea(
            top: false,
            child: Container(
                decoration: const BoxDecoration(
                    color: Colors.white,
                    border: Border(top: BorderSide(color: line))),
                padding: const EdgeInsets.fromLTRB(20, 12, 20, 4),
                width: double.infinity,
                child: FilledButton(
                    onPressed: onRequest,
                    child: const UiText('Запросить экспорт'))))
      ]);
}

class ExportStatus extends StatelessWidget {
  final JobaApi api;
  final String id;
  final bool busy;
  final VoidCallback onPrivacy, onNewRequest;
  final ValueChanged<String> onDownload;
  final ValueChanged<String>? onTitle;
  const ExportStatus(
      {required this.api,
      required this.id,
      required this.onPrivacy,
      required this.onNewRequest,
      required this.onDownload,
      this.busy = false,
      this.onTitle,
      super.key});
  @override
  Widget build(BuildContext context) => ApiView(
      load: () => api.request('/me/privacy-requests/$id'),
      builder: (context, data, reload) {
        final request = data as Json;
        if (request['type'] != 'export')
          return const Center(
              child: Notice('Запрос экспорта не найден.', error: true));
        final ready = request['status'] == 'completed' &&
            request['download_available'] == true &&
            request['upload_id'] is String;
        final expired = request['status'] == 'completed' && !ready;
        final failed = request['status'] == 'failed',
            cancelled = request['status'] == 'cancelled';
        final caption = ready
            ? 'Копия готова'
            : expired || failed || cancelled
                ? 'Экспорт данных'
                : 'Экспорт готовится';
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (context.mounted) onTitle?.call(caption);
        });
        return ListView(padding: const EdgeInsets.all(20), children: [
          JobaStatePanel(
              title: ready
                  ? 'Копия готова'
                  : expired
                      ? 'Архив больше недоступен'
                      : failed
                          ? 'Подготовка приостановлена'
                          : cancelled
                              ? 'Запрос отменён'
                              : 'Готовим вашу копию',
              message: ready
                  ? 'Сохраните архив на своём устройстве. Доступ действует ограниченное время.'
                  : expired
                      ? 'Запросите новую копию данных.'
                      : failed
                          ? 'Не удалось подготовить архив. Можно создать новый запрос.'
                          : cancelled
                              ? 'При необходимости можно запросить новую копию.'
                              : 'Сообщим в приложении, когда архив будет доступен. Он не отправляется в уведомлениях.',
              icon: 'download',
              busy: busy,
              primaryLabel: ready
                  ? 'Сохранить архив'
                  : expired || failed
                      ? 'Запросить экспорт'
                      : 'Вернуться к приватности',
              onPrimary: ready
                  ? () => onDownload(request['upload_id'])
                  : expired || failed
                      ? onNewRequest
                      : onPrivacy,
              secondaryLabel:
                  ready || expired || failed ? 'Вернуться к приватности' : null,
              onSecondary: ready || expired || failed ? onPrivacy : null)
        ]);
      });
}
