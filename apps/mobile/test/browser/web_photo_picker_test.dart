@TestOn('browser')
library;

import 'dart:js_interop';
import 'dart:typed_data';
import 'package:web/web.dart' as web;
import 'package:flutter_test/flutter_test.dart';
import 'package:services_marketplace/core/photo_source_web.dart';
import 'package:services_marketplace/core/photo_file.dart';

void main() {
  for (final source in PhotoSource.values) {
    test(
        'browser ${source.name} creates input immediately, reads photo and cleans up',
        () async {
      final pending = pickPhotoFile(source, selfie: false);
      final input = web.document.querySelector('[data-joba-photo-picker]')
          as web.HTMLInputElement;
      expect(input.accept, contains('image/jpeg'));
      expect(input.getAttribute('capture'),
          source == PhotoSource.camera ? 'environment' : isNull);
      final transfer = web.DataTransfer();
      final bytes = Uint8List.fromList([255, 216, 255, 0]);
      transfer.items.add(web.File([bytes.toJS].toJS, 'photo.jpg',
          web.FilePropertyBag(type: 'image/jpeg')));
      input.files = transfer.files;
      input.dispatchEvent(web.Event('change'));
      final photo = await pending;
      expect(photo!.bytes, orderedEquals(bytes));
      expect(photo.mime, 'image/jpeg');
      expect(web.document.querySelector('[data-joba-photo-picker]'), isNull);
    });
  }
  test('browser cancellation releases input and allows another selection',
      () async {
    final pending = pickPhotoFile(PhotoSource.gallery);
    final input = web.document.querySelector('[data-joba-photo-picker]')!;
    input.dispatchEvent(web.Event('cancel'));
    expect(await pending, isNull);
    expect(web.document.querySelector('[data-joba-photo-picker]'), isNull);
  });
}
