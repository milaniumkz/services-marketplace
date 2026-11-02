import 'package:flutter/material.dart';
import 'face_sequence.dart';
import 'photo_file.dart';
import 'photo_source_native.dart';

// Native source uses the same steps. APK is not built in this web release.
Future<FaceSequence?> captureFacePhotos(BuildContext context) async {
  final photos = <PhotoFile>[];
  for (var i = 0; i < faceSteps.length; i++) {
    if (!context.mounted) return null;
    final photo = await showDialog<PhotoFile>(
        context: context,
        builder: (dialog) => AlertDialog(
              title: Text('Съёмка лица · шаг ${i + 1} из ${faceSteps.length}'),
              content: Text(facePrompts[i]),
              actions: [
                TextButton(
                    onPressed: () => Navigator.pop(dialog),
                    child: const Text('Отмена')),
                FilledButton(
                    onPressed: () async {
                      final frame =
                          await pickPhotoFile(PhotoSource.camera, selfie: true);
                      if (dialog.mounted) Navigator.pop(dialog, frame);
                    },
                    child: const Text('Снять кадр'))
              ],
            ));
    if (photo == null) return null;
    photos.add(photo);
  }
  return FaceSequence(photos);
}
