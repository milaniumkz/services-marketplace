import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:camera_platform_interface/camera_platform_interface.dart';
import 'package:services_marketplace/core/selfie_capture_native.dart';
import 'package:services_marketplace/core/photo_file.dart';

const rear = CameraDescription(
    name: 'rear',
    lensDirection: CameraLensDirection.back,
    sensorOrientation: 90);
const front = CameraDescription(
    name: 'front',
    lensDirection: CameraLensDirection.front,
    sensorOrientation: 270);

class FakeCamera extends CameraPlatform {
  List<CameraDescription> devices = [rear, front];
  final errors = StreamController<CameraErrorEvent>.broadcast();
  CameraDescription? opened;
  MediaSettings? settings;
  int released = 0;
  File? temporary;
  @override
  Future<List<CameraDescription>> availableCameras() async => devices;
  @override
  Future<int> createCameraWithSettings(
      CameraDescription cameraDescription, MediaSettings mediaSettings) async {
    opened = cameraDescription;
    settings = mediaSettings;
    return 1;
  }

  @override
  Future<void> initializeCamera(int cameraId,
      {ImageFormatGroup imageFormatGroup = ImageFormatGroup.unknown}) async {}
  @override
  Stream<CameraInitializedEvent> onCameraInitialized(int cameraId) =>
      Stream.value(CameraInitializedEvent(cameraId, 1280, 720,
          ExposureMode.auto, false, FocusMode.auto, false));
  @override
  Stream<CameraErrorEvent> onCameraError(int cameraId) => errors.stream;
  @override
  Stream<DeviceOrientationChangedEvent> onDeviceOrientationChanged() =>
      const Stream.empty();
  @override
  Widget buildPreview(int cameraId) => const Text('Front camera preview');
  @override
  Future<void> dispose(int cameraId) async {
    released++;
  }

  @override
  Future<XFile> takePicture(int cameraId) async {
    final dir = await Directory.systemTemp.createTemp('joba-selfie-test-');
    temporary = File('${dir.path}/frame.jpg');
    await temporary!.writeAsBytes([255, 216, 255, 1]);
    return XFile(temporary!.path);
  }
}

void main() {
  test(
      'selfies choose an actual front lens and never fall back to a rear camera',
      () {
    expect(frontSelfieCamera([rear, front]), front);
    expect(() => frontSelfieCamera([rear]), throwsA(isA<CameraException>()));
  });
  testWidgets(
      'native selfie previews front lens, captures without audio and releases private temporary photo',
      (t) async {
    final fake = FakeCamera();
    CameraPlatform.instance = fake;
    PhotoFile? photo;
    await t.pumpWidget(MaterialApp(
        home: Builder(
            builder: (context) => Scaffold(
                body: TextButton(
                    onPressed: () async {
                      photo = await captureSelfiePhoto(context);
                    },
                    child: const Text('Open'))))));
    await t.tap(find.text('Open'));
    await t.pumpAndSettle();
    expect(fake.opened, front);
    expect(fake.settings!.enableAudio, false);
    expect(find.text('Front camera preview'), findsOneWidget);
    await t.tap(find.text('Сделать селфи'));
    // Camera files use real async I/O; advance both frames and the I/O loop.
    for (var i = 0; i < 100 && photo == null; i++) {
      await t.pump(const Duration(milliseconds: 50));
      await t.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 20)));
    }
    await t.pumpAndSettle();
    expect(photo, isNotNull);
    expect(fake.temporary!.existsSync(), false);
    await t.runAsync(() => fake.temporary!.parent.delete());
    expect(fake.released, 1);
    expect(t.takeException(), isNull);
  });
  testWidgets(
      'missing front lens reports an error instead of opening rear camera',
      (t) async {
    final fake = FakeCamera()..devices = [rear];
    CameraPlatform.instance = fake;
    await t.pumpWidget(const MaterialApp(home: NativeSelfieCamera()));
    await t.pumpAndSettle();
    expect(fake.opened, isNull);
    expect(find.text('На устройстве не найдена фронтальная камера.'),
        findsOneWidget);
    expect(
        t
            .widget<FilledButton>(
                find.byWidgetPredicate((w) => w is FilledButton))
            .onPressed,
        isNull);
    await t.pumpWidget(const SizedBox.shrink());
  });
  testWidgets(
      'camera is released in background and resumes with front lens only',
      (t) async {
    final fake = FakeCamera();
    CameraPlatform.instance = fake;
    await t.pumpWidget(const MaterialApp(home: NativeSelfieCamera()));
    await t.pumpAndSettle();
    expect(fake.opened, front);
    t.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    await t.pump();
    expect(fake.released, 1);
    t.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await t.pumpAndSettle();
    expect(fake.opened, front);
    expect(fake.settings!.enableAudio, false);
    await t.pumpWidget(const SizedBox.shrink());
    await t.pump();
    expect(fake.released, 2);
    expect(t.takeException(), isNull);
  });
}
