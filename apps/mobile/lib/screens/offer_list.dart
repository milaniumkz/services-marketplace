import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../core/api.dart';
import '../core/currency.dart';
import '../core/design_icons.dart';
import '../core/design_widgets.dart';
import '../core/l10n.dart';
import '../core/theme.dart';

class OfferList extends StatefulWidget {
  final JobaApi api;
  final Json order;
  final List<Json> offers;
  final void Function(String route, String id) onGo;
  const OfferList(
      {required this.api,
      required this.order,
      required this.offers,
      required this.onGo,
      super.key});
  @override
  State<OfferList> createState() => _OfferListState();
}

class _OfferListState extends State<OfferList> {
  String sort = 'all';
  Widget card(List<Widget> children) => Container(
      padding: const EdgeInsets.all(16),
      margin: const EdgeInsets.only(bottom: 14),
      decoration: BoxDecoration(
          color: Colors.white,
          border: Border.all(color: line),
          borderRadius: BorderRadius.circular(16)),
      child: Column(
          crossAxisAlignment: CrossAxisAlignment.start, children: children));
  @override
  Widget build(BuildContext context) {
    final locale = Localizations.localeOf(context).languageCode;
    final rows = List<Json>.from(widget.offers);
    if (sort != 'all')
      rows.sort((a, b) {
        final comparison = sort == 'price'
            ? (a['amount'] as num).compareTo(b['amount'] as num)
            : ((b['executor']?['rating']?['average'] ?? -1) as num)
                .compareTo((a['executor']?['rating']?['average'] ?? -1) as num);
        return comparison != 0
            ? comparison
            : '${a['id']}'.compareTo('${b['id']}');
      });
    return ListView(padding: const EdgeInsets.all(20), children: [
      card([
        Text('${widget.order['title']}',
            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
        const SizedBox(height: 4),
        Text(
            widget.order['budget_amount'] == null
                ? localize(context, 'По договорённости')
                : formatMoney(widget.order['budget_amount'],
                    '${widget.order['currency']}', locale),
            style: const TextStyle(fontSize: 12, color: muted))
      ]),
      SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(children: [
            for (final entry in {
              'all': '${localize(context, 'Все')} · ${rows.length}',
              'price': localize(context, 'По цене'),
              'rating': localize(context, 'По рейтингу')
            }.entries)
              Padding(
                  padding: const EdgeInsets.only(right: 8, bottom: 16),
                  child: ChoiceChip(
                      label: Text(entry.value),
                      selected: sort == entry.key,
                      showCheckmark: false,
                      selectedColor: navy,
                      backgroundColor: Colors.white,
                      labelStyle: TextStyle(
                          fontSize: 12,
                          color: sort == entry.key ? Colors.white : navy),
                      padding: const EdgeInsets.symmetric(
                          horizontal: 10, vertical: 12),
                      onSelected: (_) => setState(() => sort = entry.key)))
          ])),
      if (rows.isEmpty) const Notice('Откликов пока нет'),
      for (final offer in rows)
        card([
          Row(children: [
            JobaAvatar(
                api: widget.api,
                name: offer['executor']?['display_name'] ?? '',
                id: offer['executor']?['avatar_id']),
            const SizedBox(width: 10),
            Expanded(
                child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                  Text(
                      offer['executor']?['display_name'] ??
                          localize(context, 'Исполнитель'),
                      style: const TextStyle(
                          fontSize: 16, fontWeight: FontWeight.w700)),
                  if ((offer['executor']?['rating']?['count'] as num? ?? 0) > 0)
                    Row(children: [
                      const JobaIcon('star',
                          size: 14, color: Color(0xFFCC941A), fill: yellow),
                      const SizedBox(width: 4),
                      Text(
                          '${NumberFormat('0.0', locale).format(offer['executor']['rating']['average'])} (${offer['executor']['rating']['count']})',
                          style: const TextStyle(fontSize: 12))
                    ]),
                ])),
            if (offer['executor']?['verified'] == true)
              const JobaIcon('shield', color: primary),
          ]),
          const SizedBox(height: 16),
          Text(formatMoney(offer['amount'], '${offer['currency']}', locale),
              style:
                  const TextStyle(fontSize: 20, fontWeight: FontWeight.w700)),
          if (offer['proposed_start_local'] != null ||
              offer['duration_minutes'] != null)
            Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text(
                    [
                      if (offer['proposed_start_local'] != null)
                        DateFormat('d MMMM, HH:mm', locale).format(
                            DateTime.parse(offer['proposed_start_local'])),
                      if (offer['duration_minutes'] != null)
                        '${offer['duration_minutes']} ${localize(context, 'мин')}',
                    ].join(' · '),
                    style: const TextStyle(fontSize: 12, color: muted))),
          const SizedBox(height: 12),
          Text('${offer['text'] ?? ''}',
              style: const TextStyle(fontSize: 12, height: 1.5)),
          if (offer['status'] != 'active')
            Padding(
                padding: const EdgeInsets.only(top: 8),
                child: JobaBadge(localize(
                    context,
                    const {
                          'expired': 'Срок истёк',
                          'selected': 'Выбран',
                          'not_selected': 'Не выбран',
                          'withdrawn': 'Отозван'
                        }[offer['status']] ??
                        '${offer['status']}'))),
          const SizedBox(height: 16),
          Row(children: [
            Expanded(
                child: OutlinedButton(
                    onPressed: offer['conversation_id'] == null
                        ? null
                        : () => widget.onGo('chat', offer['conversation_id']),
                    child: const UiText('Уточнить'))),
            const SizedBox(width: 10),
            Expanded(
                child: FilledButton(
                    onPressed: offer['status'] == 'active' &&
                            widget.order['status'] == 'open' &&
                            offer['executor'] != null &&
                            offer['executor']?['available'] != false
                        ? () => widget.onGo('select-contractor', offer['id'])
                        : null,
                    child: const UiText('Выбрать'))),
          ]),
        ]),
    ]);
  }
}
