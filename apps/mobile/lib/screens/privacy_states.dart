import 'package:flutter/material.dart';
import '../core/api.dart';
import '../core/design_states.dart';
import '../core/l10n.dart';
import '../core/theme.dart';
import '../core/widgets.dart';

class PrivacyStates extends StatefulWidget {
  final JobaApi api;
  final String mode;
  final String? id;
  final void Function(String route, String? id) onGo;
  const PrivacyStates(
      {required this.api,
      required this.mode,
      required this.onGo,
      this.id,
      super.key});
  @override
  State<PrivacyStates> createState() => _PrivacyStatesState();
}

class _PrivacyStatesState extends State<PrivacyStates> {
  bool acknowledged = false, busy = false;
  Object? error;
  Json? consent;
  Widget footer(String label, VoidCallback? action) => Container(
      decoration: const BoxDecoration(
          color: Colors.white, border: Border(top: BorderSide(color: line))),
      child: SafeArea(
          top: false,
          child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 4),
              child: FilledButton(onPressed: action, child: UiText(label)))));
  @override
  Widget build(BuildContext context) {
    if (widget.mode == 'consents')
      return ApiView(
          load: () => widget.api.request('/me/processing-consents'),
          builder: (context, r, reload) {
            consent ??= Map<String, dynamic>.from(r);
            return Column(children: [
              Expanded(
                  child: ListView(padding: const EdgeInsets.all(20), children: [
                const UiHeading(
                    'Вы решаете', 'Изменения действуют на будущую обработку.'),
                for (final e in const {
                  'marketing': [
                    'Новости JOBA',
                    'Предложения и новости в приложении'
                  ],
                  'ad_personalization': [
                    'Персонализация рекламы',
                    'Подбор рекламы по интересам'
                  ],
                  'optional_analytics': [
                    'Необязательная аналитика',
                    'Помогает улучшать интерфейс'
                  ]
                }.entries)
                  SwitchListTile(
                      contentPadding:
                          const EdgeInsets.symmetric(horizontal: 16),
                      title: UiText(e.value[0]),
                      subtitle: UiText(e.value[1]),
                      value: consent![e.key] == true,
                      onChanged: busy
                          ? null
                          : (v) => setState(() => consent![e.key] = v)),
                const Notice(
                    'Отказ от необязательных согласий не закрывает управление аккаунтом, приватность и поддержку.'),
                DataCard('Обязательные условия',
                    translateTitle: true,
                    subtitle: localize(context, 'Принятые версии и даты'),
                    onTap: () => widget.onGo('terms', null)),
                if (error != null)
                  Notice(errorText(context, error!), error: true)
              ])),
              footer(
                  'Сохранить выбор',
                  busy
                      ? null
                      : () async {
                          setState(() => busy = true);
                          try {
                            await widget.api.request('/me/processing-consents',
                                method: 'POST',
                                body: {
                                  for (final k in [
                                    'marketing',
                                    'ad_personalization',
                                    'optional_analytics'
                                  ])
                                    k: consent![k] == true,
                                  'expected_version': r['version']
                                });
                            if (mounted) widget.onGo('privacy', null);
                          } catch (e) {
                            if (mounted) setState(() => error = e);
                          } finally {
                            if (mounted) setState(() => busy = false);
                          }
                        })
            ]);
          });
    if (widget.mode == 'delete-account')
      return ApiView(
          load: () => widget.api.request('/me/deletion-preview'),
          builder: (context, r, reload) => Column(children: [
                Expanded(
                    child:
                        ListView(padding: const EdgeInsets.all(20), children: [
                  const UiHeading('Проверьте последствия',
                      'Удаление затронет обе роли: заказчика и исполнителя.'),
                  const Notice(
                      'Профиль исчезнет из поиска. Сессии завершатся. Данные будут удалены или обезличены по установленным срокам.'),
                  DataCard('Активные заказы',
                      translateTitle: true,
                      subtitle: '${r['active_orders']}',
                      onTap: () => widget.onGo('orders', null)),
                  DataCard('Подписка',
                      translateTitle: true,
                      subtitle: localize(
                          context, 'Удаление аккаунта не отменяет подписку.'),
                      onTap: () => widget.onGo('manage-subscription', null)),
                  DataCard('Сохранить свои данные',
                      translateTitle: true,
                      subtitle:
                          localize(context, 'Запросить копию до удаления'),
                      onTap: () => widget.onGo('export', null)),
                  const Notice(
                      'Часть записей может сохраняться по законному основанию. Мы объясним, какие данные и почему.'),
                  if (r['policy_ready'] != true)
                    const Notice(
                        'Сроки хранения ещё не утверждены. Запрос можно подать, но очистка не начнётся до проверки политики.'),
                  CheckboxListTile(
                      value: acknowledged,
                      onChanged: (v) =>
                          setState(() => acknowledged = v == true),
                      title: const UiText(
                          'Понимаю последствия и хочу продолжить.')),
                  TextButton(
                      onPressed: () => widget.onGo('account', null),
                      child: const UiText('Вернуться в профиль'))
                ])),
                footer(
                    'Продолжить',
                    acknowledged
                        ? () => widget.onGo('delete-confirm', null)
                        : null)
              ]));
    if (widget.mode == 'delete-confirm')
      return ActionForm(
          stickySubmit: true,
          before: const [
            UiHeading('Последний шаг',
                'Для удаления потребуется текущий пароль аккаунта.'),
            Notice(
                'До начала окончательной очистки запрос можно отменить. Удаление не отменяет подписку автоматически.')
          ],
          fields: const [
            InputSpec('current_password', 'Пароль аккаунта', secret: true)
          ],
          afterFields: const [
            Notice(
                'Проверьте активную подписку и сохраните копию своих данных. Открытые дела будут обработаны по правилам хранения.')
          ],
          button: 'Подтвердить запрос',
          submit: (v) async {
            final r = await widget.api.request('/me/privacy-requests',
                method: 'POST', body: {...v, 'type': 'delete'});
            if (mounted) widget.onGo('delete-scheduled', r['id']);
          });
    return ApiView(
        load: () => widget.api.request('/me/privacy-requests/${widget.id}'),
        builder: (context, r, reload) {
          if (r['type'] != 'delete')
            return const Notice('Запрос удаления не найден.');
          final cancel = [
            'requested',
            'awaiting_retention_policy',
            'scheduled',
            'awaiting_resolution'
          ].contains(r['status']);
          return ListView(padding: const EdgeInsets.all(20), children: [
            JobaStatePanel(
                icon: 'clock',
                title: r['status'] == 'cancelled'
                    ? 'Запрос отменён'
                    : r['status'] == 'scheduled'
                        ? 'Удаление запланировано'
                        : 'Запрос принят',
                message: r['status'] == 'scheduled'
                    ? 'Очистка начнётся не раньше ${r['execute_after']}. До её начала запрос можно отменить.'
                    : r['status'] == 'awaiting_retention_policy'
                        ? 'Ожидается утверждение политики хранения. Очистка не началась.'
                        : r['status'] == 'awaiting_resolution'
                            ? 'Сначала необходимо безопасно завершить активные заказы. Очистка не началась.'
                            : r['status'] == 'cancelled'
                                ? 'Аккаунт сохранён. Поддержка доступна.'
                                : 'Состояние запроса обновляется. Поддержка доступна.',
                primaryLabel: cancel ? 'Отменить запрос' : 'Приватность',
                busy: busy,
                onPrimary: cancel
                    ? () async {
                        setState(() => busy = true);
                        try {
                          await widget.api.request(
                              '/me/privacy-requests/${widget.id}/cancel',
                              method: 'POST',
                              body: {'expected_version': r['version']});
                          reload();
                        } catch (e) {
                          if (mounted) setState(() => error = e);
                        } finally {
                          if (mounted) setState(() => busy = false);
                        }
                      }
                    : () => widget.onGo('privacy', null),
                secondaryLabel: 'Поддержка',
                onSecondary: () => widget.onGo('support', null)),
            if (error != null) Notice(errorText(context, error!), error: true)
          ]);
        });
  }
}
