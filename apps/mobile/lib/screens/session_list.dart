import 'package:flutter/material.dart';
import '../core/api.dart';
import '../core/design_icons.dart';
import '../core/design_widgets.dart';
import '../core/l10n.dart';
import '../core/theme.dart';

class SessionListContent extends StatelessWidget {
  final List<Json> sessions;
  final ValueChanged<String> onRevoke;
  final VoidCallback onRevokeOthers;
  const SessionListContent(
      {required this.sessions,
      required this.onRevoke,
      required this.onRevokeOthers,
      super.key});
  @override
  Widget build(BuildContext context) {
    final ordered = [...sessions]..sort((a, b) =>
        (a['current'] == true ? 0 : 1).compareTo(b['current'] == true ? 0 : 1));
    final others = ordered.where((r) => r['current'] != true).toList();
    return ListView(padding: const EdgeInsets.all(20), children: [
      const UiText('Активные сессии',
          style: TextStyle(
              fontSize: 26,
              height: 33 / 26,
              letterSpacing: -.9,
              fontWeight: FontWeight.w700)),
      const SizedBox(height: 10),
      const UiText('Если устройство вам незнакомо, завершите его сеанс.',
          style: TextStyle(fontSize: 12, height: 1.5, color: muted)),
      const SizedBox(height: 24),
      if (ordered.isEmpty) const UiText('Активных сессий нет'),
      for (final record in ordered) ...[
        Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
                color: Colors.white,
                border: Border.all(color: line),
                borderRadius: BorderRadius.circular(16)),
            child:
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                const JobaIcon('phone', color: primary),
                const SizedBox(width: 10),
                Expanded(
                    child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                      UiText(
                          record['current'] == true
                              ? 'Текущее устройство'
                              : 'Другое устройство',
                          style: const TextStyle(
                              fontSize: 16,
                              height: 23 / 16,
                              letterSpacing: -.2,
                              fontWeight: FontWeight.w700)),
                      const SizedBox(height: 4),
                      const UiText('Сведения об устройстве недоступны',
                          style: TextStyle(
                              fontSize: 10, height: 1.4, color: muted))
                    ]))
              ]),
              const SizedBox(height: 16),
              if (record['current'] == true)
                const JobaBadge('Это устройство',
                    background: Color(0xFFE8F5EF),
                    foreground: Color(0xFF147657)),
              if (record['current'] != true) ...[
                if (DateTime.tryParse('${record['expires_at']}')
                    case final expiry?)
                  Text(
                      '${localize(context, 'Сессия действует до')}: ${MaterialLocalizations.of(context).formatMediumDate(expiry.toLocal())}',
                      style: const TextStyle(
                          fontSize: 12, height: 1.5, color: muted)),
                const SizedBox(height: 16),
                SizedBox(
                    width: double.infinity,
                    child: OutlinedButton(
                        onPressed: () => onRevoke(record['family'] as String),
                        child: const UiText('Завершить сеанс')))
              ]
            ])),
        const SizedBox(height: 12)
      ],
      if (others.isNotEmpty) ...[
        const SizedBox(height: 12),
        FilledButton(
            style: FilledButton.styleFrom(
                backgroundColor: const Color(0xFFFBECEC),
                foregroundColor: const Color(0xFFB73838)),
            onPressed: onRevokeOthers,
            child: const UiText('Выйти на других устройствах')),
        const SizedBox(height: 16),
        const UiText('Текущее устройство останется авторизовано.',
            style: TextStyle(fontSize: 10, height: 1.4, color: muted))
      ]
    ]);
  }
}
