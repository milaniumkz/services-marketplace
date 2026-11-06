import 'dart:io';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';
import 'api.dart';
import 'export_result.dart';

Future<ExportResult> saveExport(JobaApi api, String id,
    {void Function(int, int?)? onProgress}) async {
  if (!Platform.isAndroid && !Platform.isIOS)
    throw ApiException('EXPORT_UNAVAILABLE', 'Сохранение архива недоступно');
  final generation = api.sessionGeneration;
  final root = await getTemporaryDirectory(),
      directory = await Directory(root.path).createTemp('joba-export-');
  IOSink? sink;
  try {
    final file = File('${directory.path}/joba-export.zip');
    sink = file.openWrite();
    await api.downloadToSink(id, sink, onProgress: onProgress);
    await sink.flush();
    await sink.close();
    sink = null;
    if (api.sessionGeneration != generation || !api.authenticated)
      throw ApiException(
          'SESSION_SUPERSEDED', 'Сессия изменилась. Повторите вход', 401);
    final saved = await const MethodChannel('joba.file_export')
        .invokeMethod<bool>('save', {
      'path': file.path,
      'filename': 'joba-export.zip',
      'mime': 'application/zip'
    });
    return saved == true ? ExportResult.saved : ExportResult.cancelled;
  } on PlatformException {
    throw ApiException('EXPORT_UNAVAILABLE', 'Не удалось сохранить архив');
  } finally {
    await sink?.close();
    await directory.delete(recursive: true);
  }
}
