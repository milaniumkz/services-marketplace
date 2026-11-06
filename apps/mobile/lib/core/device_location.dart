import 'api.dart';
import 'device_location_native.dart'
    if (dart.library.js_interop) 'device_location_web.dart' as platform;

Future<Json> currentDeviceLocation() async {
  final value = await platform.currentLocation();
  final lat = value?['latitude'], lon = value?['longitude'];
  if (lat is! num ||
      lon is! num ||
      !lat.isFinite ||
      !lon.isFinite ||
      lat.abs() > 90 ||
      lon.abs() > 180) {
    throw ApiException('GPS_DENIED',
        'Не удалось определить местоположение. Выберите точку вручную.');
  }
  return {'latitude': lat.toDouble(), 'longitude': lon.toDouble()};
}
