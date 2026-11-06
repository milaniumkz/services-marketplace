@TestOn('browser')
library;

import 'dart:async';
import 'dart:js_interop';
import 'package:flutter_test/flutter_test.dart';
import 'package:web/web.dart' as web;
import 'package:services_marketplace/core/session_refresh_lock.dart';

void main() {
  test('browser holds one native refresh lock and serializes competing tabs',
      () async {
    final entered = Completer<void>(), release = Completer<void>();
    final order = <int>[];
    final key = 'joba.refresh.browser-test';
    final first = withSessionRefreshLock(key, () async {
      order.add(1);
      entered.complete();
      await release.future;
      order.add(2);
    });
    await entered.future;
    final state = await web.window.navigator.locks.query().toDart;
    expect(state.held.toDart.any((lock) => lock.name == key), isTrue);
    final second = withSessionRefreshLock(key, () async {
      order.add(3);
    });
    await Future<void>.delayed(const Duration(milliseconds: 30));
    expect(order, [1]);
    release.complete();
    await Future.wait([first, second]);
    expect(order, [1, 2, 3]);
  });
}
