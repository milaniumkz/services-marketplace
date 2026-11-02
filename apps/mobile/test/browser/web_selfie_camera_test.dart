@TestOn('browser')
library;

import 'dart:async';
import 'dart:js_interop';
import 'dart:js_interop_unsafe';
import 'package:web/web.dart' as web;
import 'package:flutter_test/flutter_test.dart';
import 'package:services_marketplace/core/photo_source_web.dart';
import 'package:services_marketplace/core/photo_file.dart';
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
      'guided recovery records five frames in order, speaks instructions and stops speech on close',
      () async {
    final canvas = web.HTMLCanvasElement()
      ..width = 160
      ..height = 120;
    final context = canvas.getContext('2d') as web.CanvasRenderingContext2D;
    context.fillStyle = 'blue'.toJS;
    context.fillRect(0, 0, 160, 120);
    final stream = _StreamCanvas(canvas).captureStream(5);
    install(((JSObject _) => Future.value(stream).toJS).toJS);
    final originalSpeech =
        web.window.getProperty<JSAny?>('speechSynthesis'.toJS);
    final spoken = <String>[];
    var cancelled = 0;
    defineProperty(
        web.window,
        'speechSynthesis'.toJS,
        {
          'configurable': true,
          'value': {
            'getVoices': (() => <JSAny>[].toJS).toJS,
            'cancel': (() {
              cancelled++;
            }).toJS,
            'resume': (() {}).toJS,
            'speak': ((JSObject utterance) {
              spoken.add(utterance.getProperty<JSString>('text'.toJS).toDart);
            }).toJS,
          }.jsify()
        }.jsify()! as JSObject);
    addTearDown(() => defineProperty(web.window, 'speechSynthesis'.toJS,
        {'configurable': true, 'value': originalSpeech}.jsify()! as JSObject));
    final captured = <int>[];
    final future = captureWebSelfie(
        guided: true,
        onFrame: (i, photo) {
          captured.add(i);
          expect(photo.bytes, isNotEmpty);
        });
    final take = web.document.querySelector('[data-joba-camera-capture]')
        as web.HTMLButtonElement;
    for (var i = 0; i < 100 && take.disabled; i++)
      await Future<void>.delayed(const Duration(milliseconds: 30));
    final dialog = web.document.querySelector('[data-joba-selfie-camera]')!;
    expect(
        dialog.textContent, contains('Движения автоматически не проверяются'));
    take.click();
    expect(captured, isEmpty);
    expect(spoken.last, contains('Посмотрите прямо'));
    for (final text in ['налево', 'направо', 'моргните', 'улыбнитесь']) {
      take.click();
      expect(dialog.textContent, contains(text));
      expect(spoken.last, contains(text));
    }
    expect(captured, [0, 1, 2, 3]);
    take.click();
    expect((await future)!.mime, 'image/jpeg');
    expect(captured, [0, 1, 2, 3, 4]);
    expect(spoken, hasLength(5));
    expect(cancelled, greaterThanOrEqualTo(6));
    expect(
        stream.getTracks().toDart.every((track) => track.readyState == 'ended'),
        true);
    expect(web.document.querySelector('[data-joba-selfie-camera]'), isNull);
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
