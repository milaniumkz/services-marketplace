import 'package:web/web.dart' as web;

DateTime? _until;
const _key = 'joba.pushPrompt.deferredUntil';
DateTime? readPushPromptUntil() {
  try {
    return DateTime.tryParse(web.window.localStorage.getItem(_key) ?? '') ??
        _until;
  } catch (_) {
    return _until;
  }
}

void writePushPromptUntil(DateTime until) {
  _until = until;
  try {
    web.window.localStorage.setItem(_key, until.toUtc().toIso8601String());
  } catch (_) {/* Browser storage restrictions must not interrupt the app. */}
}
