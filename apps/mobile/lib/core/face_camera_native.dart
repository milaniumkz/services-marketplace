import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:webview_flutter/webview_flutter.dart';
import 'package:webview_flutter_android/webview_flutter_android.dart';
import 'package:webview_flutter_wkwebview/webview_flutter_wkwebview.dart';
import 'face_sequence.dart';
import 'face_motion.dart';
import 'photo_file.dart';
import 'external_activity.dart';

Future<FaceSequence?> captureFacePhotos(BuildContext context, {Uri? origin}) =>
    withExternalActivity(() => Navigator.of(context).push<FaceSequence>(
        MaterialPageRoute(
            builder: (_) => NativeFaceCamera(
                origin: origin ?? Uri.parse('https://joba.com.kz')))));

class NativeFaceCamera extends StatefulWidget {
  final Uri origin;
  const NativeFaceCamera({super.key, required this.origin});
  @override
  State<NativeFaceCamera> createState() => _NativeFaceCameraState();
}

class _NativeFaceCameraState extends State<NativeFaceCamera>
    with WidgetsBindingObserver {
  static const native = MethodChannel('joba.face_camera');
  WebViewController? controller;
  FaceMotion motion = FaceMotion();
  final photos = <PhotoFile>[];
  bool capturing = false,
      ready = false,
      closed = false,
      paused = false,
      voice = true;
  String? error;
  int generation = 0;
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    initialize();
  }

  Future<void> speak() async {
    if (voice && !closed)
      try {
        await native.invokeMethod('speak', {'text': facePrompts[motion.step]});
      } catch (_) {}
  }

  Future<void> initialize() async {
    final epoch = ++generation;
    try {
      if (widget.origin.scheme != 'https' || widget.origin.userInfo.isNotEmpty)
        throw StateError('HTTPS required');
      if (await native.invokeMethod<bool>('prepare') != true)
        throw StateError('Camera permission denied');
      if (!mounted || closed || epoch != generation) return;
      PlatformWebViewControllerCreationParams params =
          const PlatformWebViewControllerCreationParams();
      if (WebViewPlatform.instance is WebKitWebViewPlatform)
        params = WebKitWebViewControllerCreationParams(
            allowsInlineMediaPlayback: true,
            mediaTypesRequiringUserAction: const {});
      final view = WebViewController.fromPlatformCreationParams(params,
          onPermissionRequest: (request) {
        if (epoch == generation &&
            !closed &&
            !paused &&
            request.types.isNotEmpty &&
            request.types
                .every((t) => t == WebViewPermissionResourceType.camera)) {
          request.grant();
        } else {
          request.deny();
        }
      });
      if (view.platform is AndroidWebViewController)
        await (view.platform as AndroidWebViewController)
            .setMediaPlaybackRequiresUserGesture(false);
      await view.setJavaScriptMode(JavaScriptMode.unrestricted);
      await view.setBackgroundColor(const Color(0xff0e213c));
      await view.addJavaScriptChannel('JobaFace', onMessageReceived: (event) {
        if (epoch == generation && !paused) message(event);
      });
      final uri = widget.origin.resolve('/face-camera-native.html');
      await view.setNavigationDelegate(
          NavigationDelegate(onNavigationRequest: (request) {
        final next = Uri.tryParse(request.url);
        return !closed &&
                next?.scheme == 'https' &&
                next!.origin == uri.origin &&
                next.path == uri.path
            ? NavigationDecision.navigate
            : NavigationDecision.prevent;
      }, onWebResourceError: (e) {
        if (mounted && epoch == generation && e.isForMainFrame == true)
          setState(() => error =
              'Камера недоступна. Проверьте соединение и повторите попытку.');
      }));
      if (!mounted || closed || epoch != generation) return;
      setState(() => controller = view);
      await view.loadRequest(uri);
    } catch (_) {
      if (mounted && !closed && epoch == generation)
        setState(() => error =
            'Разрешите JOBA доступ к камере в настройках телефона и повторите попытку.');
    }
  }

  void message(JavaScriptMessage event) {
    if (!mounted ||
        closed ||
        paused ||
        error != null ||
        event.message.length > 3000000) return;
    try {
      final data = jsonDecode(event.message) as Map<String, dynamic>;
      if (data['type'] == 'ready') {
        setState(() => ready = true);
        unawaited(speak());
      } else if (data['type'] == 'error') {
        setState(() => error = '${data['message']}');
      } else if (data['type'] == 'metrics' &&
          ready &&
          !capturing &&
          !motion.finished) {
        final now = (data['time'] as num).round();
        if (motion.observe(Map<String, dynamic>.from(data['metrics']), now)) {
          capturing = true;
          unawaited(controller!
              .runJavaScript('window.JobaNativeFace.capture(${motion.step})')
              .catchError((Object _) {
            if (mounted)
              setState(
                  () => error = 'Не удалось сохранить кадр. Повторите съёмку.');
          }));
        }
        setState(() {});
      } else if (data['type'] == 'frame' &&
          capturing &&
          data['step'] == motion.step) {
        final bytes = base64Decode(data['photo']);
        if (bytes.isEmpty || bytes.length > 2000000)
          throw StateError('Invalid frame');
        photos.add(PhotoFile(bytes));
        capturing = false;
        if (photos.length == faceSteps.length) {
          unawaited(finish());
        } else {
          motion.advance((data['time'] as num).round());
          setState(() {});
          unawaited(speak());
        }
      }
    } catch (_) {
      if (mounted)
        setState(() => error = 'Не удалось обработать кадр. Повторите съёмку.');
    }
  }

  Future<void> finish() async {
    closed = true;
    generation++;
    try {
      await controller?.runJavaScript('window.JobaNativeFace.stop()');
    } catch (_) {}
    try {
      await native.invokeMethod('stop');
    } catch (_) {}
    if (mounted) Navigator.pop(context, FaceSequence(List.of(photos)));
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused) {
      paused = true;
      generation++;
      unawaited(native.invokeMethod('stop').catchError((Object _) {}));
      unawaited(controller
              ?.runJavaScript('window.JobaNativeFace?.stop()')
              .catchError((Object _) {}) ??
          Future.value());
    }
    if (state == AppLifecycleState.resumed && paused) {
      paused = false;
      unawaited(restart());
    }
  }

  Future<void> restart() async {
    final old = controller;
    generation++;
    photos.clear();
    motion = FaceMotion();
    capturing = false;
    ready = false;
    error = null;
    setState(() => controller = null);
    try {
      await old?.runJavaScript('window.JobaNativeFace?.stop()');
    } catch (_) {}
    if (mounted && !closed && !paused) await initialize();
  }

  @override
  void dispose() {
    closed = true;
    generation++;
    WidgetsBinding.instance.removeObserver(this);
    unawaited(controller
            ?.runJavaScript('window.JobaNativeFace?.stop()')
            .catchError((Object _) {}) ??
        Future.value());
    unawaited(native.invokeMethod('stop').catchError((Object _) {}));
    photos.clear();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        backgroundColor: const Color(0xff0e213c),
        appBar: AppBar(title: const Text('Проверка лица')),
        body: SafeArea(
            child: LayoutBuilder(
                builder: (context, constraints) => SingleChildScrollView(
                    child: SizedBox(
                        height: math.max(constraints.maxHeight, 540),
                        child: Column(children: [
                          Padding(
                              padding: const EdgeInsets.all(16),
                              child: Column(children: [
                                Text('Шаг ${motion.step + 1} из 5',
                                    style:
                                        const TextStyle(color: Colors.white)),
                                Text(facePrompts[motion.step.clamp(0, 4)],
                                    textAlign: TextAlign.center,
                                    style: const TextStyle(
                                        color: Colors.white,
                                        fontSize: 22,
                                        fontWeight: FontWeight.bold)),
                                const SizedBox(height: 8),
                                LinearProgressIndicator(
                                    value: photos.length / 5),
                              ])),
                          Expanded(
                              child:
                                  Stack(alignment: Alignment.center, children: [
                            if (controller != null)
                              WebViewWidget(controller: controller!),
                            IgnorePointer(
                                child: FractionallySizedBox(
                                    widthFactor: .65,
                                    heightFactor: .78,
                                    child: DecoratedBox(
                                        decoration: BoxDecoration(
                                            border: Border.all(
                                                color: Colors.lightBlueAccent,
                                                width: 3),
                                            borderRadius:
                                                BorderRadius.circular(250))))),
                            if (!ready && error == null)
                              const CircularProgressIndicator(),
                          ])),
                          Padding(
                              padding: const EdgeInsets.all(16),
                              child: Text(
                                  error ??
                                      (ready
                                          ? motion.hint
                                          : 'Открываем фронтальную камеру…'),
                                  textAlign: TextAlign.center,
                                  style: TextStyle(
                                      color: error == null
                                          ? Colors.white
                                          : Colors.orangeAccent))),
                          if (error != null)
                            TextButton(
                                onPressed: restart,
                                child: const Text('Повторить съёмку')),
                          TextButton(
                              onPressed: () {
                                setState(() => voice = !voice);
                                if (voice)
                                  unawaited(speak());
                                else
                                  unawaited(native
                                      .invokeMethod('stop')
                                      .catchError((Object _) {}));
                              },
                              child: Text(voice
                                  ? 'Озвучка включена'
                                  : 'Озвучка отключена')),
                          TextButton(
                              onPressed: () => Navigator.pop(context),
                              child: const Text('Отмена')),
                        ]))))),
      );
}
