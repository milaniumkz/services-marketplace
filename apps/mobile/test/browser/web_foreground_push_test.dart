@TestOn('browser')
library;

import 'dart:js_interop';
import 'dart:js_interop_unsafe';
import 'package:flutter_test/flutter_test.dart';
import 'package:web/web.dart' as web;
import 'package:services_marketplace/core/push_display_web.dart';

@JS('Object.defineProperty')
external JSObject defineProperty(
    JSObject target, JSString key, JSObject descriptor);
@JS('Object.getOwnPropertyDescriptor')
external JSObject? descriptor(JSObject target, JSString key);
@JS('Reflect.deleteProperty')
external bool removeProperty(JSObject target, JSString key);
void main() {
  test(
      'foreground web push uses service worker system display and never asks permission again',
      () async {
    final notification =
            globalContext.getProperty<JSObject>('Notification'.toJS),
        container = web.window.navigator.serviceWorker;
    final originalPermission = descriptor(notification, 'permission'.toJS),
        originalRegistrations = descriptor(container, 'getRegistrations'.toJS);
    addTearDown(() {
      if (originalPermission != null) {
        defineProperty(notification, 'permission'.toJS, originalPermission);
      } else {
        removeProperty(notification, 'permission'.toJS);
      }
      if (originalRegistrations != null) {
        defineProperty(
            container, 'getRegistrations'.toJS, originalRegistrations);
      } else {
        removeProperty(container, 'getRegistrations'.toJS);
      }
    });
    defineProperty(notification, 'permission'.toJS,
        {'value': 'granted', 'configurable': true}.jsify() as JSObject);
    final registration = JSObject();
    registration.setProperty(
        'active'.toJS,
        {'scriptURL': 'https://isolated.example/firebase-messaging-sw.js'}
            .jsify());
    var shown = 0;
    registration.setProperty(
        'showNotification'.toJS,
        ((JSString title, JSObject options) {
          shown++;
          expect(title.toDart, 'JOBA');
          expect(options.getProperty<JSString>('tag'.toJS).toDart,
              'isolated-event');
          expect(
              options
                  .getProperty<JSObject>('data'.toJS)
                  .getProperty<JSBoolean>('joba'.toJS)
                  .toDart,
              isTrue);
          return Future<JSAny?>.value(null).toJS;
        }).toJS);
    defineProperty(
        container,
        'getRegistrations'.toJS,
        {
          'value': (() =>
              Future<JSArray<JSObject>>.value([registration].toJS).toJS).toJS,
          'configurable': true
        }.jsify() as JSObject);
    expect(
        await displayForegroundPush(
            'JOBA', 'Новое сообщение', 'isolated-event'),
        isTrue);
    expect(shown, 1);
    defineProperty(notification, 'permission'.toJS,
        {'value': 'denied', 'configurable': true}.jsify() as JSObject);
    expect(
        await displayForegroundPush(
            'JOBA', 'Новое сообщение', 'isolated-event'),
        isFalse);
    expect(shown, 1);
  });
}
