import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:services_marketplace/core/photo_picker.dart';

void main() {
  for (final identity in [false, true]) {
    for (final source in PhotoSource.values) {
      testWidgets(
          'identity=$identity photo source ${source.name} opens only after its button and preserves cancellation',
          (t) async {
        PhotoSource? selected;
        bool? frontCamera;
        PhotoFile? result;
        await t.pumpWidget(MaterialApp(
            home: Scaffold(
                body: Builder(
                    builder: (context) => TextButton(
                        onPressed: () async {
                          result = await choosePhoto(context,
                              selfie: false, identity: identity, sourcePicker:
                                  (source, {required bool selfie}) async {
                            selected = source;
                            frontCamera = selfie;
                            return PhotoFile(
                                Uint8List.fromList([255, 216, 255, 0]));
                          });
                        },
                        child: const Text('Add'))))));
        await t.tap(find.text('Add'));
        await t.pumpAndSettle();
        expect(selected, isNull);
        await t.tap(find.text(source == PhotoSource.gallery
            ? 'Выбрать из галереи'
            : 'Сделать фото'));
        await t.pumpAndSettle();
        expect(selected, source);
        expect(frontCamera, false);
        expect(result!.mime, 'image/jpeg');
        selected = null;
        await t.tap(find.text('Add'));
        await t.pumpAndSettle();
        await t.tap(find.text('Отмена'));
        await t.pumpAndSettle();
        expect(selected, isNull);
        expect(result, isNull);
      });
    }
  }
  testWidgets('selfie remains camera-only without gallery selection',
      (t) async {
    PhotoSource? selected;
    await t.pumpWidget(MaterialApp(
        home: Builder(
            builder: (context) => TextButton(
                onPressed: () =>
                    choosePhoto(context, selfie: true, identity: true,
                        sourcePicker: (source, {required bool selfie}) async {
                      selected = source;
                      return null;
                    }),
                child: const Text('Selfie')))));
    await t.tap(find.text('Selfie'));
    await t.pumpAndSettle();
    expect(selected, PhotoSource.camera);
    expect(find.text('Выбрать из галереи'), findsNothing);
  });
  test('photo MIME follows image bytes and unsupported formats are rejected',
      () {
    expect(
        PhotoFile(Uint8List.fromList([137, 80, 78, 71, 13, 10, 26, 10])).mime,
        'image/png');
    expect(
        () => PhotoFile(Uint8List.fromList([37, 80, 68, 70])), throwsException);
  });
}
