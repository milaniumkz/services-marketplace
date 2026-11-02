import 'dart:async';
import 'dart:convert';
import 'dart:js_interop';
import 'dart:js_interop_unsafe';
import 'package:web/web.dart' as web;
import 'api.dart';
import 'photo_file.dart';
import 'face_sequence.dart';
import 'web_face_voice.dart';
import 'web_face_tracker.dart';
import 'face_motion.dart';

Future<PhotoFile?> captureWebSelfie(
    {bool guided = false, void Function(int, PhotoFile)? onFrame}) {
  var step = 0;
  final motion = FaceMotion();
  WebFaceTracker? tracker;
  Timer? trackingTimer, captureDeadline;
  double lastVideoTime = -1, lastAnalysisTime = -1000;
  var trackingEpoch = 0;
  final voice = FaceVoice();
  const prompts = facePrompts;
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
    ..setAttribute('role', 'status')
    ..setAttribute('aria-live', 'polite');
  final video = web.HTMLVideoElement()
    ..autoplay = true
    ..muted = true
    ..setAttribute('playsinline', 'true');
  video.style.cssText =
      'width:100%;max-height:55dvh;object-fit:contain;background:#eef2f7;transform:scaleX(-1)';
  final take = web.HTMLButtonElement()
    ..type = 'button'
    ..textContent = 'Сделать селфи'
    ..hidden = guided.toJS
    ..disabled = true
    ..setAttribute('data-joba-camera-capture', 'true');
  final audio = web.HTMLButtonElement()
    ..type = 'button'
    ..textContent = 'Озвучка: включена'
    ..hidden = (!guided).toJS
    ..setAttribute('data-joba-face-voice', 'true');
  void showStep() {
    title.textContent = 'Съёмка лица · шаг ${step + 1} из ${prompts.length}';
    status.textContent = prompts[step];
    dialog.setAttribute('data-joba-face-step', '$step');
    take.hidden = guided.toJS;
    if (guided) {
      voice.speak(prompts[step]);
      if (!voice.available)
        audio.textContent = 'Озвучка недоступна в этом браузере';
    }
  }

  voice.onUnavailable = () {
    audio.textContent = 'Озвучка недоступна в этом браузере';
  };
  audio.onclick = ((web.MouseEvent _) {
    voice.enabled = !voice.enabled;
    audio.textContent =
        voice.enabled ? 'Озвучка: включена' : 'Озвучка: выключена';
    if (voice.enabled)
      voice.speak(prompts[step]);
    else
      voice.stop();
  }).toJS;
  final retry = web.HTMLButtonElement()
    ..type = 'button'
    ..textContent = 'Открыть камеру повторно'
    ..hidden = true.toJS
    ..setAttribute('data-joba-camera-retry', 'true');
  final cancel = web.HTMLButtonElement()
    ..type = 'button'
    ..textContent = 'Отмена'
    ..setAttribute('data-joba-camera-cancel', 'true');
  for (final b in [take, audio, retry, cancel])
    b.style.cssText =
        'padding:14px 18px;margin:10px 6px 0 0;border-radius:10px;border:0;font-size:16px;background:#245bdb;color:#fff';
  void stop() {
    trackingEpoch++;
    trackingTimer?.cancel();
    captureDeadline?.cancel();
    try {
      tracker?.close();
    } catch (_) {}
    tracker = null;
    voice.stop();
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
  void captureFrame() {
    try {
      if (result.isCompleted || video.videoWidth == 0 || video.videoHeight == 0)
        return;
      final edge = guided ? 960 : 1920;
      final scale = video.videoWidth > video.videoHeight
          ? edge / video.videoWidth
          : edge / video.videoHeight;
      final factor = scale < 1 ? scale : 1.0;
      final canvas = web.HTMLCanvasElement()
        ..width = (video.videoWidth * factor).round()
        ..height = (video.videoHeight * factor).round();
      (canvas.getContext('2d') as web.CanvasRenderingContext2D)
          .drawImage(video, 0, 0, canvas.width, canvas.height);
      final data = canvas
          .toDataURL('image/jpeg', (guided ? 0.85 : 0.9).toJS)
          .split(',')
          .last;
      final photo = PhotoFile(base64Decode(data));
      if (guided) {
        onFrame?.call(step, photo);
        if (step < prompts.length - 1) {
          motion.advance(web.window.performance.now().round());
          step = motion.step;
          showStep();
          return;
        }
      }
      finish(photo);
    } catch (_) {
      finish(
          null,
          ApiException('CAMERA_UNAVAILABLE',
              'Не удалось сделать снимок. Откройте камеру заново.'));
    }
  }

  take.onclick = ((web.MouseEvent _) {
    if (!guided && !take.disabled) captureFrame();
  }).toJS;
  dialog.append(title);
  dialog.append(status);
  final preview = web.HTMLDivElement();
  preview.style.cssText =
      'position:relative;overflow:hidden;border-radius:18px;background:#eef2f7';
  preview.append(video);
  final frame = web.HTMLDivElement()
    ..setAttribute('data-joba-face-frame', 'true')
    ..setAttribute('aria-hidden', 'true');
  frame.style.cssText =
      'pointer-events:none;position:absolute;inset:8% 20%;border:3px solid #77d7ff;border-radius:50%;box-shadow:0 0 0 100vmax #11294a33,inset 0 0 18px #77d7ff55';
  final decoration = web.HTMLStyleElement()
    ..textContent =
        '@keyframes jobaFaceGlow{50%{border-color:#245bdb;box-shadow:0 0 0 100vmax #11294a33,inset 0 0 28px #77d7ff88}} [data-joba-face-frame]{animation:jobaFaceGlow 2.8s ease-in-out infinite} @media(prefers-reduced-motion:reduce){[data-joba-face-frame]{animation:none}}';
  preview.append(decoration);
  preview.append(frame);
  final guide = web.HTMLParagraphElement()
    ..textContent = guided
        ? 'Кадры снимаются автоматически. Следуйте голосу и подсказкам. Это не защита от фотографий или подмены видео.'
        : 'Расположите лицо внутри рамки при хорошем освещении.';
  dialog.append(preview);
  dialog.append(guide);
  dialog.append(audio);
  dialog.append(take);
  dialog.append(retry);
  dialog.append(cancel);
  web.document.body!.append(dialog);
  dialog.showModal();
  Future<void> start() async {
    retry.disabled = true;
    retry.hidden = true.toJS;
    take.disabled = true;
    step = 0;

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
      if (guided) {
        showStep();
        take.hidden = true.toJS;
        final epoch = ++trackingEpoch;
        guide.textContent = 'Подготавливаем автоматическую фиксацию движений…';
        try {
          final loaded = await WebFaceTracker.create();
          if (result.isCompleted || epoch != trackingEpoch) {
            loaded.close();
            return;
          }
          tracker = loaded;
          guide.textContent =
              'Кадры снимаются автоматически. Кнопки нажимать не нужно.';
          captureDeadline = Timer(
              const Duration(minutes: 3),
              () => finish(
                  null,
                  ApiException('FACE_CAPTURE_TIMEOUT',
                      'Не удалось автоматически зафиксировать все пять шагов. Держите лицо в рамке и повторите попытку.')));
          trackingTimer = Timer.periodic(const Duration(milliseconds: 50), (_) {
            if (result.isCompleted || epoch != trackingEpoch || tracker == null)
              return;
            if (video.readyState < 2 || video.currentTime == lastVideoTime)
              return;
            final now = web.window.performance.now();
            if (now - lastAnalysisTime < (motion.step >= 3 ? 45 : 95)) return;
            lastVideoTime = video.currentTime;
            lastAnalysisTime = now;
            try {
              final observation = tracker!.detect(video, now);
              if (motion.observe(observation, now.round())) {
                captureFrame();
              } else if (motion.hint.isNotEmpty &&
                  status.textContent != motion.hint) {
                status.textContent = motion.hint;
              }
            } catch (_) {
              finish(
                  null,
                  ApiException('FACE_TRACKER_FAILED',
                      'Автоматическая съёмка прервалась. Повторите попытку в браузере с поддержкой камеры.'));
            }
          });
        } catch (error) {
          if (!result.isCompleted)
            finish(
                null,
                error is ApiException
                    ? error
                    : ApiException('FACE_TRACKER_UNAVAILABLE',
                        'Не удалось запустить определение движений. Проверьте соединение и повторите попытку.'));
        }
      } else {
        status.textContent =
            'Расположите лицо в кадре и нажмите «Сделать селфи».';
        take.disabled = false;
        take.focus();
      }
    } catch (_) {
      if (!result.isCompleted) {
        stream?.getTracks().toDart.forEach((track) => track.stop());
        stream = null;
        video.pause();
        video.srcObject = null;
        status.textContent =
            'Не удалось открыть фронтальную камеру. Разрешите камеру для joba.com.kz в настройках сайта. Если браузер пишет «сайт не может запросить разрешение», закройте плавающие кнопки и окна других приложений поверх экрана. Затем нажмите «Открыть камеру повторно». Селфи из галереи не принимается.';
        retry.hidden = false.toJS;
        retry.disabled = false;
        retry.focus();
      }
    }
  }

  retry.onclick = ((web.MouseEvent _) {
    if (!retry.disabled) unawaited(start());
  }).toJS;
  unawaited(start());
  return result.future;
}
