import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../core/api.dart';
import '../core/currency.dart';
import '../core/design_icons.dart';
import '../core/design_widgets.dart';
import '../core/l10n.dart';
import '../core/theme.dart';

class OfferEditor extends StatefulWidget {
  final JobaApi api;
  final Json order;
  final Json? offer;
  final void Function(Json) onSaved;
  const OfferEditor(
      {required this.api,
      required this.order,
      required this.onSaved,
      this.offer,
      super.key});
  @override
  State<OfferEditor> createState() => _OfferEditorState();
}

class _OfferEditorState extends State<OfferEditor> {
  final form = GlobalKey<FormState>();
  late final TextEditingController note, price, duration;
  late Json order;
  DateTime? start, expiry;
  bool accepted = false, busy = false, expiryChanged = false;
  Object? error;
  String get zone =>
      '${order['offer_policy']?['time_zone'] ?? order['time_window']?['time_zone'] ?? const {
            'KZ': 'Asia/Almaty',
            'KG': 'Asia/Bishkek',
            'RU': 'Europe/Moscow',
            'BY': 'Europe/Minsk'
          }[order['country']] ?? 'Asia/Almaty'}';
  @override
  void initState() {
    super.initState();
    order = widget.order;
    note = TextEditingController(text: widget.offer?['text'] ?? '');
    price = TextEditingController(
        text: widget.offer?['amount'] == null
            ? ''
            : '${(widget.offer!['amount'] as num) / 100}');
    duration = TextEditingController(
        text: widget.offer?['duration_minutes'] == null
            ? ''
            : '${(widget.offer!['duration_minutes'] as num) / 60}');
    start = DateTime.tryParse('${widget.offer?['proposed_start_local']}');
    // Calendar values are local wall time in the service zone, never device UTC conversions.
    expiry = DateTime.tryParse(
        '${widget.offer?['expires_local'] ?? order['offer_policy']?['latest_expires_local']}');
  }

  @override
  void dispose() {
    note.dispose();
    price.dispose();
    duration.dispose();
    super.dispose();
  }

  String local(DateTime date) => DateFormat("yyyy-MM-dd'T'HH:mm").format(date);
  int? amount(String value) {
    final raw = value.trim().replaceAll(',', '.');
    if (!RegExp(r'^\d+(\.\d{1,2})?$').hasMatch(raw)) return null;
    final parts = raw.split('.'), whole = int.tryParse(parts[0]);
    if (whole == null || whole > 90071992547409) return null;
    final result = whole * 100 +
        int.parse(parts.length == 1 ? '0' : parts[1].padRight(2, '0'));
    return result > 9007199254740991 ? null : result;
  }

  Future<DateTime?> pick(DateTime? current,
      {required bool clock, bool validity = false}) async {
    final today = DateUtils.dateOnly(DateTime.now());
    final windowStart =
        DateTime.tryParse('${order['time_window']?['start_date']}');
    final windowEnd = DateTime.tryParse('${order['time_window']?['end_date']}');
    final first = !validity && windowStart != null && windowStart.isAfter(today)
        ? windowStart
        : today;
    final policyEnd =
        DateTime.tryParse('${order['offer_policy']?['latest_expires_local']}');
    var last = validity
        ? policyEnd ?? today.add(const Duration(days: 365))
        : windowEnd ?? today.add(const Duration(days: 365));
    if (validity && start != null && start!.isBefore(last)) last = start!;
    if (last.isBefore(first)) {
      setState(() => error = ApiException('DATES_UNAVAILABLE',
          'Выбранные заказчиком даты уже прошли. Уточните новые условия заказа.'));
      return null;
    }
    var initial = current ?? first;
    if (initial.isBefore(first)) initial = first;
    if (initial.isAfter(last)) initial = last;
    final date = await showDatePicker(
        context: context,
        firstDate: first,
        lastDate: last,
        initialDate: initial);
    if (date == null || !mounted) return null;
    final time = clock
        ? await showTimePicker(
            context: context,
            initialTime: current == null
                ? const TimeOfDay(hour: 10, minute: 0)
                : TimeOfDay.fromDateTime(current))
        : TimeOfDay(hour: current?.hour ?? 10, minute: current?.minute ?? 0);
    if (time == null) return null;
    return DateTime(date.year, date.month, date.day, time.hour, time.minute);
  }

  Future<void> save() async {
    if (busy || !accepted || !form.currentState!.validate()) return;
    setState(() {
      busy = true;
      error = null;
    });
    try {
      final body = <String, dynamic>{
        'amount': amount(price.text),
        'text': note.text.trim(),
        'acknowledged_revision': order['revision'],
        'proposed_start_local': start == null ? null : local(start!),
        'duration_minutes': duration.text.trim().isEmpty
            ? null
            : (double.parse(duration.text.replaceAll(',', '.')) * 60).round(),
        if (expiry != null && (widget.offer == null || expiryChanged))
          'expires_local': local(expiry!),
        if (widget.offer != null) 'expected_version': widget.offer!['version']
      };
      final result = await widget.api.request(
          widget.offer == null
              ? '/orders/${order['id']}/offers'
              : '/offers/${widget.offer!['id']}',
          method: widget.offer == null ? 'POST' : 'PATCH',
          body: body);
      if (mounted) widget.onSaved(Json.from(result));
    } catch (e) {
      if (e is ApiException && e.code == 'REVISION_NOT_ACKNOWLEDGED') {
        try {
          final current = await widget.api.request('/orders/${order['id']}');
          if (mounted)
            setState(() {
              order = Json.from(current);
              accepted = false;
            });
        } catch (_) {
          if (mounted) setState(() => accepted = false);
        }
      }
      if (mounted) setState(() => error = e);
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Widget label(String value) => Padding(
      padding: const EdgeInsets.only(top: 18, bottom: 8),
      child: UiText(value,
          style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700)));
  Widget choice(String value, VoidCallback onTap, {String icon = 'down'}) =>
      OutlinedButton(
          style: OutlinedButton.styleFrom(
              backgroundColor: Colors.white,
              alignment: Alignment.centerLeft,
              minimumSize: const Size(double.infinity, 52),
              padding: const EdgeInsets.symmetric(horizontal: 14),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12))),
          onPressed: busy ? null : onTap,
          child: Row(children: [
            Expanded(
                child: Text(value,
                    style: const TextStyle(
                        fontSize: 14, fontWeight: FontWeight.w400))),
            JobaIcon(icon, size: 18)
          ]));
  @override
  Widget build(BuildContext context) {
    final locale = Localizations.localeOf(context).languageCode;
    final budget = order['budget_amount'] == null
        ? localize(context, 'По договорённости')
        : formatMoney(order['budget_amount'], '${order['currency']}', locale);
    final enabled = order['status'] == 'open' &&
        (widget.offer == null || widget.offer!['status'] == 'active');
    return Column(children: [
      Expanded(
          child: Form(
              key: form,
              child: ListView(padding: const EdgeInsets.all(20), children: [
                Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                        color: Colors.white,
                        border: Border.all(color: line),
                        borderRadius: BorderRadius.circular(16)),
                    child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                              '${localize(context, 'Заказ')} № ${order['id'].toString().substring(0, order['id'].toString().length.clamp(0, 8))}',
                              style: const TextStyle(
                                  fontSize: 11,
                                  color: muted,
                                  fontWeight: FontWeight.w700)),
                          const SizedBox(height: 8),
                          Text('${order['title']}',
                              style: const TextStyle(
                                  fontSize: 16, fontWeight: FontWeight.w700)),
                          const SizedBox(height: 8),
                          Text('${localize(context, 'Бюджет')} $budget',
                              style:
                                  const TextStyle(fontSize: 12, color: muted)),
                        ])),
                label('Ваше предложение'),
                TextFormField(
                    key: const ValueKey('offer-note'),
                    controller: note,
                    enabled: !busy,
                    minLines: 4,
                    maxLines: 6,
                    maxLength: 3000,
                    decoration: const InputDecoration(counterText: ''),
                    validator: (v) => v == null || v.trim().isEmpty
                        ? localize(context, 'Заполните поле')
                        : null),
                Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Expanded(
                      child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                        label('Ваша цена'),
                        TextFormField(
                            key: const ValueKey('offer-price'),
                            controller: price,
                            enabled: !busy,
                            keyboardType: const TextInputType.numberWithOptions(
                                decimal: true),
                            decoration:
                                InputDecoration(suffixText: order['currency']),
                            validator: (v) => amount(v ?? '') == null
                                ? localize(context, 'Проверьте цену')
                                : null),
                      ])),
                  const SizedBox(width: 12),
                  Expanded(
                      child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                        label('Когда начнёте'),
                        choice(
                            start == null
                                ? localize(context, 'Выберите дату')
                                : DateFormat.MMMd(locale).format(start!),
                            () async {
                          final value = await pick(start, clock: false);
                          if (value != null && mounted)
                            setState(() {
                              start = value;
                              if (expiry != null && expiry!.isAfter(value)) {
                                expiry = value;
                                expiryChanged = true;
                              }
                            });
                        }),
                      ]))
                ]),
                label('Время и срок работы'),
                Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Expanded(
                      child: choice(
                          start == null
                              ? localize(context, 'Время согласуем')
                              : DateFormat.Hm(locale).format(start!), () async {
                    final value = await pick(start, clock: true);
                    if (value != null && mounted)
                      setState(() {
                        start = value;
                        if (expiry != null && expiry!.isAfter(value)) {
                          expiry = value;
                          expiryChanged = true;
                        }
                      });
                  }, icon: 'clock')),
                  const SizedBox(width: 12),
                  Expanded(
                      child: TextFormField(
                          key: const ValueKey('offer-duration'),
                          controller: duration,
                          enabled: !busy,
                          keyboardType: const TextInputType.numberWithOptions(
                              decimal: true),
                          decoration: InputDecoration(
                              hintText: localize(context, 'Часов'),
                              suffixText: localize(context, 'ч')),
                          validator: (v) {
                            if (v == null || v.trim().isEmpty) return null;
                            final n = double.tryParse(v.replaceAll(',', '.'));
                            return n == null ||
                                    !n.isFinite ||
                                    n <= 0 ||
                                    n * 60 < 1 ||
                                    n * 60 > 9007199254740991
                                ? localize(context, 'Проверьте длительность')
                                : null;
                          }))
                ]),
                const SizedBox(height: 8),
                Text('${localize(context, 'Местное время заказа')}: $zone',
                    style: const TextStyle(fontSize: 10, color: muted)),
                if (start != null)
                  TextButton(
                      onPressed:
                          busy ? null : () => setState(() => start = null),
                      child: const UiText('Очистить начало работы')),
                label('Отклик действует до'),
                choice(
                    expiry == null
                        ? localize(context, 'По правилам страны')
                        : '${DateFormat.MMMd(locale).format(expiry!)} · ${DateFormat.Hm(locale).format(expiry!)}',
                    () async {
                  final value = await pick(expiry, clock: true, validity: true);
                  if (value != null && mounted)
                    setState(() {
                      expiry = value;
                      expiryChanged = true;
                    });
                }),
                CheckboxListTile(
                    contentPadding: EdgeInsets.zero,
                    controlAffinity: ListTileControlAffinity.leading,
                    value: accepted,
                    onChanged: busy
                        ? null
                        : (v) => setState(() => accepted = v == true),
                    title: const UiText(
                        'Подтверждаю текущую версию условий заказа.',
                        style: TextStyle(fontSize: 12, height: 1.58))),
                const Notice(
                    'Отклик не гарантирует выбор. Договорённость закрепится после подтверждения заказчика.',
                    icon: 'info'),
                if (!enabled)
                  const Notice(
                      'Отклик или заказ больше не доступен для изменения.'),
                if (error != null)
                  Notice(errorText(context, error!), error: true),
              ]))),
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
                          onPressed:
                              busy || !accepted || !enabled ? null : save,
                          child: UiText(widget.offer == null
                              ? 'Отправить отклик'
                              : 'Сохранить')))))),
    ]);
  }
}
