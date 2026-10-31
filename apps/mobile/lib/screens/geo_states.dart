import 'package:flutter/material.dart';
import '../core/api.dart';
import '../core/design_states.dart';
import '../core/design_widgets.dart';
import '../core/l10n.dart';
import '../core/theme.dart';
import '../core/osm_map.dart';
import 'package:flutter_map/flutter_map.dart';
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
    return ApiView(load: () async {
      final data = await api.request('/contractors/map', query: filters);
      try {
        final cities = items(await api.request('/geo/cities'));
        final matches = cities
            .where((c) => c['name'] == filters['city'] && mapPoint(c) != null);
        final valid = cities.where((c) => mapPoint(c) != null);
        data['fallback_center'] = matches.isNotEmpty
            ? matches.first
            : valid.isNotEmpty
                ? valid.first
                : null;
      } catch (_) {}
      return data;
    }, builder: (context, r, reload) {
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
        Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Notice(rows.isEmpty
                ? 'Нет объявлений с опубликованной зоной обслуживания.'
                : 'Показаны приблизительные зоны обслуживания. Точные адреса скрыты.')),
        Expanded(
            child: Stack(children: [
          OsmMap(initialCenter: mapPoint(r['fallback_center']), markers: [
            for (final row in rows)
              if (mapPoint(row['public_location']) != null)
                Marker(
                    point: mapPoint(row['public_location'])!,
                    width: 48,
                    height: 48,
                    child: IconButton(
                        tooltip: '${row['title']}',
                        onPressed: () => onGo('contractor', row['id']),
                        icon: const Icon(Icons.location_on,
                            color: primary, size: 36)))
          ]),
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
                          child: DataCard('${p['display_name'] ?? p['title']}',
                              subtitle: '${p['title']}',
                              onTap: () => onGo('contractor', p['id'])))
                  ]))
      ]);
    });
  }
}
