import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http;
import 'package:uuid/uuid.dart';

String diagnosticText(Object? value, [int limit = 1200]) {
  var text = '$value';
  if (text.length > limit * 2) text = text.substring(0, limit * 2);
  text = text
      .replaceAll(RegExp(r'https?://[^\s<>]+', caseSensitive: false), '[url]')
      .replaceAll(RegExp(r'Bearer\s+[^\s,;]+', caseSensitive: false),
          'Bearer [redacted]')
      .replaceAll(
          RegExp(r'\beyJ[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+\b'),
          '[token]')
      .replaceAll(
          RegExp(
              r'''\b(password|authorization|cookie|secret|api[_-]?key|access_token|refresh_token|nonce|pin)\b["']?\s*[:=]\s*["']?[^\s,;"'}]+''',
              caseSensitive: false),
          '[credential redacted]')
      .replaceAll(RegExp(r'[\w.+-]+@[\w.-]+\.[A-Za-z]{2,}'), '[email]')
      .replaceAll(RegExp(r'\+?\d[\d ()-]{7,}\d'), '[number]');
  return text.length > limit ? text.substring(0, limit) : text;
}

/// Small synchronous crash spool in the app's private support directory.
/// Never uses the login client, authentication tokens or account storage.
class CrashReportQueue {
  final File file;
  final http.Client transport;
  final Uri endpoint;
  final Map<String, dynamic> metadata;
  final _reports = <Map<String, dynamic>>[];
  String installationId = const Uuid().v4();
  bool _sending = false;
  CrashReportQueue(
      {required this.file,
      required this.transport,
      required this.endpoint,
      required this.metadata}) {
    // A process can die between flushing the temporary file and renaming it.
    // Prefer a complete temporary snapshot; fall back to the committed file.
    for (final candidate in [File('${file.path}.tmp'), file]) {
      try {
        if (!candidate.existsSync()) continue;
        final data = jsonDecode(candidate.readAsStringSync());
        final restored = <Map<String, dynamic>>[];
        for (final item in (data['reports'] as List).take(50)) {
          if (item is Map && item['id'] is String) restored.add(Map<String, dynamic>.from(item));
        }
        if (data['installation_id'] is String) installationId = data['installation_id'];
        _reports.addAll(restored);
        break;
      } catch (_) {/* Try the last committed diagnostic snapshot instead. */}
    }
  }

  int get pending => _reports.length;
  void _save() {
    final temporary = File('${file.path}.tmp');
    temporary.writeAsStringSync(
        jsonEncode({'installation_id': installationId, 'reports': _reports}),
        flush: true);
    temporary.renameSync(file.path);
  }

  void add(Map<String, dynamic> value) {
    final report = <String, dynamic>{...metadata, ...value};
    report['id'] ??= const Uuid().v4();
    report['installation_id'] = installationId;
    report['occurred_at'] ??= DateTime.now().toUtc().toIso8601String();
    report['message'] = diagnosticText(report['message'] ?? '');
    report['stack'] = diagnosticText(report['stack'] ?? '', 10000);
    if (_reports.any((r) => r['id'] == report['id'])) return;
    if (_reports.length >= 50) {
      final nonFatal = _reports.indexWhere((r) => r['fatal'] != true);
      _reports.removeAt(nonFatal < 0 ? 0 : nonFatal);
    }
    _reports.add(report);
    _save();
  }

  Future<void> flush() async {
    if (_sending) return;
    _sending = true;
    try {
      while (_reports.isNotEmpty) {
        final current = _reports.first;
        final response = await transport
            .post(endpoint,
                headers: {
                  'content-type': 'application/json',
                  'x-joba-client': 'native-diagnostics-v1'
                },
                body: jsonEncode(current))
            .timeout(const Duration(seconds: 8));
        var accepted = false;
        if (response.statusCode >= 200 && response.statusCode < 300) {
          final result = jsonDecode(response.body)['data'];
          accepted = result is Map &&
              result['accepted'] == true &&
              result['id'] == current['id'];
        }
        // A permanent validation rejection must not block subsequent reports.
        if (!accepted && ![400, 413].contains(response.statusCode)) break;
        _reports.removeWhere((r) => r['id'] == current['id']);
        _save();
      }
    } catch (_) {
      /* Keep the same report IDs for a later idempotent retry. */
    } finally {
      _sending = false;
    }
  }

  void close() => transport.close();
}
