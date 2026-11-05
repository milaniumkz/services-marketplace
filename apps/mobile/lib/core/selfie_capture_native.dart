import 'dart:async';
import 'dart:io';
import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'photo_file.dart';
import 'external_activity.dart';

CameraDescription frontSelfieCamera(List<CameraDescription> cameras) =>
    cameras.firstWhere(
        (camera) => camera.lensDirection == CameraLensDirection.front,
        orElse: () => throw CameraException(
            'FRONT_CAMERA_UNAVAILABLE', 'Фронтальная камера не найдена'));

Future<PhotoFile?> captureSelfiePhoto(BuildContext context) =>
    withExternalActivity(() => Navigator.of(context).push<PhotoFile>(
        MaterialPageRoute(builder: (_) => const NativeSelfieCamera())));

class NativeSelfieCamera extends StatefulWidget {
  const NativeSelfieCamera({super.key});
  @override
  State<NativeSelfieCamera> createState() => _NativeSelfieState();
}

class _NativeSelfieState extends State<NativeSelfieCamera>
    with WidgetsBindingObserver {
  CameraController? controller;
  Future<void> serial = Future<void>.value();
  int generation = 0;
  bool active = true, loading = true, taking = false, closing = false;
  String? error;
  bool current(int g) => mounted && !closing && active && generation == g;
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    start();
  }

  Future<void> enqueue(Future<void> Function() operation) => serial =
      serial.then((_) => operation()).catchError((Object _, StackTrace __) {});
  Future<void> release() async {
    final old = controller;
    controller = null;
    try {
      await old?.dispose();
    } catch (_) {}
  }

  void start() {
    final g = ++generation;
    if (mounted)
      setState(() {
        loading = true;
        error = null;
      });
    unawaited(enqueue(() async {
      await release();
      if (!current(g)) return;
      CameraController? candidate;
      try {
        final camera = frontSelfieCamera(await availableCameras());
        if (!current(g)) return;
        candidate =
            CameraController(camera, ResolutionPreset.high, enableAudio: false);
        await candidate.initialize();
        if (!current(g)) return;
        final ready = candidate;
        candidate = null;
        setState(() {
          controller = ready;
          loading = false;
        });
      } catch (e) {
        if (current(g))
          setState(() {
            loading = false;
            error = e is CameraException && e.code == 'FRONT_CAMERA_UNAVAILABLE'
                ? 'На устройстве не найдена фронтальная камера.'
                : e is CameraException &&
                        e.code.toLowerCase().contains('denied')
                    ? 'Разрешите JOBA доступ к камере в настройках телефона и повторите попытку.'
                    : 'Не удалось открыть фронтальную камеру. Повторите попытку.';
          });
      } finally {
        await candidate?.dispose();
      }
    }));
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      if (!active && !closing) {
        active = true;
        start();
      }
    } else if (state == AppLifecycleState.inactive ||
        state == AppLifecycleState.paused ||
        state == AppLifecycleState.hidden) {
      active = false;
      generation++;
      if (mounted) setState(() => loading = true);
      unawaited(enqueue(release));
    }
  }

  void capture() {
    final camera = controller, g = generation;
    if (camera == null || taking || loading || closing) return;
    setState(() => taking = true);
    unawaited(enqueue(() async {
      try {
        if (!current(g)) return;
        final photo = await camera.takePicture();
        late PhotoFile result;
        try {
          result = PhotoFile(await photo.readAsBytes());
        } finally {
          try {
            await File(photo.path).delete();
          } catch (_) {}
        }
        if (current(g)) Navigator.of(context).pop(result);
      } catch (_) {
        if (current(g))
          setState(() => error = 'Не удалось сделать селфи. Повторите снимок.');
      } finally {
        if (mounted) setState(() => taking = false);
      }
    }));
  }

  @override
  void dispose() {
    closing = true;
    active = false;
    generation++;
    WidgetsBinding.instance.removeObserver(this);
    unawaited(enqueue(release));
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => PopScope<PhotoFile>(
      onPopInvokedWithResult: (didPop, result) {
        if (didPop) {
          closing = true;
          active = false;
          generation++;
        }
      },
      child: Scaffold(
        appBar: AppBar(
            title: const Text('Селфи'),
            leading: IconButton(
                tooltip: 'Отмена',
                icon: const Icon(Icons.close),
                onPressed: () => Navigator.of(context).pop())),
        body: SafeArea(
            child: Column(children: [
          const Padding(
              padding: EdgeInsets.all(16),
              child: Text(
                  'Посмотрите во фронтальную камеру. Лицо должно быть хорошо освещено.')),
          Expanded(
              child: loading
                  ? const Center(child: CircularProgressIndicator())
                  : controller == null
                      ? const Center(
                          child: Icon(Icons.no_photography_outlined, size: 64))
                      : Center(child: CameraPreview(controller!))),
          if (error != null)
            Padding(
                padding: const EdgeInsets.all(12),
                child: Text(error!,
                    textAlign: TextAlign.center,
                    style: const TextStyle(color: Colors.red))),
          if (controller == null && !loading)
            TextButton(
                onPressed: start,
                child: const Text('Повторить открытие камеры')),
          Padding(
              padding: const EdgeInsets.all(16),
              child: SizedBox(
                  width: double.infinity,
                  child: FilledButton.icon(
                      onPressed: loading || controller == null || taking
                          ? null
                          : capture,
                      icon: const Icon(Icons.camera_alt),
                      label: Text(
                          taking ? 'Сохраняем снимок…' : 'Сделать селфи')))),
        ])),
      ));
}
