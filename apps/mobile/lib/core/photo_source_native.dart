import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'api.dart';
import 'photo_file.dart';
import 'external_activity.dart';

Future<PhotoFile?> pickPhotoFile(PhotoSource source,
    {bool selfie = false}) => withExternalActivity(() async {
  try {
    final file = await ImagePicker().pickImage(
      source: selfie || source == PhotoSource.camera
          ? ImageSource.camera
          : ImageSource.gallery,
      preferredCameraDevice: selfie ? CameraDevice.front : CameraDevice.rear,
      maxWidth: 2048,
      maxHeight: 2048,
      imageQuality: 88,
      requestFullMetadata: false,
    );
    return file == null ? null : PhotoFile(await file.readAsBytes());
  } on PlatformException catch (e) {
    throw ApiException(
        'PHOTO_UNAVAILABLE',
        e.code.contains('denied') || e.code.contains('restricted')
            ? 'Разрешите доступ к камере или фотографиям в настройках устройства.'
            : 'Не удалось открыть камеру или фотографии. Попробуйте другой способ.');
  }
});
