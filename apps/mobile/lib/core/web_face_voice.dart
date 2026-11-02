import 'dart:js_interop';
import 'package:web/web.dart' as web;

/// Uses voices installed in this browser; a female Russian voice is preferred.
class FaceVoice {
  void Function()? onUnavailable;
  int _epoch = 0;
  bool enabled = true;
  bool available = true;
  void speak(String text) {
    if (!enabled || !available) return;
    final epoch = ++_epoch;
    try {
      final synth = web.window.speechSynthesis;
      final voices = synth.getVoices().toDart;
      web.SpeechSynthesisVoice? selected;
      for (final voice in voices) {
        if (!voice.lang.toLowerCase().startsWith('ru')) continue;
        selected ??= voice;
        if (RegExp(
                r'female|жен|irina|milena|alena|alyona|svetlana|tatyana|tatiana|maria|anna|екатерин|ирина|алёна|милена|светлана',
                caseSensitive: false)
            .hasMatch(voice.name)) {
          selected = voice;
          break;
        }
      }
      final utterance = web.SpeechSynthesisUtterance(text)
        ..lang = 'ru-RU'
        ..rate = 1.15
        ..pitch = 1.02
        ..volume = 0.65;
      if (selected != null) utterance.voice = selected;
      utterance.onerror = ((web.SpeechSynthesisErrorEvent event) {
        if (epoch != _epoch ||
            event.error == 'canceled' ||
            event.error == 'interrupted') return;
        available = false;
        onUnavailable?.call();
      }).toJS;
      synth.cancel();
      synth.resume();
      synth.speak(utterance);
    } catch (_) {
      available = false;
      onUnavailable?.call();
    }
  }

  void stop() {
    _epoch++;
    try {
      web.window.speechSynthesis.cancel();
    } catch (_) {}
  }
}
