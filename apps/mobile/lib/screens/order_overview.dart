import 'package:flutter/material.dart';
import '../core/api.dart';
import '../core/design_icons.dart';
import '../core/design_widgets.dart';
import '../core/l10n.dart';
import '../core/theme.dart';
import '../core/widgets.dart';

/// The information shared by S10 and the participant's order detail.
class OrderOverview extends StatelessWidget {
  final JobaApi api;
  final Json order;
  final String stateLabel, priceLabel, timeLabel;
  final VoidCallback onReport;
  const OrderOverview(
      {required this.api,
      required this.order,
      required this.stateLabel,
      required this.priceLabel,
      required this.timeLabel,
      required this.onReport,
      super.key});
  Widget detail(String icon, String title, String subtitle) => Row(children: [
        JobaIcon(icon, color: primary),
        const SizedBox(width: 10),
        Expanded(
            child:
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(title,
              style:
                  const TextStyle(fontSize: 13, fontWeight: FontWeight.w700)),
          const SizedBox(height: 4),
          UiText(subtitle,
              style: const TextStyle(fontSize: 10, color: Color(0xFF627187))),
        ])),
      ]);
  @override
  Widget build(BuildContext context) {
    final customer = order['customer'] as Json?;
    final id = '${order['id']}';
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Row(children: [
        JobaBadge(stateLabel),
        const Spacer(),
        Text('№ ${id.substring(0, id.length.clamp(0, 8))}',
            style: const TextStyle(fontSize: 10, color: Color(0xFF627187)))
      ]),
      const SizedBox(height: 16),
      Text('${order['title']}',
          style: const TextStyle(
              fontSize: 28,
              height: 1.25,
              letterSpacing: -.9,
              fontWeight: FontWeight.w700)),
      const SizedBox(height: 20),
      Row(children: [
        Expanded(
            child:
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const UiText('Бюджет заказчика',
              style: TextStyle(fontSize: 12, color: Color(0xFF627187))),
          const SizedBox(height: 4),
          Text(priceLabel,
              style:
                  const TextStyle(fontSize: 28, fontWeight: FontWeight.w700)),
        ])),
        IconButton(
            tooltip: localize(context, 'Пожаловаться'),
            style: IconButton.styleFrom(
                backgroundColor: canvas,
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14))),
            onPressed: onReport,
            icon: const JobaIcon('flag'))
      ]),
      const SizedBox(height: 20),
      Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
              color: Colors.white,
              border: Border.all(color: line),
              borderRadius: BorderRadius.circular(16)),
          child: Column(children: [
            detail(
                'pin',
                '${order['city'] ?? ''}',
                order['work_mode'] == 'remote'
                    ? 'Удалённая работа'
                    : 'Примерное расположение'),
            const Divider(height: 28, thickness: 1, color: line),
            detail('clock', timeLabel,
                order['time_window']?['time_zone'] ?? 'Время согласуем'),
          ])),
      const SizedBox(height: 20),
      const UiText('Что нужно сделать',
          style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
      const SizedBox(height: 8),
      Text('${order['description'] ?? ''}',
          style: const TextStyle(
              fontSize: 12, height: 1.55, color: Color(0xFF627187))),
      for (final id in order['upload_ids'] as List? ?? [])
        Padding(
            padding: const EdgeInsets.only(top: 16),
            child: ClipRRect(
                borderRadius: BorderRadius.circular(16),
                child: SizedBox(
                    height: 140,
                    width: double.infinity,
                    child: PrivatePhoto(api: api, id: id)))),
      if (customer != null) ...[
        const SizedBox(height: 20),
        Row(children: [
          JobaAvatar(
              api: api,
              name: customer['display_name'] ?? '',
              id: customer['avatar_id'],
              size: 42,
              backgroundColor: const Color(0xFFE6E1F0),
              foregroundColor: const Color(0xFF6F608A)),
          const SizedBox(width: 10),
          Expanded(
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                Text(customer['display_name'] ?? '',
                    style: const TextStyle(
                        fontSize: 13, fontWeight: FontWeight.w700)),
                const UiText('Заказчик',
                    style: TextStyle(fontSize: 10, color: Color(0xFF627187))),
              ])),
        ]),
      ],
      const SizedBox(height: 16),
      const UiText(
          'Стоимость услуги оплачивается по договорённости сторон, вне JOBA.',
          style: TextStyle(fontSize: 10, color: Color(0xFF627187))),
      const SizedBox(height: 16),
    ]);
  }
}
