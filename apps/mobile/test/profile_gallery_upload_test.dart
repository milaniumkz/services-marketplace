import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:services_marketplace/core/api.dart';
import 'package:services_marketplace/core/photo_file.dart';
import 'package:services_marketplace/screens/profile_gallery_upload.dart';

class GalleryApi extends JobaApi {
  int uploads = 0, writes = 0;
  bool failSave = false, failUpload = false;
  List<String> gallery = ['old-photo', 'newer-photo'];
  Json? saved;
  GalleryApi() : super('https://isolated.example') {
    session = {'access_token': 'test'};
  }
  @override
  Future<Json> upload(Uint8List bytes, String mime, String purpose,
      {String? verificationId}) async {
    expect(purpose, 'portfolio');
    uploads++;
    if (failUpload && uploads == 2)
      throw ApiException('OFFLINE', 'Нет соединения');
    return {'id': 'photo-${bytes.last}', 'status': 'clean'};
  }

  @override
  Future<dynamic> request(String path,
      {String method = 'GET',
      Json? body,
      Json query = const {},
      String? key,
      bool authenticated = true,
      String? capability}) async {
    expect(path, '/me/contractor-profile');
    if (method == 'GET')
      return {
        'profile': {
          'version': 7,
          'title': 'Fresh title',
          'gallery_ids': gallery
        }
      };
    writes++;
    saved = Json.from(body!);
    if (failSave) {
      failSave = false;
      throw ApiException('OFFLINE', 'Нет соединения');
    }
    expect(saved!['expected_version'], 7);
    expect(saved!['title'], 'Fresh title');
    gallery = (body['gallery_ids'] as List).cast<String>();
    return {'version': 8};
  }
}

void main() {
  for (final failure in ['none', 'upload', 'save']) {
    testWidgets(
        'batch attaches all photos, preserves latest profile and retries $failure without selection loss',
        (t) async {
      final api = GalleryApi()
        ..failSave = failure == 'save'
        ..failUpload = failure == 'upload';
      var picks = 0, saved = 0;
      await t.pumpWidget(MaterialApp(
          locale: const Locale('ru'),
          supportedLocales: const [Locale('ru')],
          localizationsDelegates: GlobalMaterialLocalizations.delegates,
          home: Scaffold(
              body: ProfileGalleryUpload(
            api: api,
            count: 1,
            onSaved: () => saved++,
            pick: (limit) async {
              expect(limit, 19);
              picks++;
              return [
                PhotoFile(Uint8List.fromList([255, 216, 255, 1])),
                PhotoFile(Uint8List.fromList([255, 216, 255, 2]))
              ];
            },
          ))));
      await t.tap(find.text('Добавить фотографии'));
      await t.pumpAndSettle();
      if (failure != 'none') {
        expect(saved, 0);
        await t.tap(find.text('Повторить загрузку'));
        await t.pumpAndSettle();
      }
      expect(picks, 1);
      expect(saved, 1);
      expect(api.gallery, ['old-photo', 'newer-photo', 'photo-1', 'photo-2']);
      expect(api.uploads, failure == 'upload' ? 3 : 2);
      await t.pumpWidget(const SizedBox());
      api.dispose();
    });
  }
  testWidgets(
      'cancel and selection beyond remaining slots never upload or save',
      (t) async {
    final api = GalleryApi();
    var selections = 0;
    await t.pumpWidget(MaterialApp(
        locale: const Locale('ru'),
        supportedLocales: const [Locale('ru')],
        localizationsDelegates: GlobalMaterialLocalizations.delegates,
        home: Scaffold(
            body: ProfileGalleryUpload(
          api: api,
          count: 19,
          onSaved: () => fail('Must not save'),
          pick: (_) async {
            selections++;
            return selections == 1
                ? []
                : List.generate(2,
                    (_) => PhotoFile(Uint8List.fromList([255, 216, 255, 1])));
          },
        ))));
    await t.tap(find.text('Добавить фотографии'));
    await t.pumpAndSettle();
    await t.tap(find.text('Добавить фотографии'));
    await t.pumpAndSettle();
    expect(api.uploads, 0);
    expect(api.writes, 0);
    expect(find.textContaining('не больше 20'), findsOneWidget);
    await t.pumpWidget(const SizedBox());
    api.dispose();
  });
}
