import 'package:flutter/material.dart';
import '../core/api.dart';
import '../core/l10n.dart';
import '../core/theme.dart';
import '../core/widgets.dart';

class ServiceArea extends StatefulWidget {
  final JobaApi api;
  final Future<Json?> Function() locate;
  final VoidCallback onSaved;
  const ServiceArea(
      {required this.api,
      required this.locate,
      required this.onSaved,
      super.key});
  @override
  State<ServiceArea> createState() => _ServiceAreaState();
}

class _ServiceAreaState extends State<ServiceArea> {
  Json? point;
  bool? enabled;
  bool busy = false;
  Object? error;
  Future<void> run(Future<void> Function() action) async {
    if (busy) return;
    setState(() {
      busy = true;
      error = null;
    });
    try {
      await action();
    } catch (e) {
      if (mounted) setState(() => error = e);
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => ApiView(
      load: () => widget.api.request('/me/contractor-profile'),
      builder: (context, data, reload) {
        final p = data['profile'] as Json?;
        if (p == null) return const Notice('Сначала заполните профиль услуг.');
        enabled ??= p['public_location'] != null;
        point ??= p['public_location'];
        return ListView(padding: const EdgeInsets.all(20), children: [
          const UiHeading('Зона на карте', 'Точный адрес не публикуется.'),
          const Notice(
              'Вы можете показать приблизительную зону обслуживания. Новая зона появится после проверки профиля. Отключение скрывает её сразу.'),
          SwitchListTile(
              title: const UiText('Показывать приблизительную зону'),
              value: enabled!,
              onChanged: busy ? null : (v) => setState(() => enabled = v)),
          if (enabled!) ...[
            if (point != null)
              DataCard('${p['city'] ?? ''}',
                  subtitle: '${point!['latitude']}, ${point!['longitude']}'),
            OutlinedButton(
                onPressed: busy
                    ? null
                    : () => run(() async {
                          final location = await widget.locate();
                          if (location == null)
                            throw ApiException(
                                'GPS_DENIED', 'Выберите город вручную');
                          if (mounted)
                            setState(() => point = {
                                  'latitude':
                                      ((location['latitude'] as num) * 100)
                                              .round() /
                                          100,
                                  'longitude':
                                      ((location['longitude'] as num) * 100)
                                              .round() /
                                          100
                                });
                        }),
                child: const UiText('Указать зону по местоположению')),
            const Notice(
                'Если геолокация недоступна, поиск по городу продолжает работать. Публиковать зону необязательно.'),
          ],
          if (error != null) Notice(errorText(context, error!), error: true),
          FilledButton(
              onPressed: busy || enabled! && point == null
                  ? null
                  : () => run(() async {
                        await widget.api.request(
                            '/me/contractor-profile/public-location',
                            method: 'PATCH',
                            body: {
                              'expected_version': p['version'],
                              'enabled': enabled,
                              if (enabled!) 'location': point
                            });
                        if (mounted) widget.onSaved();
                      }),
              child: const UiText('Сохранить выбор'))
        ]);
      });
}
