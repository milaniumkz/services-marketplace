import 'package:flutter/material.dart';
import '../core/api.dart';
import '../core/design_states.dart';
import '../core/design_widgets.dart';
import '../core/l10n.dart';
import '../core/theme.dart';
import '../core/widgets.dart';

class GeoStates extends StatelessWidget {
  final JobaApi api;
  final String mode, country;
  final Json filters;
  final void Function(String route, String? id) onGo;
  const GeoStates(
      {required this.api,
      required this.mode,
      required this.country,
      required this.onGo,
      this.filters = const {},
      super.key});
  @override
  Widget build(BuildContext context) {
    if (mode == 'gps-denied')
      return ListView(padding: const EdgeInsets.all(20), children: [
        JobaStatePanel(
            icon: 'pin',
            title: 'Выберите город\nвручную',
            message:
                'Геолокация необязательна. Укажите город, чтобы видеть подходящих специалистов.',
            primaryLabel: 'Выбрать город',
            onPrimary: () => onGo('location', null))
      ]);
    if (mode == 'country-unavailable')
      return ApiView(
          load: () => api.request('/public/config', authenticated: false),
          builder: (context, r, reload) {
            final entries =
                (r['countries'] as List).where((c) => c['code'] == country);
            final closed = entries.isEmpty ||
                entries.first['stop_new_business'] == true ||
                entries.first['registration_enabled'] == false;
            return ListView(padding: const EdgeInsets.all(20), children: [
              JobaStatePanel(
                  icon: 'globe',
                  title: closed
                      ? 'Новые заказы\nпока недоступны'
                      : 'Регион доступен',
                  message: closed
                      ? 'Для выбранной страны новые коммерческие действия временно отключены. Поддержка и управление данными доступны.'
                      : 'Доступность новых действий определяется текущими правами и состоянием аккаунта.'),
              JobaMenu([
                JobaMenuEntry('Поддержка', 'chat', () => onGo('support', null),
                    subtitle: 'Получить помощь'),
                JobaMenuEntry('Мои действующие заказы', 'briefcase',
                    () => onGo('orders', null)),
                JobaMenuEntry('Восстановление покупки', 'refresh',
                    () => onGo('restore', null)),
                JobaMenuEntry(
                    'Приватность', 'lock', () => onGo('privacy', null))
              ])
            ]);
          });
    return ApiView(
        load: () => api.request('/contractors/map', query: filters),
        builder: (context, r, reload) {
          final rows = items(r);
          return Column(children: [
            Padding(
                padding: const EdgeInsets.all(20),
                child: Row(children: [
                  Expanded(
                      child: Text(
                          '${filters['city'] ?? localize(context, 'Все города')}')),
                  TextButton(
                      onPressed: () => onGo('catalog', null),
                      child: const UiText('Списком'))
                ])),
            Expanded(
                child: Stack(children: [
              InteractiveViewer(
                  minScale: .5,
                  maxScale: 8,
                  child: LayoutBuilder(builder: (context, c) {
                    final locations = rows
                        .where((r) => r['public_location'] != null)
                        .toList();
                    final xs = locations
                            .map((r) =>
                                (r['public_location']['longitude'] as num)
                                    .toDouble())
                            .toList(),
                        ys = locations
                            .map((r) =>
                                (r['public_location']['latitude'] as num)
                                    .toDouble())
                            .toList();
                    final centerX = xs.isEmpty
                            ? 0
                            : xs.reduce((a, b) => a + b) / xs.length,
                        centerY = ys.isEmpty
                            ? 0
                            : ys.reduce((a, b) => a + b) / ys.length;
                    double spread = .05;
                    for (final x in xs)
                      if ((x - centerX).abs() > spread)
                        spread = (x - centerX).abs();
                    for (final y in ys)
                      if ((y - centerY).abs() > spread)
                        spread = (y - centerY).abs();
                    return Container(
                        color: const Color(0xFFEDF2F7),
                        child: Stack(children: [
                          const Positioned.fill(
                              child: CustomPaint(painter: _GeoGrid())),
                          for (final e in locations)
                            Positioned(
                                left: c.maxWidth *
                                        (.5 +
                                            ((e['public_location']['longitude']
                                                        as num) -
                                                    centerX) /
                                                (spread * 2.5)) -
                                    22,
                                top: c.maxHeight *
                                        (.5 -
                                            ((e['public_location']['latitude'] as num) -
                                                    centerY) /
                                                (spread * 2.5)) -
                                    22,
                                child: IconButton(
                                    tooltip: '${e['title']}',
                                    onPressed: () =>
                                        onGo('contractor', e['id']),
                                    icon: const Icon(Icons.location_on,
                                        color: primary, size: 36)))
                        ]));
                  })),
              Positioned(
                  left: 20,
                  right: 20,
                  top: 12,
                  child: Notice(rows.isEmpty
                      ? 'Нет объявлений с опубликованной зоной обслуживания.'
                      : 'Показаны приблизительные зоны обслуживания. Точные адреса скрыты.')),
              Positioned(
                  left: 20,
                  right: 20,
                  bottom: 12,
                  child: Notice(
                      'Географическая подложка подключается отдельно. Точки обозначают опубликованные зоны обслуживания.'))
            ])),
            if (rows.isNotEmpty)
              SizedBox(
                  height: 160,
                  child: ListView(
                      scrollDirection: Axis.horizontal,
                      padding: const EdgeInsets.all(12),
                      children: [
                        for (final p in rows)
                          SizedBox(
                              width: 280,
                              child: DataCard(
                                  '${p['display_name'] ?? p['title']}',
                                  subtitle: '${p['title']}',
                                  onTap: () => onGo('contractor', p['id'])))
                      ]))
          ]);
        });
  }
}

class _GeoGrid extends CustomPainter {
  const _GeoGrid();
  @override
  void paint(Canvas canvas, Size size) {
    final p = Paint()
      ..color = const Color(0xFFDDE6EF)
      ..strokeWidth = 1;
    for (double x = 0; x < size.width; x += 50)
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), p);
    for (double y = 0; y < size.height; y += 50)
      canvas.drawLine(Offset(0, y), Offset(size.width, y), p);
  }

  @override
  bool shouldRepaint(_GeoGrid oldDelegate) => false;
}
