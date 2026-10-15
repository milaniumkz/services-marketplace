import 'package:flutter/material.dart';
import '../core/api.dart';
import '../core/currency.dart';
import '../core/design_states.dart';
import '../core/l10n.dart';
import '../core/theme.dart';
import '../core/widgets.dart';

class WorkStateScreen extends StatefulWidget {
  final JobaApi api;
  final String mode, id;
  final void Function(String route, String id) onGo;
  final Future<Json?> Function() pickPhoto;
  const WorkStateScreen(
      {required this.api,
      required this.mode,
      required this.id,
      required this.onGo,
      required this.pickPhoto,
      super.key});
  @override
  State<WorkStateScreen> createState() => _WorkStateScreenState();
}

class _WorkStateScreenState extends State<WorkStateScreen> {
  bool acknowledged = false;
  final List<String> photos = [];
  String path() => widget.mode == 'invited'
      ? '/order-invites/${widget.id}'
      : widget.mode == 'cancel-pending'
          ? '/cancel-requests/${widget.id}'
          : widget.mode == 'offer-revision'
              ? '/offers/${widget.id}'
              : widget.mode == 'frozen-chat'
                  ? '/conversations/${widget.id}'
                  : '/orders/${widget.id}';
  int amount(String value) {
    final n = double.tryParse(value.replaceAll(',', '.'));
    if (n == null || n < 0 || !n.isFinite)
      throw ApiException('VALIDATION_ERROR', 'Проверьте цену');
    return (n * 100).round();
  }

  @override
  Widget build(BuildContext context) => ApiView(
      load: () => widget.api.request(path()),
      builder: (context, r, reload) {
        final mode = widget.mode;
        if (mode == 'invited' || mode == 'cancel-pending') {
          final pending = r['status'] == 'pending',
              orderId = '${r['order_id']}';
          return ListView(padding: const EdgeInsets.all(20), children: [
            JobaStatePanel(
                icon: pending ? 'check' : 'info',
                title: mode == 'invited'
                    ? (pending
                        ? 'Приглашение\nотправлено'
                        : 'Приглашение обновлено')
                    : (pending
                        ? 'Запрос отправлен'
                        : 'Решение по запросу получено'),
                message: mode == 'invited'
                    ? 'Когда исполнитель ответит, вы увидите событие в приложении. Назначение произойдёт после подтверждения условий.'
                    : 'История заказа и поддержка остаются доступны. Решение появится в заказе.',
                primaryLabel:
                    mode == 'invited' ? 'Мои заказы' : 'Открыть заказ',
                onPrimary: () => widget.onGo(
                    mode == 'invited' ? 'orders' : 'order', orderId))
          ]);
        }
        if (mode == 'frozen-chat')
          return ListView(padding: const EdgeInsets.all(20), children: [
            Notice(r['blocked'] == true
                ? 'Для безопасности новые сообщения в этой переписке временно недоступны.'
                : 'Эта переписка доступна по текущим правилам.'),
            DataCard('${r['order_title'] ?? ''}',
                subtitle: localize(context, 'История заказа сохранена.')),
            JobaStatePanel(
                icon: 'shield',
                title: r['blocked'] == true
                    ? 'Обратитесь\nв поддержку'
                    : 'Чат доступен',
                message: 'Подписка не снимает ограничения безопасности.',
                primaryLabel:
                    r['blocked'] == true ? 'Открыть обращение' : 'Открыть чат',
                onPrimary: () => widget.onGo(
                    r['blocked'] == true ? 'support' : 'chat', widget.id))
          ]);
        if (mode == 'offer-revision') {
          final order = r['order'];
          return ActionForm(
              stickySubmit: true,
              submitEnabled: acknowledged,
              before: [
                Notice(
                    'Заказчик обновил задачу. Проверьте изменения перед подтверждением.'),
                Heading('${order['title']}'),
                DataCard(
                    'Версия ${r['acknowledged_revision']} → ${order['revision']}',
                    subtitle: '${order['description']}'),
                const Notice(
                    'Ничего не будет отправлено до повторного подтверждения.')
              ],
              fields: [
                InputSpec('amount', 'Ваша цена',
                    initial: ((r['amount'] as num) / 100).toStringAsFixed(2),
                    keyboard: TextInputType.number),
                InputSpec('text', 'Комментарий',
                    initial: r['text'] ?? '', multiline: true)
              ],
              afterFields: [
                CheckboxListTile(
                    value: acknowledged,
                    onChanged: (v) => setState(() => acknowledged = v == true),
                    title: const UiText('Ознакомился с новой версией условий.'))
              ],
              button: 'Изменить мой отклик',
              submit: (v) async {
                await widget.api
                    .request('/offers/${widget.id}', method: 'PATCH', body: {
                  'expected_version': r['version'],
                  'amount': amount(v['amount']!),
                  'text': v['text'],
                  'acknowledged_revision': order['revision']
                });
                widget.onGo('offer-sent', widget.id);
              });
        }
        final amendment = mode == 'amendment';
        return ActionForm(
            stickySubmit: true,
            before: [
              UiHeading(
                  amendment
                      ? 'Предложите изменение'
                      : 'Что осталось исправить?',
                  amendment
                      ? 'Условия обновятся только после согласия второй стороны.'
                      : 'Опишите конкретные замечания к результату заказа.'),
              DataCard('${r['title']}',
                  subtitle: formatMoney(
                      (r['agreed_amount'] ?? r['budget_amount'] ?? 0) as int,
                      '${r['currency'] ?? 'KZT'}',
                      Localizations.localeOf(context).languageCode))
            ],
            fields: [
              if (amendment)
                InputSpec('amount', 'Новая стоимость',
                    keyboard: TextInputType.number),
              InputSpec('date', 'Новая дата (ГГГГ-ММ-ДД)',
                  required: false,
                  validate: (s) => s.isEmpty || DateTime.tryParse(s) != null
                      ? null
                      : 'Проверьте дату'),
              InputSpec('reason',
                  amendment ? 'Причина изменения' : 'Комментарий исполнителю',
                  multiline: true,
                  validate: (v) => v.trim().length >= 5
                      ? null
                      : 'Опишите ситуацию подробнее')
            ],
            afterFields: [
              if (!amendment) ...[
                for (final id in photos) PrivatePhoto(api: widget.api, id: id),
                if (photos.length < 10)
                  OutlinedButton(
                      onPressed: () async {
                        final file = await widget.pickPhoto();
                        if (file != null && mounted)
                          setState(() => photos.add(file['id']));
                      },
                      child: const UiText('Добавить фото'))
              ],
              Notice(amendment
                  ? 'Пока изменение не принято, действуют прежние условия.'
                  : 'Работа ещё не будет принята. Исполнитель получит замечание в заказе.')
            ],
            button:
                amendment ? 'Предложить изменение' : 'Отправить на доработку',
            submit: (v) async {
              Json? window;
              if (v['date']!.isNotEmpty) {
                final day = DateTime.parse(v['date']!)
                    .toIso8601String()
                    .substring(0, 10);
                window = {
                  'start_date': day,
                  'end_date': day,
                  'time_zone': r['time_window']?['time_zone'] ?? 'UTC'
                };
              }
              await widget.api.request(
                  '/orders/${widget.id}/${amendment ? 'amendments' : 'request-revision'}',
                  method: 'POST',
                  body: {
                    'expected_version': r['version'],
                    'reason': v['reason'],
                    if (amendment) 'amount': amount(v['amount']!),
                    if (amendment) 'description': r['description'],
                    if (window != null) 'time_window': window,
                    if (!amendment) 'upload_ids': photos
                  });
              widget.onGo(amendment ? 'change-requests' : 'order', widget.id);
            });
      });
}
