import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:webview_flutter_platform_interface/webview_flutter_platform_interface.dart';
import 'package:services_marketplace/core/face_camera_native.dart';
import 'bank_form_test.dart' show TestController, TestPlatform;

class FaceController extends TestController {
  FaceController(super.params);
  late JavaScriptChannelParams bridge;
  final scripts = <String>[];
  @override
  Future<void> addJavaScriptChannel(JavaScriptChannelParams params) async {
    bridge = params;
  }

  @override
  Future<void> setOnPlatformPermissionRequest(
      void Function(PlatformWebViewPermissionRequest) callback) async {}
  @override
  Future<void> runJavaScript(String source) async {
    scripts.add(source);
  }

  void send(Map<String, dynamic> data) =>
      bridge.onMessageReceived(JavaScriptMessage(message: jsonEncode(data)));
}

class FacePlatform extends TestPlatform {
  final controllers = <FaceController>[];
  @override
  PlatformWebViewController createPlatformWebViewController(
      PlatformWebViewControllerCreationParams params) {
    final c = FaceController(params);
    controllers.add(c);
    return controller = c;
  }
}

void main() {
  testWidgets(
      'continuous native view keeps one camera, rejects stale frames after retry, and closes automatically after five stages',
      (t) async {
    final platform = FacePlatform();
    WebViewPlatform.instance = platform;
    final voice = <String>[];
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(const MethodChannel('joba.face_camera'),
            (call) async {
      if (call.method == 'speak') voice.add(call.arguments['text']);
      return true;
    });
    await t.pumpWidget(MaterialApp(
        home: Builder(
            builder: (context) => TextButton(
                onPressed: () => Navigator.push(
                    context,
                    MaterialPageRoute(
                        builder: (_) => NativeFaceCamera(
                            origin: Uri.parse('https://joba.com.kz')))),
                child: const Text('start')))));
    await t.tap(find.text('start'));
    await t.pump();
    await t.pump(const Duration(milliseconds: 500));
    await t.pump();
    expect(platform.controllers.length, 1);
    final first = platform.controllers.single;
    expect(first.loaded!.uri.path, '/face-camera-native.html');
    first.send({'type': 'ready'});
    await t.pump();
    expect(voice, isNotEmpty);
    expect(find.text('Снять кадр'), findsNothing);
    first.send({'type': 'error', 'message': 'test error'});
    await t.pump();
    await t.tap(find.text('Повторить съёмку'));
    await t.pump();
    await t.pump();
    await t.pump();
    expect(first.scripts.any((s) => s.contains('stop')), true);
    first.send({'type': 'frame', 'step': 0, 'photo': '/9j/', 'time': 1000});
    await t.pump();
    expect(find.text('Шаг 1 из 5'), findsOneWidget);
    final current = platform.controllers.last;
    current.send({'type': 'ready'});
    await t.pump();
    var time = 1000;
    Map<String, dynamic> metrics(
            {double yaw = 0, double blink = 0, double smile = 0}) =>
        {
          'faces': 1,
          'yaw': yaw,
          'centerX': .5,
          'centerY': .5,
          'width': .5,
          'height': .6,
          'blinkLeft': blink,
          'blinkRight': blink,
          'smile': smile
        };
    void observe(Map<String, dynamic> m, int stamp) =>
        current.send({'type': 'metrics', 'metrics': m, 'time': stamp});
    for (var step = 0; step < 5; step++) {
      final m = metrics(
          yaw: step == 1
              ? 0.2
              : step == 2
                  ? -0.2
                  : 0,
          smile: step == 4 ? 0.8 : 0);
      if (step == 3) {
        observe(metrics(), time);
        observe(metrics(blink: .9), time + 100);
        observe(metrics(), time + 200);
        observe(metrics(), time + 300);
      } else {
        observe(m, time);
        observe(m, time + 160);
        observe(m, time + 350);
      }
      expect(current.scripts.last, contains('capture($step)'));
      current.send(
          {'type': 'frame', 'step': step, 'photo': '/9j/', 'time': time + 400});
      await t.pump();
      time += 1500;
    }
    await t.pumpAndSettle();
    expect(find.text('start'), findsOneWidget);
    expect(current.scripts.any((s) => s.contains('stop')), true);
    expect(voice.any((s) => s.contains('налево')), true);
    expect(voice.any((s) => s.contains('Улыбнитесь')), true);
  });
  testWidgets(
      'small screen keeps the camera layout usable and cancel reachable without overflow',
      (t) async {
    final platform = FacePlatform();
    WebViewPlatform.instance = platform;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
            const MethodChannel('joba.face_camera'), (call) async => true);
    t.view.physicalSize = const Size(320, 360);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.resetPhysicalSize);
    addTearDown(t.view.resetDevicePixelRatio);
    await t.pumpWidget(MaterialApp(
        home: NativeFaceCamera(origin: Uri.parse('https://joba.com.kz'))));
    await t.pump();
    await t.pump();
    await t.pump();
    platform.controllers.last.send({'type': 'ready'});
    await t.pump();
    await t.scrollUntilVisible(find.text('Отмена'), 150);
    expect(t.takeException(), isNull);
    expect(find.text('Отмена'), findsOneWidget);
    await t.pumpWidget(const SizedBox.shrink());
  });
}
