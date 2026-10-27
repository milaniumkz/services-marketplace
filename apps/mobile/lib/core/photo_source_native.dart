import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'api.dart';
import 'photo_file.dart';

Future<PhotoFile?> pickPhotoFile(PhotoSource source,
    {bool selfie = false}) async {
  try {
    final file = await ImagePicker().pickImage(
      source: source == PhotoSource.camera
          ? ImageSource.camera
          : ImageSource.gallery,
      preferredCameraDevice: selfie ? CameraDevice.front : CameraDevice.rear,
      maxWidth: 4096,
      maxHeight: 4096,
      imageQuality: 95,
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
}
