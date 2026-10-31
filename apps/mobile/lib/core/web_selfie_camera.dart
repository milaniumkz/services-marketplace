import 'dart:async';
import 'dart:convert';
import 'dart:js_interop';
import 'dart:js_interop_unsafe';
import 'package:web/web.dart' as web;
import 'api.dart';
import 'photo_file.dart';

Future<PhotoFile?> captureWebSelfie() {
  final result = Completer<PhotoFile?>();
  web.MediaStream? stream;
  final dialog = web.HTMLDialogElement()
    ..setAttribute('data-joba-selfie-camera', 'true')
    ..setAttribute('aria-label', 'Селфи — фронтальная камера');
  dialog.style.cssText =
      'position:fixed;inset:12px;margin:auto;padding:16px;border:0;border-radius:16px;max-width:460px;max-height:90dvh;width:calc(100% - 24px);box-sizing:border-box;background:#fff;color:#183153;font-family:Arial,sans-serif;z-index:2147483647';
  final title = web.HTMLHeadingElement.h2()..textContent = 'Сделайте селфи';
  final status = web.HTMLParagraphElement()
    ..textContent = 'Разрешите доступ к фронтальной камере.'
    ..setAttribute('role', 'status');
  final video = web.HTMLVideoElement()
    ..autoplay = true
    ..muted = true
    ..setAttribute('playsinline', 'true');
  video.style.cssText =
      'width:100%;max-height:55dvh;object-fit:contain;background:#eef2f7;transform:scaleX(-1)';
  final take = web.HTMLButtonElement()
    ..type = 'button'
    ..textContent = 'Сделать селфи'
    ..disabled = true
    ..setAttribute('data-joba-camera-capture', 'true');
  final retry = web.HTMLButtonElement()
    ..type = 'button'
    ..textContent = 'Открыть камеру повторно'
    ..hidden = true.toJS
    ..setAttribute('data-joba-camera-retry', 'true');
  final cancel = web.HTMLButtonElement()
    ..type = 'button'
    ..textContent = 'Отмена'
    ..setAttribute('data-joba-camera-cancel', 'true');
  for (final b in [take, retry, cancel])
    b.style.cssText =
        'padding:14px 18px;margin:10px 6px 0 0;border-radius:10px;border:0;font-size:16px;background:#245bdb;color:#fff';
  void stop() {
    stream?.getTracks().toDart.forEach((track) => track.stop());
    video.pause();
    video.srcObject = null;
    dialog.remove();
  }

  void finish(PhotoFile? file, [Object? error]) {
    if (result.isCompleted) return;
    stop();
    if (error == null)
      result.complete(file);
    else
      result.completeError(error);
  }

  cancel.onclick = ((web.MouseEvent _) => finish(null)).toJS;
  dialog.addEventListener(
      'cancel',
      ((web.Event event) {
        event.preventDefault();
        finish(null);
      }).toJS);
  take.onclick = ((web.MouseEvent _) {
    try {
      if (video.videoWidth == 0 || video.videoHeight == 0) return;
      final scale = video.videoWidth > video.videoHeight
          ? 1920 / video.videoWidth
          : 1920 / video.videoHeight;
      final factor = scale < 1 ? scale : 1.0;
      final canvas = web.HTMLCanvasElement()
        ..width = (video.videoWidth * factor).round()
        ..height = (video.videoHeight * factor).round();
      (canvas.getContext('2d') as web.CanvasRenderingContext2D)
          .drawImage(video, 0, 0, canvas.width, canvas.height);
      final data = canvas.toDataURL('image/jpeg', 0.9.toJS).split(',').last;
      finish(PhotoFile(base64Decode(data)));
    } catch (_) {
      finish(
          null,
          ApiException('CAMERA_UNAVAILABLE',
              'Не удалось сделать селфи. Откройте камеру заново.'));
    }
  }).toJS;
  dialog.append(title);
  dialog.append(status);
  dialog.append(video);
  dialog.append(take);
  dialog.append(retry);
  dialog.append(cancel);
  web.document.body!.append(dialog);
  dialog.showModal();
  Future<void> start() async {
    retry.disabled = true;
    retry.hidden = true.toJS;
    take.disabled = true;
    status.textContent = 'Открываем фронтальную камеру…';
    try {
      var current = await web.window.navigator.mediaDevices
          .getUserMedia(web.MediaStreamConstraints(
              audio: false.toJS,
              video: {
                'facingMode': {'ideal': 'user'},
                'width': {'ideal': 1280},
                'height': {'ideal': 1280}
              }.jsify()!))
          .toDart;
      if (result.isCompleted) {
        current.getTracks().toDart.forEach((t) => t.stop());
        return;
      }
      stream = current;
      final track = current.getVideoTracks().toDart.first;
      if (track
              .getSettings()
              .getProperty<JSAny?>('facingMode'.toJS)
              ?.dartify() ==
          'environment') {
        current.getTracks().toDart.forEach((t) => t.stop());
        current = await web.window.navigator.mediaDevices
            .getUserMedia(web.MediaStreamConstraints(
                audio: false.toJS,
                video: {
                  'facingMode': {'exact': 'user'}
                }.jsify()!))
            .toDart;
        stream = current;
      }
      if (result.isCompleted) {
        current.getTracks().toDart.forEach((t) => t.stop());
        return;
      }
      video.srcObject = current;
      await video.play().toDart;
      if (result.isCompleted) return;
      status.textContent =
          'Расположите лицо в кадре и нажмите «Сделать селфи».';
      take.disabled = false;
      take.focus();
    } catch (_) {
      if (!result.isCompleted) {
        stream?.getTracks().toDart.forEach((track) => track.stop());
        stream = null;
        video.pause();
        video.srcObject = null;
        status.textContent = 'Не удалось открыть фронтальную камеру. Разрешите камеру для joba.com.kz в настройках сайта. Если браузер пишет «сайт не может запросить разрешение», закройте плавающие кнопки и окна других приложений поверх экрана. Затем нажмите «Открыть камеру повторно». Селфи из галереи не принимается.';
        retry.hidden = false.toJS;
        retry.disabled = false;
        retry.focus();
      }
    }
  }

  retry.onclick = ((web.MouseEvent _) { if (!retry.disabled) unawaited(start()); }).toJS;
  unawaited(start());
  return result.future;
}
