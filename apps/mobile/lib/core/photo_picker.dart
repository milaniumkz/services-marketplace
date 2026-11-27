import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'photo_file.dart';
import 'api.dart';
import 'photo_source_native.dart'
    if (dart.library.js_interop) 'photo_source_web.dart';
import 'l10n.dart';
import 'selfie_capture_native.dart'
    if (dart.library.js_interop) 'selfie_capture_web.dart';
export 'photo_file.dart';

typedef PhotoSourcePicker = Future<PhotoFile?> Function(PhotoSource source,
    {required bool selfie});

class _PhotoResult<T> {
  final T? photo;
  final Object? error;
  _PhotoResult(this.photo, [this.error]);
}

Future<PhotoFile?> choosePhoto(BuildContext context,
    {bool selfie = false,
    bool identity = false,
    PhotoSourcePicker? sourcePicker}) async {
  final picker = sourcePicker ?? pickPhotoFile;
  if (selfie)
    return sourcePicker == null
        ? captureSelfiePhoto(context)
        : picker(PhotoSource.camera, selfie: true);
  if (identity && kIsWeb) return picker(PhotoSource.gallery, selfie: false);
  return _chooseSource<PhotoFile>(
      context, (source) => picker(source, selfie: false));
}

typedef PhotosSourcePicker = Future<List<PhotoFile>>
    Function(PhotoSource source, {required int limit});

Future<List<PhotoFile>> choosePhotos(BuildContext context,
    {required int limit, PhotosSourcePicker? sourcePicker}) async {
  if (limit < 1) return [];
  final picker = sourcePicker ?? pickPhotoFiles;
  final result = await _chooseSource<List<PhotoFile>>(
      context, (source) => picker(source, limit: limit),
      multiple: true);
  if (result != null && result.length > limit) {
    throw ApiException('TOO_MANY_PHOTOS',
        'В галерее может быть не больше 20 фотографий. Выберите меньше фотографий.');
  }
  return result ?? [];
}

Future<T?> _chooseSource<T>(
    BuildContext context, Future<T?> Function(PhotoSource) picker,
    {bool multiple = false}) async {
  var busy = false;
  final result = await showModalBottomSheet<_PhotoResult<T>>(
      context: context,
      isDismissible: true,
      builder: (sheet) => StatefulBuilder(builder: (sheet, update) {
            Future<void> select(PhotoSource source) async {
              if (busy) return;
              update(() => busy = true);
              try {
                // Open immediately in this tap: awaiting API here loses browser activation.
                final photo = await picker(source);
                if (sheet.mounted && ModalRoute.of(sheet)?.isCurrent == true)
                  Navigator.pop(sheet, _PhotoResult<T>(photo));
              } catch (error) {
                if (sheet.mounted)
                  Navigator.pop(sheet, _PhotoResult<T>(null, error));
              }
            }

            return SafeArea(
                child: Column(mainAxisSize: MainAxisSize.min, children: [
              Padding(
                  padding: const EdgeInsets.all(16),
                  child: UiText(
                      multiple ? 'Добавить фотографии' : 'Добавить фотографию',
                      style: TextStyle(
                          fontWeight: FontWeight.w700, fontSize: 18))),
              ListTile(
                  leading: const Icon(Icons.photo_library_outlined),
                  title: const UiText('Выбрать из галереи'),
                  enabled: !busy,
                  onTap: () => select(PhotoSource.gallery)),
              ListTile(
                  leading: const Icon(Icons.camera_alt_outlined),
                  title: const UiText('Сделать фото'),
                  enabled: !busy,
                  onTap: () => select(PhotoSource.camera)),
              if (busy) const LinearProgressIndicator(),
              TextButton(
                  onPressed: () => Navigator.pop(sheet),
                  child: const UiText('Отмена')),
            ]));
          }));
  if (result?.error != null) throw result!.error!;
  return result?.photo;
}
