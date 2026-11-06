import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../core/api.dart';
import '../core/currency.dart';
import '../core/design_widgets.dart';
import '../core/l10n.dart';
import '../core/theme.dart';
import '../core/widgets.dart';

const refundLabels = {
  'requested': 'На рассмотрении',
  'approved': 'Возврат согласован',
  'pending': 'Ожидается подтверждение',
  'unknown': 'Требуется сверка',
  'confirmed': 'Возврат подтверждён',
  'rejected': 'Заявка отклонена',
  'canceled': 'Заявка отменена',
  'failed': 'Возврат не выполнен',
};

// Decimal input is converted without floating point rounding, including on web.
int? parseRefundAmount(String value) {
  final raw = value.trim().replaceAll(',', '.');
  if (!RegExp(r'^\d{1,14}(\.\d{1,2})?$').hasMatch(raw)) return null;
  final parts = raw.split('.');
  final amount = int.parse(parts[0]) * 100 +
      int.parse(parts.length == 1 ? '0' : parts[1].padRight(2, '0'));
  return amount > 0 && amount <= 9007199254740991 ? amount : null;
}

class RefundsScreen extends StatefulWidget {
  final JobaApi api;
  final VoidCallback onSupport;
  const RefundsScreen({required this.api, required this.onSupport, super.key});
  @override
  State<RefundsScreen> createState() => _RefundsScreenState();
}

class _RefundsScreenState extends State<RefundsScreen> {
  bool history = false, busy = false;
  int revision = 0;
  Json? payment, request;
  Object? error;

  String money(dynamic amount, dynamic currency) =>
      amount is int && currency is String
          ? formatMoney(
              amount, currency, Localizations.localeOf(context).languageCode)
          : localize(context, 'Сумма уточняется');

  Widget details(String label, String value) => Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        UiText(label, style: const TextStyle(fontSize: 12, color: muted)),
        const SizedBox(height: 4),
        Text(value, style: const TextStyle(fontSize: 14)),
      ]));

  Widget card(Json row) => Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: ListTile(
          contentPadding: const EdgeInsets.all(16),
          title: Text(money(row['amount_minor'], row['currency'])),
          subtitle:
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const SizedBox(height: 6),
            UiText(history
                ? refundLabels[row['status']] ?? 'Статус уточняется'
                : row['benefit'] == 'boost'
                    ? 'Продвижение'
                    : 'Доступ исполнителя'),
            if (!history)
              Text(
                  '${localize(context, 'Доступно к возврату')}: ${money(row['balance']?['available_minor'], row['currency'])}'),
            if (row['created_at'] != null)
              Text(
                  DateFormat.yMMMd(Localizations.localeOf(context).languageCode)
                      .format(DateTime.parse(row['created_at']).toLocal())),
          ]),
          trailing: const Icon(Icons.chevron_right),
          onTap: busy
              ? null
              : () => setState(() {
                    error = null;
                    if (history) {
                      request = row;
                    } else {
                      payment = row;
                    }
                  })));

  Future<void> cancel() async {
    if (busy || request?['status'] != 'requested') return;
    final confirmed = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
              title: const UiText('Отменить заявку?'),
              content: const UiText(
                  'Зарезервированная сумма снова станет доступна для новой заявки. Это не отменяет покупку.'),
              actions: [
                TextButton(
                    onPressed: () => Navigator.pop(context, false),
                    child: const UiText('Назад')),
                FilledButton(
                    onPressed: () => Navigator.pop(context, true),
                    child: const UiText('Отменить заявку')),
              ],
            ));
    if (confirmed != true || !mounted) return;
    setState(() {
      busy = true;
      error = null;
    });
    try {
      final result = await widget.api.request(
          '/billing/refund-requests/${request!['id']}/cancel',
          method: 'POST',
          body: {
            'expected_version': request!['version'],
            'reason': 'Отменено пользователем',
          });
      if (mounted)
        setState(() {
          request = Map<String, dynamic>.from(result);
          revision++;
        });
    } catch (e) {
      if (mounted) setState(() => error = e);
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Widget requestDetails() {
    final row = request!;
    return ListView(padding: const EdgeInsets.all(20), children: [
      TextButton(
          onPressed: busy
              ? null
              : () => setState(() {
                    request = null;
                    error = null;
                    revision++;
                  }),
          child: const UiText('К истории заявок')),
      UiText(refundLabels[row['status']] ?? 'Статус уточняется',
          style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w700)),
      details('Номер заявки', '${row['id']}'),
      if (row['payment_id'] != null) details('Платёж', '${row['payment_id']}'),
      details('Сумма', money(row['amount_minor'], row['currency'])),
      if (row['reason'] != null)
        details('Причина обращения', '${row['reason']}'),
      if (row['access_action'] == 'revoked')
        const Notice('Доступ по возвращённой покупке отозван.'),
      if (row['status'] == 'unknown')
        const Notice(
            'Исход операции ещё не подтверждён. Сумма остаётся зарезервированной до сверки.'),
      if (['approved', 'pending'].contains(row['status']))
        const Notice(
            'Согласование заявки не означает зачисления денег. Статус изменится после подтверждения возврата.'),
      if (row['status'] == 'confirmed')
        const Notice(
            'Возврат подтверждён платёжной системой. Срок зачисления зависит от банка.'),
      if (error != null) Notice(errorText(context, error!), error: true),
      if (row['status'] == 'requested')
        OutlinedButton(
            onPressed: busy ? null : cancel,
            child: UiText(busy ? 'Подождите…' : 'Отменить заявку')),
      OutlinedButton(
          onPressed: busy
              ? null
              : () => setState(() {
                    request = null;
                    error = null;
                    revision++;
                  }),
          child: const UiText('Обновить историю')),
      TextButton(
          onPressed: busy ? null : widget.onSupport,
          child: const UiText('Обратиться в поддержку')),
    ]);
  }

  @override
  Widget build(BuildContext context) {
    if (payment != null)
      return RefundEditor(
        key: ValueKey(payment!['id']),
        api: widget.api,
        payment: payment!,
        onBack: () => setState(() {
          payment = null;
          revision++;
        }),
        onSaved: (value) => setState(() {
          payment = null;
          history = true;
          request = value;
          revision++;
        }),
      );
    if (request != null) return requestDetails();
    return Column(children: [
      Padding(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
          child: Row(children: [
            Expanded(
                child: ChoiceChip(
                    label: const UiText('Платежи'),
                    selected: !history,
                    onSelected: (_) => setState(() => history = false))),
            const SizedBox(width: 12),
            Expanded(
                child: ChoiceChip(
                    label: const UiText('Заявки'),
                    selected: history,
                    onSelected: (_) => setState(() => history = true))),
          ])),
      Expanded(
          child: PagedList(
        key: ValueKey('refunds:$history:$revision'),
        api: widget.api,
        path: history
            ? '/billing/refund-requests'
            : '/billing/refundable-payments',
        empty: history
            ? 'Заявок на возврат пока нет'
            : 'Подтверждённых платежей пока нет',
        header: const Padding(
            padding: EdgeInsets.only(bottom: 16),
            child: Notice(
                'Заявка на возврат рассматривается отдельно. До подтверждения деньги не считаются возвращёнными.')),
        tile: card,
        footer: TextButton(
            onPressed: widget.onSupport,
            child: const UiText('Обратиться в поддержку')),
      )),
    ]);
  }
}

class RefundEditor extends StatefulWidget {
  final JobaApi api;
  final Json payment;
  final VoidCallback onBack;
  final ValueChanged<Json> onSaved;
  const RefundEditor(
      {required this.api,
      required this.payment,
      required this.onBack,
      required this.onSaved,
      super.key});
  @override
  State<RefundEditor> createState() => _RefundEditorState();
}

class _RefundEditorState extends State<RefundEditor> {
  final form = GlobalKey<FormState>();
  final amount = TextEditingController(), reason = TextEditingController();
  bool busy = false, acknowledged = false;
  Object? error;
  Json? uncertainBody;
  int get available =>
      widget.payment['balance']?['available_minor'] as int? ?? 0;
  @override
  void dispose() {
    amount.dispose();
    reason.dispose();
    super.dispose();
  }

  Future<void> submit() async {
    if (busy ||
        !acknowledged ||
        uncertainBody == null && !form.currentState!.validate()) return;
    final body = uncertainBody ??
        {
          'payment_id': widget.payment['id'],
          'amount_minor': parseRefundAmount(amount.text),
          'reason': reason.text.trim(),
        };
    setState(() {
      busy = true;
      error = null;
    });
    try {
      final result = await widget.api
          .request('/billing/refund-requests', method: 'POST', body: body);
      if (mounted) widget.onSaved(Map<String, dynamic>.from(result));
    } catch (e) {
      if (mounted)
        setState(() {
          error = e;
          // A lost response may have created a request. Retry exactly that payload
          // with JobaApi's retained idempotency key; do not silently create another.
          uncertainBody = e is! ApiException || e.status == 0 || e.status >= 500
              ? body
              : null;
        });
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final locked = busy || uncertainBody != null;
    final currency = '${widget.payment['currency']}';
    final locale = Localizations.localeOf(context).languageCode;
    return Form(
        key: form,
        child: ListView(padding: const EdgeInsets.all(20), children: [
          TextButton(
              onPressed: busy ? null : widget.onBack,
              child: const UiText('К платежам')),
          const UiText('Заявка на возврат',
              style: TextStyle(fontSize: 24, fontWeight: FontWeight.w700)),
          const SizedBox(height: 16),
          Text('${localize(context, 'Платёж')}: ${widget.payment['id']}'),
          const SizedBox(height: 12),
          Text(
              '${localize(context, 'Доступно')}: ${formatMoney(available, currency, locale)}'),
          if (widget.payment['balance']?['reserved_minor'] is int &&
              widget.payment['balance']['reserved_minor'] > 0)
            Text(
                '${localize(context, 'Зарезервировано другими заявками')}: ${formatMoney(widget.payment['balance']['reserved_minor'], currency, locale)}'),
          const SizedBox(height: 20),
          TextFormField(
              key: const ValueKey('refund-amount'),
              controller: amount,
              enabled: !locked && available > 0,
              keyboardType:
                  const TextInputType.numberWithOptions(decimal: true),
              decoration: InputDecoration(
                  labelText: localize(context, 'Сумма возврата'),
                  suffixText: currency),
              validator: (value) {
                final parsed = parseRefundAmount(value ?? '');
                if (parsed == null)
                  return localize(context,
                      'Введите положительную сумму, не более двух знаков после запятой');
                if (parsed > available)
                  return localize(context, 'Сумма превышает доступный остаток');
                return null;
              }),
          const SizedBox(height: 16),
          TextFormField(
              key: const ValueKey('refund-reason'),
              controller: reason,
              enabled: !locked && available > 0,
              minLines: 3,
              maxLines: 5,
              maxLength: 1000,
              decoration: InputDecoration(
                  labelText: localize(context, 'Причина возврата')),
              validator: (value) => (value ?? '').trim().length < 5
                  ? localize(context, 'Укажите причину: от 5 до 1000 символов')
                  : null),
          CheckboxListTile(
              contentPadding: EdgeInsets.zero,
              value: acknowledged,
              onChanged: locked || available <= 0
                  ? null
                  : (value) => setState(() => acknowledged = value == true),
              title: const UiText(
                  'Понимаю, что заявка будет рассмотрена, а возврат может повлиять на доступ по этой покупке.')),
          if (available <= 0)
            const Notice(
                'Доступного остатка нет. Проверьте историю заявок или обновите платежи.'),
          if (uncertainBody != null)
            const Notice(
                'Ответ не получен. Повторите отправку без изменения данных или проверьте историю заявок.'),
          if (error != null) Notice(errorText(context, error!), error: true),
          FilledButton(
              onPressed:
                  busy || !acknowledged || available <= 0 ? null : submit,
              child: UiText(busy
                  ? 'Отправляем…'
                  : uncertainBody != null
                      ? 'Повторить отправку'
                      : 'Отправить заявку')),
          const Notice(
              'Отправка заявки не означает выполнения возврата. Итоговый статус появится в истории.'),
        ]));
  }
}
