import 'package:flutter/material.dart';
import '../core/api.dart';
import '../core/design_icons.dart';
import '../core/l10n.dart';
import '../core/theme.dart';
import '../core/widgets.dart';

class AccountRestrictions extends StatelessWidget {
  final JobaApi api;
  final VoidCallback onSupport, onPrivacy, onOrders;
  final ValueChanged<String> onCase, onAppeal;
  final String Function(dynamic) dateLabel;
  const AccountRestrictions(
      {required this.api,
      required this.onSupport,
      required this.onPrivacy,
      required this.onOrders,
      required this.onCase,
      required this.onAppeal,
      required this.dateLabel,
      super.key});
  Widget line(String title, String value) => Padding(
      padding: const EdgeInsets.symmetric(vertical: 14),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Expanded(child: UiText(title, style: const TextStyle(fontSize: 12))),
        const SizedBox(width: 12),
        Expanded(
            child: Text(value,
                textAlign: TextAlign.right,
                style:
                    const TextStyle(fontSize: 12, fontWeight: FontWeight.w700)))
      ]));
  @override
  Widget build(BuildContext context) => ApiView(
      load: () => api.request('/me/restrictions'),
      builder: (context, data, reload) {
        final entries = items(data),
            restricted = data['meta']?['restricted'] == true;
        final appealable =
            entries.where((r) => r['can_appeal'] == true).toList();
        return Column(children: [
          Expanded(
              child: ListView(padding: const EdgeInsets.all(20), children: [
            Padding(
                padding: const EdgeInsets.symmetric(vertical: 22),
                child: Column(children: [
                  Container(
                      width: 94,
                      height: 94,
                      decoration: BoxDecoration(
                          color: restricted
                              ? const Color(0xFFFFF4D4)
                              : const Color(0xFFE8F6EF),
                          borderRadius: BorderRadius.circular(30)),
                      child: Center(
                          child: JobaIcon(restricted ? 'lock' : 'check',
                              size: 42))),
                  const SizedBox(height: 23),
                  UiText(restricted ? 'Нужна проверка' : 'Ограничений нет',
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                          fontSize: 25,
                          height: 1.28,
                          fontWeight: FontWeight.w700,
                          letterSpacing: -.9)),
                  const SizedBox(height: 12),
                  UiText(
                      restricted
                          ? 'Новые публикации и отклики временно недоступны.'
                          : 'Новые действия доступны по условиям вашего аккаунта.',
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                          fontSize: 13, height: 1.55, color: Color(0xFF627187)))
                ])),
            for (final r in entries)
              Container(
                  margin: const EdgeInsets.only(bottom: 16),
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                      color: Colors.white,
                      border: Border.all(color: lineColor),
                      borderRadius: BorderRadius.circular(16)),
                  child: Column(children: [
                    line(
                        'Причина',
                        r['reason'] == 'Проверка содержания'
                            ? localize(context, 'Проверка содержания')
                            : '${r['reason']}'),
                    const Divider(height: 1),
                    line(
                        'Срок до',
                        r['ends_at'] == null
                            ? localize(context, 'Уточните в поддержке')
                            : dateLabel(r['ends_at'])),
                    if (r['case_id'] != null) ...[
                      const Divider(height: 1),
                      TextButton(
                          style: TextButton.styleFrom(
                              foregroundColor: navy,
                              textStyle: const TextStyle(
                                  fontFamily: 'Noto', fontSize: 12)),
                          onPressed: () => onCase(r['case_id']),
                          child: Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                const UiText('Дело'),
                                Text(
                                    '№ ${r['case_id'].toString().split('-').first.toUpperCase()}')
                              ]))
                    ],
                    const SizedBox(height: 12),
                    const UiText(
                        'Временная мера не означает доказанное нарушение.',
                        style:
                            TextStyle(fontSize: 10, color: Color(0xFF627187)))
                  ])),
            if (restricted && entries.isEmpty)
              const Notice(
                  'Подробности ограничения можно уточнить в поддержке.',
                  icon: 'info'),
            const UiText(
                'Поддержка, приватность и разрешённое завершение действующих заказов остаются доступны.',
                style: TextStyle(
                    fontSize: 12, color: Color(0xFF627187), height: 1.55)),
            const SizedBox(height: 20),
            Row(children: [
              Expanded(
                  child: OutlinedButton(
                      onPressed: onSupport, child: const UiText('Поддержка'))),
              const SizedBox(width: 12),
              Expanded(
                  child: OutlinedButton(
                      onPressed: onPrivacy, child: const UiText('Приватность')))
            ]),
            TextButton(
                onPressed: onOrders, child: const UiText('Действующие заказы')),
            TextButton(
                onPressed: reload, child: const UiText('Обновить статус')),
          ])),
          if (appealable.isNotEmpty)
            SafeArea(
                top: false,
                child: Container(
                    color: Colors.white,
                    padding: const EdgeInsets.fromLTRB(20, 12, 20, 12),
                    width: double.infinity,
                    child: FilledButton(
                        onPressed: () => onAppeal(appealable.first['case_id']),
                        child: const UiText('Подать апелляцию'))))
        ]);
      });
  static const lineColor = Color(0xFFE5EAF2);
}
