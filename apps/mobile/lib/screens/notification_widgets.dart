import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../core/api.dart';
import '../core/design_icons.dart';
import '../core/design_widgets.dart';
import '../core/l10n.dart';
import '../core/theme.dart';

class NotificationHeader extends StatelessWidget {
  final String category;
  final ValueChanged<String> onCategory;
  final VoidCallback onSettings;
  const NotificationHeader(
      {required this.category,
      required this.onCategory,
      required this.onSettings,
      super.key});
  @override
  Widget build(BuildContext context) => Container(
      color: Colors.white,
      padding: const EdgeInsets.all(20),
      child: Column(children: [
        Row(children: [
          const Expanded(
              child: UiText('События',
                  style: TextStyle(
                      fontSize: 26,
                      height: 33 / 26,
                      letterSpacing: -.9,
                      fontWeight: FontWeight.w700))),
          IconButton(
              tooltip: localize(context, 'Настройки уведомлений'),
              onPressed: onSettings,
              icon: const JobaIcon('filter'))
        ]),
        const SizedBox(height: 16),
        Container(
            width: double.infinity,
            height: 49,
            decoration: const BoxDecoration(
                border: Border(bottom: BorderSide(color: line))),
            child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(children: [
                  for (final e in const {
                    'all': 'Все',
                    'orders': 'Заказы',
                    'account': 'Аккаунт'
                  }.entries)
                    Padding(
                        padding: const EdgeInsets.only(right: 22),
                        child: Semantics(
                            selected: category == e.key,
                            button: true,
                            child: InkWell(
                                onTap: () => onCategory(e.key),
                                child: Container(
                                    alignment: Alignment.center,
                                    height: 49,
                                    decoration: BoxDecoration(
                                        border: Border(
                                            bottom: BorderSide(
                                                color: category == e.key
                                                    ? primary
                                                    : Colors.transparent,
                                                width: 2))),
                                    child: UiText(e.value,
                                        style: TextStyle(
                                            fontSize: 12,
                                            height: 1.5,
                                            color: category == e.key
                                                ? primary
                                                : muted,
                                            fontWeight: category == e.key
                                                ? FontWeight.w700
                                                : FontWeight.w400))))))
                ])))
      ]));
}

class NotificationGroups extends StatelessWidget {
  final List<Json> rows;
  final DateTime now;
  final String Function(Json) title;
  final void Function(Json) onOpen;
  const NotificationGroups(
      {required this.rows,
      required this.now,
      required this.title,
      required this.onOpen,
      super.key});
  DateTime? date(Json row) =>
      DateTime.tryParse('${row['created_at'] ?? ''}')?.toLocal();
  String day(BuildContext context, Json row) {
    final value = date(row), today = now.toLocal();
    if (value == null) return localize(context, 'Ранее');
    final current = DateTime(today.year, today.month, today.day),
        then = DateTime(value.year, value.month, value.day);
    if (then == current) return localize(context, 'Сегодня');
    if (then == DateTime(today.year, today.month, today.day - 1))
      return localize(context, 'Вчера');
    return DateFormat('d MMMM y', Localizations.localeOf(context).languageCode)
        .format(value);
  }

  String icon(Json r) {
    final type = '${r['type']}';
    if (type.startsWith('offer.')) return 'brief';
    if (type == 'order.completion_requested') return 'check';
    if (type.startsWith('support.') || type.startsWith('message.'))
      return 'chat';
    if (type.startsWith('verification.')) return 'shield';
    if (type.startsWith('subscription.')) return 'card';
    if (type.startsWith('portfolio.') || type == 'content.moderated')
      return 'image';
    return 'bell';
  }

  double rowHeight(Json r) =>
      ['brief', 'chat', 'card', 'image'].contains(icon(r)) ? 80.5 : 62.5;
  String subtitle(Json r) {
    final body = '${r['body'] ?? ''}', value = date(r), type = '${r['type']}';
    if (value != null &&
        (r['category'] == 'orders' ||
            type.startsWith('order.') ||
            type.startsWith('offer.') ||
            type.startsWith('support.') ||
            type.startsWith('message.'))) {
      final time = DateFormat('HH:mm').format(value);
      return body.isEmpty ? time : '$body · $time';
    }
    return body;
  }

  @override
  Widget build(BuildContext context) {
    final groups = <String, List<Json>>{};
    for (final r in rows) groups.putIfAbsent(day(context, r), () => []).add(r);
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      for (final entry in groups.entries) ...[
        if (entry.key != groups.keys.first) const SizedBox(height: 24),
        Text(entry.key.toUpperCase(),
            style: const TextStyle(
                fontSize: 11,
                height: 1.45,
                letterSpacing: 1.2,
                fontWeight: FontWeight.w700,
                color: muted)),
        const SizedBox(height: 17),
        Container(
            decoration: BoxDecoration(
                color: Colors.white,
                border: Border.all(color: line),
                borderRadius: BorderRadius.circular(16)),
            padding: const EdgeInsets.all(1),
            clipBehavior: Clip.antiAlias,
            child: Column(children: [
              for (var i = 0; i < entry.value.length; i++) ...[
                if (i > 0) const Divider(height: 1),
                Material(
                    color: Colors.white,
                    child: InkWell(
                        onTap: () => onOpen(entry.value[i]),
                        child: ConstrainedBox(
                            constraints: BoxConstraints(
                                minHeight: rowHeight(entry.value[i])),
                            child: Padding(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 15, vertical: 12),
                                child: Row(children: [
                                  JobaIcon(icon(entry.value[i])),
                                  const SizedBox(width: 12),
                                  Expanded(
                                      child: ConstrainedBox(
                                          constraints: BoxConstraints(
                                              minHeight:
                                                  rowHeight(entry.value[i]) -
                                                      24),
                                          child: Column(
                                              crossAxisAlignment:
                                                  CrossAxisAlignment.start,
                                              children: [
                                                Text(title(entry.value[i]),
                                                    style: const TextStyle(
                                                        fontSize: 13,
                                                        letterSpacing: -.2,
                                                        height: 20 / 13,
                                                        fontWeight:
                                                            FontWeight.w700)),
                                                if (subtitle(entry.value[i])
                                                    .isNotEmpty)
                                                  Text(subtitle(entry.value[i]),
                                                      style: const TextStyle(
                                                          fontSize: 11,
                                                          height: 17 / 11,
                                                          color: muted))
                                              ]))),
                                  const SizedBox(width: 12),
                                  if (entry.value[i]['read'] != true)
                                    const JobaBadge('Новое')
                                  else
                                    const JobaIcon('right', size: 18)
                                ])))))
              ]
            ]))
      ]
    ]);
  }
}
