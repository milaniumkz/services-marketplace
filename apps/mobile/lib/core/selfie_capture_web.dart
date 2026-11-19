import 'package:flutter/material.dart';
import 'photo_file.dart';
import 'photo_source_web.dart';

Future<PhotoFile?> captureSelfiePhoto(BuildContext context) =>
    pickPhotoFile(PhotoSource.camera, selfie: true);
