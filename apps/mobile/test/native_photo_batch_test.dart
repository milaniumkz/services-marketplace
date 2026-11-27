import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:image_picker_platform_interface/image_picker_platform_interface.dart';
import 'package:services_marketplace/core/photo_source_native.dart';
import 'package:services_marketplace/core/photo_file.dart';
import 'package:services_marketplace/core/external_activity.dart';

class GalleryPicker extends ImagePickerPlatform {
  int calls = 0;
  @override
  Future<List<XFile>> getMultiImageWithOptions(
      {MultiImagePickerOptions options =
          const MultiImagePickerOptions()}) async {
    calls++;
    expect(externalActivityActive, true);
    expect(options.limit, 3);
    expect(options.imageOptions.maxWidth, 2048);
    expect(options.imageOptions.maxHeight, 2048);
    expect(options.imageOptions.imageQuality, 88);
    expect(options.imageOptions.requestFullMetadata, false);
    return [
      for (final n in [1, 2, 3])
        XFile.fromData(Uint8List.fromList([255, 216, 255, n]))
    ];
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test(
      'native gallery uses system multi picker, resizes photos and keeps PIN suspension',
      () async {
    final original = ImagePickerPlatform.instance;
    final picker = GalleryPicker();
    ImagePickerPlatform.instance = picker;
    try {
      final photos = await pickPhotoFiles(PhotoSource.gallery, limit: 3);
      expect(picker.calls, 1);
      expect(photos.map((p) => p.bytes.last), [1, 2, 3]);
    } finally {
      ImagePickerPlatform.instance = original;
    }
  });
}
