class NativeDiagnostics {
  static bool enabled = false, firebaseReady = false;
  static Future<void> initialize({required bool collect}) async {}
  static void screen(String route) {}
  static void installNativeHandler() {}
  static void record(Object error, StackTrace? stack,
      {String kind = 'flutter', bool fatal = true}) {}
}
