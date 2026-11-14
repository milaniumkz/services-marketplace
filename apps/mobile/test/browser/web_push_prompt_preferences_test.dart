@TestOn('browser')
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:web/web.dart' as web;
import 'package:services_marketplace/core/push_prompt_preferences.dart';

void main() {
  test(
      'web notification offer deferral persists in browser storage without account data',
      () {
    const key = 'joba.pushPrompt.deferredUntil';
    final previous = web.window.localStorage.getItem(key);
    addTearDown(() {
      if (previous == null) {
        web.window.localStorage.removeItem(key);
      } else {
        web.window.localStorage.setItem(key, previous);
      }
    });
    web.window.localStorage.removeItem(key);
    expect(PushPromptPreferences().read(), isNull);
    final until = DateTime.utc(2026, 11, 4);
    PushPromptPreferences().write(until);
    expect(PushPromptPreferences().read(), until);
    expect(web.window.localStorage.getItem(key), until.toIso8601String());
  });
}
