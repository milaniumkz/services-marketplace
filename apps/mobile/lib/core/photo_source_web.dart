import 'dart:async';
import 'dart:js_interop';
import 'package:web/web.dart' as web;
import 'photo_file.dart';

// Called directly from the source button's gesture, before any network request.
Future<PhotoFile?> pickPhotoFile(PhotoSource source, {bool selfie = false}) {
  final input = web.HTMLInputElement()
    ..type = 'file'
    ..accept = 'image/jpeg,image/png,.jpg,.jpeg,.png';
  input.setAttribute('data-joba-photo-picker', source.name);
  if (source == PhotoSource.camera)
    input.setAttribute('capture', selfie ? 'user' : 'environment');
  input.style.display = 'none';
  web.document.body!.append(input);
  final result = Completer<PhotoFile?>();
  void finish(PhotoFile? photo, [Object? error, StackTrace? stack]) {
    if (result.isCompleted) return;
    input.remove();
    if (error != null) {
      result.completeError(error, stack);
    } else {
      result.complete(photo);
    }
  }

  input.addEventListener('cancel', ((web.Event event) => finish(null)).toJS);
  Future<void> readSelection() async {
    final file = input.files?.item(0);
    if (file == null) {
      finish(null);
      return;
    }
    try {
      final buffer = await file.arrayBuffer().toDart;
      finish(PhotoFile(buffer.toDart.asUint8List()));
    } catch (error, stack) {
      finish(null, error, stack);
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
    finish(null, error, stack);
  }
  return result.future;
}
