import 'dart:async';
import 'dart:js_interop';
import 'package:web/web.dart' as web;
import 'api.dart';

Future<Map<String, dynamic>?> currentLocation() {
  final result = Completer<Map<String, dynamic>?>();
  web.window.navigator.geolocation.getCurrentPosition(
    ((web.GeolocationPosition position) {
      if (!result.isCompleted)
        result.complete({
          'latitude': position.coords.latitude,
          'longitude': position.coords.longitude
        });
    }).toJS,
    ((web.GeolocationPositionError error) {
      if (!result.isCompleted)
        result.completeError(ApiException(
            'GPS_DENIED',
            error.code == 1
                ? 'Разрешите доступ к местоположению в настройках браузера или выберите точку вручную.'
                : 'Не удалось определить местоположение. Выберите точку вручную.'));
    }).toJS,
    web.PositionOptions(
        enableHighAccuracy: true, timeout: 15000, maximumAge: 30000),
  );
  return result.future.timeout(const Duration(seconds: 20));
}
