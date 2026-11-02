@TestOn('browser')
library;

import 'dart:async';
import 'dart:js_interop';
import 'dart:js_interop_unsafe';
import 'package:web/web.dart' as web;
import 'package:flutter_test/flutter_test.dart';
import 'package:services_marketplace/core/photo_source_web.dart';
import 'package:services_marketplace/core/photo_file.dart';
import 'package:services_marketplace/core/api.dart';
import 'package:services_marketplace/core/web_selfie_camera.dart';

@JS('Object.defineProperty')
external JSObject defineProperty(
    JSObject object, JSString name, JSObject descriptor);
@JS()
extension type _StreamCanvas(JSObject _) implements JSObject {
  external web.MediaStream captureStream([num fps]);
}
void main() {
  final devices = web.window.navigator.mediaDevices,
      original = web.window.navigator.mediaDevices
          .getProperty<JSFunction>('getUserMedia'.toJS);
  void install(JSFunction fn) => devices.setProperty('getUserMedia'.toJS, fn);
  tearDown(() => install(original));
  test(
      'selfie requests front camera, captures JPEG and stops stream without a file input',
      () async {
    final canvas = web.HTMLCanvasElement()
      ..width = 160
      ..height = 120;
    final context = canvas.getContext('2d') as web.CanvasRenderingContext2D;
    context.fillStyle = 'green'.toJS;
    context.fillRect(0, 0, 160, 120);
    final stream = _StreamCanvas(canvas).captureStream(5);
    install(((JSObject constraints) {
      expect(
          constraints
              .getProperty<JSObject>('video'.toJS)
              .getProperty<JSObject>('facingMode'.toJS)
              .getProperty<JSString>('ideal'.toJS)
              .toDart,
          'user');
      return Future.value(stream).toJS;
    }).toJS);
    final future = pickPhotoFile(PhotoSource.gallery, selfie: true);
    expect(web.document.querySelector('input[data-joba-photo-picker]'), isNull);
    final button = web.document.querySelector('[data-joba-camera-capture]')
        as web.HTMLButtonElement;
    for (var i = 0; i < 100 && button.disabled; i++)
      await Future<void>.delayed(const Duration(milliseconds: 30));
    expect(button.disabled, false);
    button.click();
    final image = await future;
    expect(image!.mime, 'image/jpeg');
    expect(image.bytes.length, greaterThan(100));
    expect(web.document.querySelector('[data-joba-selfie-camera]'), isNull);
    expect(
        stream.getTracks().toDart.every((track) => track.readyState == 'ended'),
        true);
  });
  test(
      'automatic recovery captures recognized movements without any capture button and stops voice/tracker',
      () async {
    final canvas = web.HTMLCanvasElement()
      ..width = 160
      ..height = 120;
    final context = canvas.getContext('2d') as web.CanvasRenderingContext2D;
    context.fillStyle = 'blue'.toJS;
    context.fillRect(0, 0, 160, 120);
    final stream = _StreamCanvas(canvas).captureStream(15);
    install(((JSObject _) => Future.value(stream).toJS).toJS);
    final originalSpeech =
            web.window.getProperty<JSAny?>('speechSynthesis'.toJS),
        originalTracker =
            web.window.getProperty<JSAny?>('jobaCreateFaceTracker'.toJS);
    final spoken = <String>[];
    var closed = 0, previous = -1;
    double entered = 0;
    defineProperty(
        web.window,
        'speechSynthesis'.toJS,
        {
          'configurable': true,
          'value': {
            'getVoices': (() => <JSAny>[].toJS).toJS,
            'cancel': (() {}).toJS,
            'resume': (() {}).toJS,
            'speak': ((JSObject u) {
              spoken.add(u.getProperty<JSString>('text'.toJS).toDart);
              expect(u.getProperty<JSNumber>('rate'.toJS).toDartDouble,
                  greaterThan(1));
              expect(u.getProperty<JSNumber>('volume'.toJS).toDartDouble,
                  lessThan(1));
            }).toJS,
          }.jsify()
        }.jsify()! as JSObject);
    web.window.setProperty(
        'jobaCreateFaceTracker'.toJS,
        (() => Future.value({
              'detect': ((JSObject _, JSNumber time) {
                final now = time.toDartDouble;
                final step = int.parse(web.document
                    .querySelector('[data-joba-selfie-camera]')!
                    .getAttribute('data-joba-face-step')!);
                if (step != previous) {
                  previous = step;
                  entered = now;
                }
                final elapsed = now - entered;
                return {
                  'faces': 1,
                  'yaw': step == 1
                      ? 0.2
                      : step == 2
                          ? -0.2
                          : 0.0,
                  'centerX': .5,
                  'centerY': .5,
                  'width': .4,
                  'height': .6,
                  'blinkLeft':
                      step == 3 && elapsed > 900 && elapsed < 1300 ? 0.9 : 0.05,
                  'blinkRight':
                      step == 3 && elapsed > 900 && elapsed < 1300 ? 0.9 : 0.05,
                  'smile': step == 4 ? 0.8 : 0.1
                }.jsify();
              }).toJS,
              'close': (() {
                closed++;
              }).toJS,
            }.jsify()! as JSObject)
                .toJS).toJS);
    addTearDown(() {
      defineProperty(web.window, 'speechSynthesis'.toJS,
          {'configurable': true, 'value': originalSpeech}.jsify()! as JSObject);
      web.window.setProperty('jobaCreateFaceTracker'.toJS, originalTracker);
    });
    final captured = <int>[];
    final future = captureWebSelfie(
        guided: true,
        onFrame: (i, p) {
          captured.add(i);
          expect(p.bytes, isNotEmpty);
        });
    final take = web.document.querySelector('[data-joba-camera-capture]')
        as web.HTMLButtonElement;
    expect(take.hasAttribute('hidden'), true);
    final photo = await future.timeout(const Duration(seconds: 15));
    expect(photo!.mime, 'image/jpeg');
    expect(captured, [0, 1, 2, 3, 4]);
    expect(spoken, hasLength(5));
    expect(closed, 1);
    expect(
        stream.getTracks().toDart.every((t) => t.readyState == 'ended'), true);
    expect(web.document.querySelector('[data-joba-selfie-camera]'), isNull);
  });
  test(
      'automatic tracking failure closes camera with an error and never falls back to manual capture',
      () async {
    final canvas = web.HTMLCanvasElement()
      ..width = 160
      ..height = 120;
    final context = canvas.getContext('2d') as web.CanvasRenderingContext2D;
    context.fillRect(0, 0, 160, 120);
    final stream = _StreamCanvas(canvas).captureStream(5);
    install(((JSObject _) => Future.value(stream).toJS).toJS);
    final previous =
        web.window.getProperty<JSAny?>('jobaCreateFaceTracker'.toJS);
    web.window.setProperty(
        'jobaCreateFaceTracker'.toJS,
        (() => Future<JSObject>.error(Exception('model unavailable')).toJS)
            .toJS);
    addTearDown(
        () => web.window.setProperty('jobaCreateFaceTracker'.toJS, previous));
    final future = captureWebSelfie(guided: true);
    await expectLater(future, throwsA(isA<ApiException>()));
    expect(web.document.querySelector('[data-joba-selfie-camera]'), isNull);
    expect(
        stream.getTracks().toDart.every((t) => t.readyState == 'ended'), true);
  });
  test('selfie cancellation before permission resolves stops a late stream',
      () async {
    final completer = Completer<web.MediaStream>();
    install(((JSObject _) => completer.future.toJS).toJS);
    final future = pickPhotoFile(PhotoSource.camera, selfie: true);
    (web.document.querySelector('[data-joba-camera-cancel]')
            as web.HTMLButtonElement)
        .click();
    expect(await future, isNull);
    final canvas = web.HTMLCanvasElement()
      ..width = 16
      ..height = 16;
    final stream = _StreamCanvas(canvas).captureStream(1);
    completer.complete(stream);
    await Future<void>.delayed(const Duration(milliseconds: 30));
    expect(
        stream.getTracks().toDart.every((track) => track.readyState == 'ended'),
        true);
  });
  test(
      'camera permission denial keeps guidance open, retries on click and cancels without a gallery fallback',
      () async {
    install(((JSObject _) =>
            Future<web.MediaStream>.error(Exception('permission denied')).toJS)
        .toJS);
    final future = pickPhotoFile(PhotoSource.camera, selfie: true);
    await Future<void>.delayed(const Duration(milliseconds: 50));
    expect(web.document.querySelector('[data-joba-selfie-camera]'), isNotNull);
    expect(web.document.querySelector('[data-joba-selfie-camera]')!.textContent,
        contains('плавающие кнопки'));
    expect(web.document.querySelector('input[data-joba-photo-picker]'), isNull);
    final retry = web.document.querySelector('[data-joba-camera-retry]')
        as web.HTMLButtonElement;
    expect(retry.hasAttribute('hidden'), false);
    var requests = 0;
    install(((JSObject _) {
      requests++;
      return Future<web.MediaStream>.error(Exception('still denied')).toJS;
    }).toJS);
    retry.click();
    await Future<void>.delayed(const Duration(milliseconds: 50));
    expect(requests, 1);
    expect(retry.hasAttribute('hidden'), false);
    (web.document.querySelector('[data-joba-camera-cancel]')
            as web.HTMLButtonElement)
        .click();
    expect(await future, isNull);
    expect(web.document.querySelector('[data-joba-selfie-camera]'), isNull);
  });
}
