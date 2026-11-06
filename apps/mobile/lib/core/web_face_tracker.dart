import 'dart:js_interop';
import 'dart:js_interop_unsafe';
import 'package:web/web.dart' as web;
import 'api.dart';

class WebFaceTracker {
  final JSObject _tracker;
  WebFaceTracker._(this._tracker);
  static Future<WebFaceTracker> create() async {
    final factory =
        web.window.getProperty<JSFunction?>('jobaCreateFaceTracker'.toJS);
    if (factory == null)
      throw ApiException('FACE_TRACKER_UNAVAILABLE',
          'Не удалось загрузить автоматическую съёмку. Обновите страницу и повторите попытку.');
    var abandoned = false;
    final pending = (factory.callAsFunction() as JSPromise<JSObject>).toDart;
    pending.then<void>((object) {
      if (abandoned) WebFaceTracker._(object).close();
    }, onError: (Object _, StackTrace __) {});
    final object =
        await pending.timeout(const Duration(seconds: 35), onTimeout: () {
      abandoned = true;
      throw ApiException('FACE_TRACKER_TIMEOUT',
          'Не удалось загрузить определение движений. Проверьте соединение и повторите попытку.');
    });
    return WebFaceTracker._(object);
  }

  Map<String, dynamic> detect(web.HTMLVideoElement video, double time) =>
      Map<String, dynamic>.from((_tracker
          .callMethod<JSObject>('detect'.toJS, video, time.toJS)
          .dartify() as Map));
  void close() => _tracker.callMethod<JSAny?>('close'.toJS);
}
