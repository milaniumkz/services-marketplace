import '../core/theme.dart';
import '../core/l10n.dart';
import 'package:flutter/material.dart';
import '../core/api.dart';
import '../core/device_location.dart';
import '../core/design_widgets.dart';
import '../core/widgets.dart';

class NearbyContractors extends StatefulWidget {
  final JobaApi api;
  final Future<Json> Function() locate;
  final Widget Function(Json) itemBuilder;
  final ValueChanged<Json>? onLocation;
  final VoidCallback onAccess, onVerification;
  const NearbyContractors(
      {required this.api,
      required this.itemBuilder,
      required this.onAccess,
      required this.onVerification,
      this.locate = currentDeviceLocation,
      this.onLocation,
      super.key});
  @override
  State<NearbyContractors> createState() => _NearbyContractorsState();
}

class _NearbyContractorsState extends State<NearbyContractors> {
  Future<Json> load() async {
    Json point;
    try {
      point = await widget.locate();
    } catch (_) {
      return {'location_required': true};
    }
    if (!mounted) return {'items': []};
    final lat = point['latitude'], lon = point['longitude'];
    if (lat is! num ||
        lon is! num ||
        !lat.isFinite ||
        !lon.isFinite ||
        lat.abs() > 90 ||
        lon.abs() > 180) return {'location_required': true};
    widget.onLocation?.call(point);
    try {
      return Map<String, dynamic>.from(await widget.api.request('/contractors',
          query: {
            'limit': 3,
            'near_lat': lat,
            'near_lon': lon,
            'radius_km': 20
          }));
    } on ApiException catch (e) {
      if (e.code == 'ENTITLEMENT_REQUIRED') return {'access_required': true};
      if (e.code == 'VERIFICATION_REQUIRED')
        return {'verification_required': true};
      rethrow;
    }
  }

  @override
  Widget build(BuildContext context) => ApiView(
      load: load,
      builder: (context, data, retry) {
        if (data['location_required'] == true)
          return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Notice(
                    'Чтобы показать исполнителей в радиусе 20 км, разрешите доступ к вашему местоположению. Предложения из других городов здесь не показываются.',
                    icon: 'pin'),
                OutlinedButton(
                    onPressed: retry,
                    child: const UiText('Определить местоположение'))
              ]);
        if (data['access_required'] == true)
          return JobaMenu([
            JobaMenuEntry('Мой доступ', 'card', widget.onAccess,
                subtitle: 'Выбор доступа')
          ]);
        if (data['verification_required'] == true)
          return JobaMenu([
            JobaMenuEntry(
                'Подтвердить личность', 'shield', widget.onVerification,
                subtitle: 'Удостоверение с двух сторон и селфи')
          ]);
        final rows = items(data);
        return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Padding(
              padding: EdgeInsets.only(bottom: 12),
              child: UiText('В радиусе 20 км от вас')),
          if (rows.isEmpty)
            const Notice('В радиусе 20 км пока нет исполнителей.',
                icon: 'search')
          else
            ...rows.map(widget.itemBuilder)
        ]);
      });
}
