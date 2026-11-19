@TestOn('browser')
library;

import 'dart:js_interop';
import 'dart:js_interop_unsafe';
import 'package:web/web.dart' as web;
import 'package:flutter_test/flutter_test.dart';
import 'package:services_marketplace/core/device_location.dart';
import 'package:services_marketplace/core/api.dart';

@JS('Object.defineProperty')
external JSObject defineProperty(
    JSObject object, JSString name, JSObject descriptor);
void main() {
  final original = web.window.navigator.geolocation;
  void install(JSFunction callback) {
    final stub = JSObject();
    stub.setProperty('getCurrentPosition'.toJS, callback);
    defineProperty(web.window.navigator, 'geolocation'.toJS,
        {'value': stub, 'configurable': true}.jsify() as JSObject);
  }

  tearDown(() => defineProperty(web.window.navigator, 'geolocation'.toJS,
      {'value': original, 'configurable': true}.jsify() as JSObject));
  test(
      'web uses browser geolocation with precision, timeout and no native channel',
      () async {
    install(((JSFunction success, JSFunction failure, JSObject options) {
      expect(options.getProperty<JSNumber>('timeout'.toJS).toDartInt, 15000);
      success.callAsFunction(
          null,
          {
            'coords': {'latitude': 49.812345, 'longitude': 73.123456}
          }.jsify());
    }).toJS);
    expect(await currentDeviceLocation(),
        {'latitude': 49.812345, 'longitude': 73.123456});
  });
  test('web permission denial returns a recoverable location error', () async {
    install(((JSFunction success, JSFunction failure, JSObject options) {
      failure.callAsFunction(null, {'code': 1}.jsify());
    }).toJS);
    await expectLater(
        currentDeviceLocation(),
        throwsA(
            isA<ApiException>().having((e) => e.code, 'code', 'GPS_DENIED')));
  });
}
