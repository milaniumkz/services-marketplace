import 'package:flutter/material.dart';
import 'offer_editor.dart';
import '../core/api.dart';
import '../core/design_icons.dart';
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
        if (mode == 'frozen-chat') {
          final expired = r['blocked_reason'] == 'offer_expired',
              closed = r['blocked_reason'] == 'conversation_closed';
          return ListView(padding: const EdgeInsets.all(20), children: [
            Notice(expired
                ? 'Срок отклика истёк. Новые сообщения в этой переписке недоступны.'
                : closed
                    ? 'Переписка закрыта для новых сообщений. История заказа сохранена.'
                    : r['blocked'] == true
                        ? 'Для безопасности новые сообщения в этой переписке временно недоступны.'
                        : 'Эта переписка доступна по текущим правилам.'),
            DataCard('${r['order_title'] ?? ''}',
                subtitle: localize(context, 'История заказа сохранена.')),
            JobaStatePanel(
                icon: 'shield',
                title: expired
                    ? 'Срок отклика\nистёк'
                    : closed
                        ? 'Переписка\nзакрыта'
                        : r['blocked'] == true
                            ? 'Обратитесь\nв поддержку'
                            : 'Чат доступен',
                message: expired || closed
                    ? 'Откройте заказ, чтобы проверить его текущее состояние. История переписки сохранена.'
                    : 'Подписка не снимает ограничения безопасности.',
                primaryLabel: expired || closed
                    ? 'Открыть заказ'
                    : r['blocked'] == true
                        ? 'Открыть обращение'
                        : 'Открыть чат',
                onPrimary: () => widget.onGo(
                    expired || closed
                        ? 'order'
                        : r['blocked'] == true
                            ? 'support'
                            : 'chat',
                    expired || closed ? r['order_id'] ?? widget.id : widget.id))
          ]);
        }
        if (mode == 'offer-revision') {
          final order = Json.from(r['order']),
              before = r['acknowledged_order'] as Json?;
          String price(dynamic value) => value == null
              ? '—'
              : formatMoney(value, order['currency'] ?? 'KZT',
                  Localizations.localeOf(context).languageCode);
          Widget delta(String value,
              {TextStyle? style, TextAlign align = TextAlign.right}) {
            final parts = value.split(' → ');
            return Text.rich(
                TextSpan(children: [
                  for (var i = 0; i < parts.length; i++) ...[
                    if (i > 0)
                      const WidgetSpan(
                          alignment: PlaceholderAlignment.middle,
                          child: Padding(
                              padding: EdgeInsets.symmetric(horizontal: 4),
                              child: JobaIcon('arrow-right', size: 12))),
                    TextSpan(text: parts[i]),
                  ]
                ]),
                style: style,
                textAlign: align);
          }

          Widget fact(String label, String value) => Padding(
              padding: const EdgeInsets.symmetric(vertical: 12),
              child: Row(children: [
                Expanded(
                    child: UiText(label,
                        style: const TextStyle(
                            fontSize: 12, color: Color(0xFF627187)))),
                Expanded(
                    child: delta(value,
                        align: TextAlign.right,
                        style: const TextStyle(
                            fontSize: 12, fontWeight: FontWeight.w700))),
              ]));
          return Column(children: [
            Expanded(
                child: ListView(padding: const EdgeInsets.all(20), children: [
              const Notice(
                  'Заказчик обновил задачу после открытия вашего отклика. Проверьте изменения перед отправкой.',
                  warning: true,
                  icon: 'info',
                  margin: EdgeInsets.zero),
              const SizedBox(height: 20),
              Text('${order['title']}',
                  style: const TextStyle(
                      fontSize: 28,
                      height: 1.25,
                      letterSpacing: -.9,
                      fontWeight: FontWeight.w700)),
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
                        delta(
                            '${localize(context, 'Версия')} ${r['acknowledged_revision']} → ${order['revision']}',
                            align: TextAlign.left,
                            style: const TextStyle(
                                fontSize: 11,
                                color: Color(0xFF627187),
                                fontWeight: FontWeight.w700)),
                        fact(
                            'Бюджет',
                            before == null
                                ? price(order['budget_amount'])
                                : '${price(before['budget_amount'])} → ${price(order['budget_amount'])}'),
                        if (order['time_window']?['start_date'] != null)
                          fact('Дата',
                              '${order['time_window']['start_date']} — ${order['time_window']['end_date']}'),
                        const Divider(height: 28, color: line),
                        const UiText('Текущие условия',
                            style: TextStyle(
                                fontSize: 16, fontWeight: FontWeight.w700)),
                        const SizedBox(height: 8),
                        Text('${order['description'] ?? ''}',
                            style: const TextStyle(
                                fontSize: 12,
                                height: 1.5,
                                color: Color(0xFF627187))),
                      ])),
              const SizedBox(height: 20),
              const UiText(
                  'Текст вашего отклика сохранён. Ничего не будет отправлено до повторного подтверждения.',
                  style: TextStyle(
                      fontSize: 12, height: 1.5, color: Color(0xFF627187))),
              CheckboxListTile(
                  contentPadding: EdgeInsets.zero,
                  controlAffinity: ListTileControlAffinity.leading,
                  value: acknowledged,
                  onChanged: (v) => setState(() => acknowledged = v == true),
                  title: const UiText('Ознакомился с новой версией условий.',
                      style: TextStyle(fontSize: 12, height: 1.58))),
            ])),
            Container(
                decoration: const BoxDecoration(
                    color: Colors.white,
                    border: Border(top: BorderSide(color: line))),
                child: SafeArea(
                    top: false,
                    child: Padding(
                        padding: const EdgeInsets.fromLTRB(20, 12, 20, 4),
                        child: SizedBox(
                            width: double.infinity,
                            child: FilledButton(
                                onPressed: !acknowledged
                                    ? null
                                    : () => Navigator.push(
                                        context,
                                        MaterialPageRoute<void>(
                                            builder: (editorContext) =>
                                                Scaffold(
                                                    backgroundColor: canvas,
                                                    appBar: AppBar(
                                                        title: const UiText(
                                                            'Редактировать отклик')),
                                                    body: OfferEditor(
                                                        api: widget.api,
                                                        order: order,
                                                        offer: Json.from(r),
                                                        onSaved: (saved) {
                                                          Navigator.pop(
                                                              editorContext);
                                                          widget.onGo(
                                                              'offer-sent',
                                                              widget.id);
                                                        })))),
                                child: const UiText('Изменить мой отклик')))))),
          ]);
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
