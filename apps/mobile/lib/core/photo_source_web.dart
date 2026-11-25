import 'dart:async';
import 'dart:js_interop';
import 'package:web/web.dart' as web;
import 'photo_file.dart';
import 'api.dart';
import 'web_selfie_camera.dart';

// Called directly from the source button's gesture, before any network request.
Future<PhotoFile?> pickPhotoFile(PhotoSource source, {bool selfie = false}) {
  if (selfie) return captureWebSelfie();
  return _pickFiles(source, limit: 1, multiple: false)
      .then((photos) => photos.isEmpty ? null : photos.single);
}

Future<List<PhotoFile>> pickPhotoFiles(PhotoSource source,
        {required int limit}) =>
    _pickFiles(source, limit: limit, multiple: source == PhotoSource.gallery);

Future<List<PhotoFile>> _pickFiles(PhotoSource source,
    {required int limit, required bool multiple}) {
  final input = web.HTMLInputElement()
    ..type = 'file'
    ..multiple = multiple
    ..accept = 'image/jpeg,image/png,.jpg,.jpeg,.png';
  input.setAttribute('data-joba-photo-picker', source.name);
  if (source == PhotoSource.camera)
    input.setAttribute('capture', 'environment');
  input.style.display = 'none';
  web.document.body!.append(input);
  final result = Completer<List<PhotoFile>>();
  void finish(List<PhotoFile> photos, [Object? error, StackTrace? stack]) {
    if (result.isCompleted) return;
    input.remove();
    if (error != null) {
      result.completeError(error, stack);
    } else {
      result.complete(photos);
    }
  }

  input.addEventListener('cancel', ((web.Event event) => finish([])).toJS);
  Future<void> readSelection() async {
    final files = input.files;
    if (files == null || files.length == 0) {
      finish([]);
      return;
    }
    try {
      if (files.length > limit) {
        throw ApiException('TOO_MANY_PHOTOS',
            'В галерее может быть не больше 20 фотографий. Выберите меньше фотографий.');
      }
      final photos = <PhotoFile>[];
      for (var index = 0; index < files.length; index++) {
        final buffer = await files.item(index)!.arrayBuffer().toDart;
        photos.add(PhotoFile(buffer.toDart.asUint8List()));
      }
      finish(photos);
    } catch (error, stack) {
      finish([], error, stack);
    }
  }

  input.addEventListener(
      'change',
      ((web.Event event) {
        unawaited(readSelection());
      }).toJS);
  try {
    input.click();
  } catch (error, stack) {
    finish([], error, stack);
  }
  return result.future;
}
