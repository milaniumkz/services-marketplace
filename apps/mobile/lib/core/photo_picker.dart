import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'photo_file.dart';
import 'photo_source_native.dart'
    if (dart.library.js_interop) 'photo_source_web.dart';
import 'l10n.dart';
export 'photo_file.dart';

typedef PhotoSourcePicker = Future<PhotoFile?> Function(PhotoSource source,
    {required bool selfie});

class _PhotoResult {
  final PhotoFile? photo;
  final Object? error;
  _PhotoResult(this.photo, [this.error]);
}

Future<PhotoFile?> choosePhoto(BuildContext context,
    {bool selfie = false, bool identity = false,
    PhotoSourcePicker sourcePicker = pickPhotoFile}) async {
  if(identity||selfie)return sourcePicker(kIsWeb&&!selfie?PhotoSource.gallery:PhotoSource.camera,selfie:selfie);
  var busy = false;
  final result = await showModalBottomSheet<_PhotoResult>(
      context: context,
      isDismissible: true,
      builder: (sheet) => StatefulBuilder(builder: (sheet, update) {
            Future<void> select(PhotoSource source) async {
              if (busy) return;
              update(() => busy = true);
              try {
                // Open immediately in this tap: awaiting API here loses browser activation.
                final photo = await sourcePicker(source, selfie: selfie);
                if (sheet.mounted && ModalRoute.of(sheet)?.isCurrent == true) Navigator.pop(sheet, _PhotoResult(photo));
              } catch (error) {
                if (sheet.mounted)
                  Navigator.pop(sheet, _PhotoResult(null, error));
              }
            }

            return SafeArea(
                child: Column(mainAxisSize: MainAxisSize.min, children: [
              const Padding(
                  padding: EdgeInsets.all(16),
                  child: UiText('Добавить фотографию',
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
