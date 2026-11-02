import 'face_sequence.dart';
import 'package:flutter/material.dart';
import 'photo_file.dart';
import 'web_selfie_camera.dart';

Future<FaceSequence?> captureFacePhotos(BuildContext context) async {
  final photos = <PhotoFile>[];
  final last = await captureWebSelfie(
      guided: true, onFrame: (_, photo) => photos.add(photo));
  return last == null ? null : FaceSequence(photos);
}
