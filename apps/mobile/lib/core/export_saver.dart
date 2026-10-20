import 'api.dart';
import 'export_result.dart';
import 'export_native.dart' if (dart.library.js_interop) 'export_web.dart'
    as platform;
export 'export_result.dart';

Future<ExportResult> saveExport(JobaApi api, String id,
        {void Function(int, int?)? onProgress}) =>
    platform.saveExport(api, id, onProgress: onProgress);
