import 'dart:async';
import 'dart:io';
import 'package:firebase_crashlytics/firebase_crashlytics.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import 'crash_report_queue.dart';

class NativeDiagnostics with WidgetsBindingObserver {
  static bool enabled = false, firebaseReady = false;
  static CrashReportQueue? _queue;
  static final _observer = NativeDiagnostics();
  static final _breadcrumbs = <Map<String, String>>[];
  static String _screen = 'startup';
  static Timer? _retry;
  static const _channel = MethodChannel('joba.runtime');
  static Future<void> initialize({required bool collect}) async {
    enabled = collect;
    if (!enabled || (!Platform.isAndroid && !Platform.isIOS)) return;
    try {
      final directory = await getApplicationSupportDirectory()
          .timeout(const Duration(seconds: 2));
      await directory.create(recursive: true);
      var metadata = <String, dynamic>{
        'platform': Platform.isAndroid ? 'android' : 'ios',
        'app_version': 'unknown',
        'build': 'unknown',
        'os_version': diagnosticText(Platform.operatingSystemVersion, 80)
      };
      if (Platform.isAndroid) {
        try {
          metadata.addAll(Map<String, dynamic>.from(await _channel
                  .invokeMapMethod<String, dynamic>('info')
                  .timeout(const Duration(seconds: 2)) ??
              {}));
        } catch (_) {}
      }
      _queue = CrashReportQueue(
          file: File('${directory.path}/joba-crash-reports.json'),
          transport: http.Client(),
          endpoint: Uri.parse(
              '${const String.fromEnvironment('JOBA_API_URL', defaultValue: 'https://joba.com.kz')}/api/v1/public/mobile-crashes'),
          metadata: metadata);
      WidgetsBinding.instance.addObserver(_observer);
      if (Platform.isAndroid) await _collectAndroid();
      _retry?.cancel();
      _retry = Timer.periodic(const Duration(minutes: 1), (_) => _flush());
      _flush();
    } catch (_) {/* Logging cannot prevent startup, login or rendering. */}
  }

  static Future<void> _collectAndroid() async {
    try {
      final native = await _channel
              .invokeListMethod<dynamic>('pendingCrashes')
              .timeout(const Duration(seconds: 2)) ??
          [];
      for (final item in native) {
        final report = Map<String, dynamic>.from(item);
        _queue!.add(report);
        await _channel.invokeMethod('ackCrash', {'id': report['id']});
      }
      final exits = await _channel
              .invokeListMethod<dynamic>('previousExits')
              .timeout(const Duration(seconds: 2)) ??
          [];
      // Acknowledge older exits first so a crash during transfer cannot hide
      // earlier, not-yet-persisted entries behind the newest timestamp.
      exits.sort((a,b)=>(a['timestamp'] as int).compareTo(b['timestamp'] as int));
      for (final item in exits) {
        final exit = Map<String, dynamic>.from(item);
        final timestamp = exit.remove('timestamp');
        _queue!.add({
          ...exit,
          'kind': 'android_exit',
          'fatal': true,
          'occurred_at':
              DateTime.fromMillisecondsSinceEpoch(timestamp as int, isUtc: true)
                  .toIso8601String(),
          'screen': exit['screen'] ?? 'unknown',
          'message':
              'Android process exit: reason=${exit['reason']}, status=${exit['status']}',
          'stack': exit['stack'] ?? ''
        });
        await _channel.invokeMethod('ackExit', {'timestamp': timestamp});
      }
    } catch (_) {/* Native spool remains available until persisted locally. */}
  }

  static void _flush() {
    final queue = _queue;
    if (queue != null) unawaited(queue.flush());
  }

  static void screen(String route) {
    if (!enabled) return;
    _screen = route;
    _breadcrumbs
        .add({'screen': route, 'at': DateTime.now().toUtc().toIso8601String()});
    if (_breadcrumbs.length > 20) _breadcrumbs.removeAt(0);
    if (Platform.isAndroid)
      unawaited(_channel
          .invokeMethod('screen', {'screen': route}).catchError((Object _) {}));
    if (firebaseReady)
      unawaited(FirebaseCrashlytics.instance
          .setCustomKey('screen', route)
          .catchError((Object _) {}));
  }

  static void installNativeHandler() {
    if (enabled && Platform.isAndroid)
      unawaited(_channel
          .invokeMethod('installCrashHandler')
          .catchError((Object _) {}));
  }

  static void record(Object error, StackTrace? stack,
      {String kind = 'flutter', bool fatal = true}) {
    if (!enabled) return;
    try {
      _queue?.add({
        'kind': kind,
        'fatal': fatal,
        'screen': _screen,
        'breadcrumbs': List.of(_breadcrumbs),
        'message': '${error.runtimeType}: ${diagnosticText(error)}',
        'stack': diagnosticText(stack ?? '', 10000)
      });
      _flush();
    } catch (_) {}
    if (firebaseReady)
      unawaited(FirebaseCrashlytics.instance
          .recordError(error, stack, fatal: fatal)
          .catchError((Object _) {}));
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _flush();
  }
}
