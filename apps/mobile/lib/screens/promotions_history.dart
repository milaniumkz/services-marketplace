import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../core/api.dart';
import '../core/currency.dart';
import '../core/design_states.dart';
import '../core/design_widgets.dart';
import '../core/l10n.dart';
import '../core/theme.dart';
import '../core/widgets.dart';

const boostStates = {
  'active': 'Активно',
  'scheduled': 'Запланировано',
  'paused': 'Приостановлено',
  'expired': 'Завершено',
  'revoked': 'Отозвано',
  'reserved': 'Резерв',
  'payment_pending': 'Проверяется',
  'resolution_required': 'Нужно решение'
};

class PromotionsHistory extends StatefulWidget {
  final JobaApi api;
  final VoidCallback onNew;
  final VoidCallback? onTerms;
  final ValueChanged<Json> onOpen;
  final String Function(dynamic) dateLabel;
  const PromotionsHistory(
      {required this.api,
      required this.onNew,
      this.onTerms,
      required this.onOpen,
      required this.dateLabel,
      super.key});
  @override
  State<PromotionsHistory> createState() => _PromotionsHistoryState();
}

class _PromotionsHistoryState extends State<PromotionsHistory> {
  String bucket = 'active';
  String dateRange(BuildContext context, Json r) {
    final start = DateTime.tryParse('${r['starts_at'] ?? ''}')?.toUtc(),
        end = DateTime.tryParse('${r['ends_at'] ?? ''}')?.toUtc();
    if (start == null || end == null) return widget.dateLabel(null);
    final locale = Localizations.localeOf(context).languageCode;
    if (start.year == end.year && end.year == DateTime.now().year) {
      if (start.month == end.month)
        return '${start.day}–${DateFormat('d MMMM', locale).format(end)}';
      return '${DateFormat('d MMMM', locale).format(start)} — ${DateFormat('d MMMM', locale).format(end)}';
    }
    return '${widget.dateLabel(start.toIso8601String())} — ${widget.dateLabel(end.toIso8601String())}';
  }

  String placementLabel(dynamic id) =>
      const {
        'search.services.promoted': 'Каталог услуг',
        'search.orders.promoted': 'Лента заказов',
        'home.promoted.services': 'Услуги на главной',
        'top.services.promoted': 'Топ услуг',
        'top.orders.promoted': 'Топ заказов'
      }[id] ??
      'Продвижение';

  Widget row(String label, String value) => Padding(
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: Row(children: [
        Expanded(child: UiText(label, style: const TextStyle(fontSize: 13))),
        const SizedBox(width: 12),
        Expanded(
            child: Text(value,
                textAlign: TextAlign.right,
                style:
                    const TextStyle(fontWeight: FontWeight.w700, fontSize: 12)))
      ]));
  @override
  Widget build(BuildContext context) => Column(children: [
        Expanded(
            child: PagedList(
                key: ValueKey(bucket),
                api: widget.api,
                path: '/me/boosts',
                query: {'bucket': bucket},
                header: Padding(
                    padding: const EdgeInsets.only(bottom: 16),
                    child: Row(children: [
                      for (final entry in {
                        'active': 'Активные',
                        'history': 'История'
                      }.entries)
                        Padding(
                            padding: const EdgeInsets.only(right: 8),
                            child: ChoiceChip(
                                showCheckmark: false,
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 14, vertical: 14),
                                labelPadding: EdgeInsets.zero,
                                side: BorderSide(
                                    color: bucket == entry.key ? navy : line),
                                selected: bucket == entry.key,
                                label: UiText(entry.value),
                                onSelected: (_) =>
                                    setState(() => bucket = entry.key),
                                selectedColor: navy,
                                backgroundColor: Colors.white,
                                labelStyle: TextStyle(
                                    fontSize: 13,
                                    height: 1.55,
                                    fontWeight: FontWeight.w400,
                                    color: bucket == entry.key
                                        ? Colors.white
                                        : navy),
                                shape: const StadiumBorder()))
                    ])),
                tile: (r) => Container(
                    margin: const EdgeInsets.only(bottom: 16),
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                        color: Colors.white,
                        border: Border.all(color: line),
                        borderRadius: BorderRadius.circular(22)),
                    child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(children: [
                            if (r['status'] == 'active')
                              const JobaBadge('Продвигается',
                                  background: Color(0xFFFFF4D4),
                                  foreground: Color(0xFF805900)),
                            const Spacer(),
                            JobaBadge(boostStates[r['status']] ?? 'Размещение',
                                background: r['status'] == 'active'
                                    ? const Color(0xFFE8F5EE)
                                    : const Color(0xFFEAF0FC),
                                foreground: r['status'] == 'active'
                                    ? const Color(0xFF178061)
                                    : primary)
                          ]),
                          const SizedBox(height: 16),
                          Text('${r['title'] ?? ''}',
                              style: const TextStyle(
                                  fontSize: 20, fontWeight: FontWeight.w700)),
                          const SizedBox(height: 8),
                          Text(
                              '${localize(context, placementLabel(r['placement_id']))} · ${r['city'] ?? ''}',
                              style:
                                  const TextStyle(fontSize: 13, color: muted)),
                          const SizedBox(height: 16),
                          const Divider(height: 1),
                          row('Срок', dateRange(context, r)),
                          const Divider(height: 1),
                          row(
                              'Источник',
                              localize(
                                  context,
                                  r['provenance'] == 'admin_grant'
                                      ? 'Административное выделение'
                                      : r['provenance'] == 'paid'
                                          ? 'Разовая покупка'
                                          : 'Резерв')),
                          const Divider(height: 1),
                          row(
                              r['payment_confirmed'] == true
                                  ? 'Оплачено'
                                  : 'Стоимость',
                              r['provenance'] == 'admin_grant'
                                  ? localize(context, 'Бесплатно')
                                  : r['price']?['amount_minor'] is int &&
                                          r['price']?['currency'] is String
                                      ? formatMoney(
                                          r['price']['amount_minor'],
                                          r['price']['currency'],
                                          Localizations.localeOf(context)
                                              .languageCode)
                                      : '—'),
                          const Divider(height: 1),
                          const SizedBox(height: 12),
                          const UiText('Без автопродления',
                              style: TextStyle(fontSize: 11, color: muted)),
                          const SizedBox(height: 16),
                          OutlinedButton(
                              onPressed:
                                  widget.onTerms ?? () => widget.onOpen(r),
                              child: const UiText('Условия и помощь')),
                          if (widget.onTerms != null)
                            TextButton(
                                onPressed: () => widget.onOpen(r),
                                child: const UiText('Проверить размещение'))
                        ])))),
        Container(
            decoration: const BoxDecoration(
                color: Colors.white,
                border: Border(top: BorderSide(color: line))),
            child: SafeArea(
                top: false,
                child: Padding(
                    padding: const EdgeInsets.fromLTRB(20, 12, 20, 4),
                    child: FilledButton(
                        onPressed: widget.onNew,
                        child: const UiText('Новое продвижение')))))
      ]);
}

class PromotionStatus extends StatelessWidget {
  final JobaApi api;
  final String id;
  final VoidCallback onHistory, onSupport;
  const PromotionStatus(
      {required this.api,
      required this.id,
      required this.onHistory,
      required this.onSupport,
      super.key});
  @override
  Widget build(BuildContext context) => ApiView(
      load: () => api.request('/me/boosts/$id'),
      builder: (context, r, reload) {
        final state = r['status'], paid = r['payment_confirmed'] == true;
        String title, message, icon = 'clock';
        if (state == 'resolution_required') {
          title = paid
              ? 'Оплата подтверждена,\nместо недоступно'
              : 'Нужно решение\nпо размещению';
          message = paid
              ? 'Продвижение не началось. Поддержка проверит возврат у провайдера или согласует другое размещение. Возврат ещё не выполнен.'
              : 'Поддержка проверит состояние размещения и доступность карточки. Подтверждённой оплаты в этом статусе нет.';
          icon = 'help';
        } else if (state == 'payment_pending') {
          title = 'Платёж проверяется';
          message =
              'Размещение начнётся после подтверждения транзакции и повторной проверки доступности карточки. Повторять оплату не нужно.';
        } else if (state == 'reserved') {
          title = 'Место зарезервировано';
          message =
              'Оплата ещё не подтверждена. Резерв не означает начало продвижения.';
        } else if (state == 'active') {
          title = 'Размещение действует';
          message = 'Условия и срок доступны в истории продвижений.';
          icon = 'check';
        } else {
          title = boostStates[state] ?? 'Размещение';
          message =
              'Актуальные сведения о размещении доступны в истории. При необходимости обратитесь в поддержку.';
        }
        return RefreshIndicator(
            onRefresh: () async => reload(),
            child: ListView(padding: const EdgeInsets.all(20), children: [
              JobaStatePanel(
                  icon: icon,
                  title: title,
                  message: message,
                  primaryLabel: state == 'resolution_required'
                      ? 'Связаться с поддержкой'
                      : 'Посмотреть историю',
                  onPrimary:
                      state == 'resolution_required' ? onSupport : onHistory),
              TextButton(
                  onPressed: reload, child: const UiText('Обновить статус'))
            ]));
      });
}
