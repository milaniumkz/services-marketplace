import 'package:web/web.dart' as web;
import 'api.dart';
import 'export_result.dart';

Future<ExportResult> saveExport(JobaApi api, String id,
    {void Function(int, int?)? onProgress}) async {
  final ticket = await api.request('/uploads/$id/download-url'),
      uri = Uri.parse(ticket['url']);
  if (uri.hasAuthority &&
          (uri.host != api.base.host ||
              uri.port != api.base.port ||
              uri.scheme != api.base.scheme) ||
      !uri.path.startsWith('/api/v1/private-files/'))
    throw ApiException('EXPORT_UNAVAILABLE', 'Некорректный адрес архива');
  final address =
      api.url(uri.path.substring('/api/v1'.length), uri.queryParameters);
  final anchor = web.HTMLAnchorElement()
    ..href = address.toString()
    ..download = 'joba-export.zip'
    ..referrerPolicy = 'no-referrer';
  web.document.body?.append(anchor);
  anchor.click();
  anchor.remove();
  return ExportResult.started;
}
