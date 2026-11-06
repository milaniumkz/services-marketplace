import 'dart:js_interop';
import 'dart:js_interop_unsafe';
import 'package:web/web.dart' as web;
import 'session_refresh_lock_stub.dart' as fallback;

Future<void> withSessionRefreshLock(
    String key, Future<void> Function() action) async {
  final manager = web.window.navigator.getProperty<JSObject?>('locks'.toJS);
  if (manager == null) {
    await fallback.withSessionRefreshLock(key, action);
    return;
  }
  final callback = ((JSAny? _) => action().then<JSAny?>((_) => null).toJS).toJS;
  await web.window.navigator.locks.request(key, callback).toDart;
}
