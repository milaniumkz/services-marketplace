import 'dart:typed_data';
import 'api.dart';

enum PhotoSource { gallery, camera }

class PhotoFile {
  final Uint8List bytes;
  final String mime;
  PhotoFile._(this.bytes, this.mime);
  factory PhotoFile(Uint8List bytes) {
    if (bytes.length >= 3 &&
        bytes[0] == 255 &&
        bytes[1] == 216 &&
        bytes[2] == 255) {
      return PhotoFile._(bytes, 'image/jpeg');
    }
    if (bytes.length >= 8 &&
        bytes.take(8).join(',') == '137,80,78,71,13,10,26,10') {
      return PhotoFile._(bytes, 'image/png');
    }
    throw ApiException(
        'UNSUPPORTED_PHOTO', 'Выберите фотографию в формате JPG или PNG.');
  }
}
