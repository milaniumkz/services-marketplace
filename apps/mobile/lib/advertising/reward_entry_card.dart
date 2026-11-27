import 'package:flutter/material.dart';
import '../core/api.dart';
import '../core/l10n.dart';
import '../core/theme.dart';

/// The same visible entry action is used on web and native access screens.
class RewardEntryCard extends StatelessWidget {
  final List<Json> offers;
  final ValueChanged<String> onSelect;
  const RewardEntryCard({required this.offers, required this.onSelect, super.key});

  @override
  Widget build(BuildContext context) => Card(
        margin: const EdgeInsets.symmetric(vertical: 8),
        elevation: 0,
        color: const Color(0xFFF0F5FF),
        shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(18),
            side: const BorderSide(color: primary, width: 1.5)),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            const Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Icon(Icons.play_circle_fill_rounded, color: primary, size: 28),
              SizedBox(width: 10),
              Expanded(child: UiText('Подписка за рекламу',
                  style: TextStyle(fontWeight: FontWeight.w700, fontSize: 18))),
            ]),
            const SizedBox(height: 8),
            const UiText('Деньги не списываются. Доступ выдаётся после всех завершённых просмотров.'),
            for (final offer in offers) ...[
              const SizedBox(height: 16),
              UiText('${offer['title']}',
                  style: const TextStyle(fontWeight: FontWeight.w700)),
              const SizedBox(height: 4),
              Text(localize(context, 'Просмотрено: {completed} из {required} · 30 дней')
                  .replaceAll('{completed}', '${offer['completed_views'] ?? 0}')
                  .replaceAll('{required}', '${offer['required_views'] ?? 0}')),
              const SizedBox(height: 10),
              FilledButton.icon(
                style: FilledButton.styleFrom(
                    backgroundColor: primary, foregroundColor: Colors.white,
                    minimumSize: const Size(double.infinity, 52),
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14)),
                onPressed: () => onSelect(offer['target'] as String),
                icon: Icon(offer['ready'] == true ? Icons.check_circle_outline : Icons.play_arrow_rounded),
                label: UiText(offer['ready'] == true ? 'Получить доступ'
                    : (offer['completed_views'] as num? ?? 0) > 0
                        ? 'Продолжить просмотр' : 'Смотреть рекламу',
                    textAlign: TextAlign.center),
              ),
            ],
          ]),
        ),
      );
}
