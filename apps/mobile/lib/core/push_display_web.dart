import 'dart:js_interop';
import 'package:web/web.dart' as web;

Future<bool> displayForegroundPush(
    String title, String body, String eventId) async {
  if (web.Notification.permission != 'granted') return false;
  try {
    final registrations =
        (await web.window.navigator.serviceWorker.getRegistrations().toDart)
            .toDart;
    for (final registration in registrations) {
      final worker = registration.active;
      if (worker == null ||
          !Uri.parse(worker.scriptURL)
              .path
              .endsWith('/firebase-messaging-sw.js')) continue;
      await registration
          .showNotification(
              title,
              web.NotificationOptions(
                  body: body,
                  tag: eventId,
                  icon: '/icons/joba-192.png',
                  data: {'joba': true}.jsify()))
          .toDart;
      return true;
    }
  } catch (_) {
    /* Keep in-app delivery available if the browser rejects system display. */
  }
  return false;
}
