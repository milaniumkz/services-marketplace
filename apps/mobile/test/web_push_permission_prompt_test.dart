import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:services_marketplace/core/push_permission_controller.dart';
import 'package:services_marketplace/core/push_prompt_preferences.dart';
import 'package:services_marketplace/screens/web_push_permission_prompt.dart';

class Permission extends PushPermissionController {
  bool needed;
  int calls = 0;
  Future<void> Function()? action;
  Permission(this.needed);
  @override
  bool get needsPermission => needed;
  void update(bool value) {
    needed = value;
    notifyListeners();
  }

  @override
  Future<void> enable() async {
    calls++;
    if (action != null) await action!();
  }
}

void main() {
  final now = DateTime.utc(2026, 10, 28);
  Future<void> mount(WidgetTester t, Permission controller,
      {PushPromptPreferences? preferences, double scale = 1}) async {
    await t.pumpWidget(MaterialApp(
        home: MediaQuery(
            data: MediaQueryData(textScaler: TextScaler.linear(scale)),
            child: Scaffold(
                body: Stack(fit: StackFit.expand, children: [
              const Center(child: Text('Основное приложение')),
              WebPushPermissionPrompt(
                  controller: controller,
                  preferences: preferences ??
                      PushPromptPreferences(read: () => null, write: (_) {}),
                  now: () => now),
            ])))));
    await t.pump();
  }

  testWidgets(
      'offers automatically when available and requests only after a tap',
      (t) async {
    final permission = Permission(false);
    await mount(t, permission);
    expect(find.text('Разрешить уведомления'), findsNothing);
    permission.update(true);
    await t.pump();
    expect(find.text('Разрешить уведомления'), findsOneWidget);
    expect(permission.calls, 0);
    permission.action = () async => permission.update(false);
    await t.tap(find.text('Разрешить уведомления'));
    expect(permission.calls, 1);
    await t.pumpAndSettle();
    expect(find.text('Включить уведомления?'), findsNothing);
  });
  testWidgets('later survives a new page without requesting browser permission',
      (t) async {
    DateTime? deferred;
    final preferences = PushPromptPreferences(
        read: () => deferred, write: (value) => deferred = value);
    final permission = Permission(true);
    await mount(t, permission, preferences: preferences);
    await t.tap(find.text('Позже'));
    await t.pump();
    expect(deferred, now.add(const Duration(days: 7)));
    expect(permission.calls, 0);
    await t.pumpWidget(const SizedBox());
    await mount(t, Permission(true), preferences: preferences);
    expect(find.text('Разрешить уведомления'), findsNothing);
  });
  testWidgets('expired deferral offers again but a decided permission does not',
      (t) async {
    final preferences = PushPromptPreferences(
        read: () => now.subtract(const Duration(seconds: 1)), write: (_) {});
    final permission = Permission(true);
    await mount(t, permission, preferences: preferences);
    expect(find.text('Разрешить уведомления'), findsOneWidget);
    permission.update(false);
    await t.pump();
    expect(find.text('Разрешить уведомления'), findsNothing);
  });
  testWidgets('registration failure permits retry after browser grant',
      (t) async {
    final permission = Permission(true);
    permission.action = () async {
      permission.update(false);
      throw StateError('isolated registration failure');
    };
    await mount(t, permission);
    await t.tap(find.text('Разрешить уведомления'));
    await t.pumpAndSettle();
    expect(find.text('Повторить'), findsOneWidget);
    expect(
        find.textContaining('Не удалось включить уведомления'), findsOneWidget);
    permission.action = () async {};
    await t.tap(find.text('Повторить'));
    await t.pumpAndSettle();
    expect(permission.calls, 2);
    expect(find.text('Повторить'), findsNothing);
  });
  testWidgets('pending registration disables repeated taps', (t) async {
    final permission = Permission(true);
    final done = Completer<void>();
    permission.action = () => done.future;
    await mount(t, permission);
    await t.tap(find.text('Разрешить уведомления'));
    await t.pump();
    expect(permission.calls, 1);
    expect(t.widget<FilledButton>(find.byType(FilledButton)).onPressed, isNull);
    expect(t.widget<TextButton>(find.byType(TextButton)).onPressed, isNull);
    permission.update(false);
    done.complete();
    await t.pumpAndSettle();
    expect(find.text('Включить уведомления?'), findsNothing);
  });
  testWidgets('narrow enlarged text remains usable', (t) async {
    t.view.physicalSize = const Size(320, 640);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.resetPhysicalSize);
    addTearDown(t.view.resetDevicePixelRatio);
    await mount(t, Permission(true), scale: 2);
    expect(t.takeException(), isNull);
    await t.ensureVisible(find.text('Позже'));
    await t.tap(find.text('Позже'));
    await t.pump();
    expect(t.takeException(), isNull);
    expect(find.text('Включить уведомления?'), findsNothing);
  });
}
