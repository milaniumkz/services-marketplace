import 'dart:async';
import 'package:firebase_crashlytics/firebase_crashlytics.dart';
import 'package:flutter/services.dart';

// No user identifiers, coordinates, messages or form contents are recorded.
class NativeDiagnostics {
  static bool enabled = false;
  static void screen(String route) {
    if (!enabled) return;
    unawaited(FirebaseCrashlytics.instance
        .setCustomKey('screen', route)
        .catchError((Object _) {}));
  }

  static Future<void> previousExits() async {
    if (!enabled) return;
    try {
      final exits = await const MethodChannel('joba.runtime')
          .invokeListMethod<dynamic>('previousExits')
          .timeout(const Duration(seconds: 2));
      for (final exit in exits ?? []) {
        await FirebaseCrashlytics.instance.recordError(
            StateError(
                'Android previous process exit: reason=${exit['reason']}, status=${exit['status']}, pss_kb=${exit['pss_kb']}, rss_kb=${exit['rss_kb']}'),
            null,
            fatal: false,
            reason: 'Android ApplicationExitInfo (previous run)');
      }
    } catch (_) {/* Diagnostics never affect launch or authentication. */}
  }
}
