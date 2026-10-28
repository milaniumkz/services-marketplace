import 'push_prompt_store.dart'
    if (dart.library.js_interop) 'push_prompt_store_web.dart' as store;

class PushPromptPreferences {
  final DateTime? Function() read;
  final void Function(DateTime) write;
  PushPromptPreferences(
      {DateTime? Function()? read, void Function(DateTime)? write})
      : read = read ?? store.readPushPromptUntil,
        write = write ?? store.writePushPromptUntil;
}
