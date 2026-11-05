import 'dart:convert';
import 'package:flutter/material.dart';
import '../core/api.dart';
import '../core/photo_picker.dart';
import '../core/face_camera.dart';
import '../core/face_sequence.dart';

/// Account recovery comparison. This is deliberately not a liveness check.
class FaceAccess extends StatefulWidget {
  final JobaApi api;
  final Future<PhotoFile?> Function(BuildContext)? capturePhoto;
  final Json? challenge;
  final VoidCallback onDone;
  final VoidCallback? onSkip;
  const FaceAccess(
      {super.key,
      required this.api,
      required this.onDone,
      this.capturePhoto,
      this.challenge,
      this.onSkip});
  @override
  State<FaceAccess> createState() => _FaceAccessState();
}

class _FaceAccessState extends State<FaceAccess> {
  Json? settings;
  bool busy = false, consent = false;
  String? error, resetToken;
  final password = TextEditingController(),
      next = TextEditingController(),
      repeat = TextEditingController();
  bool get recovering => widget.challenge != null;
  @override
  void initState() {
    super.initState();
    if (!recovering) load();
  }

  @override
  void dispose() {
    password.dispose();
    next.dispose();
    repeat.dispose();
    super.dispose();
  }

  void notice(String message, {bool failure = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(message),
        backgroundColor: failure ? Colors.red.shade700 : null));
  }

  Future<void> run(Future<void> Function() action,
      {bool announceFailure = true}) async {
    if (busy) return;
    final generation = widget.api.sessionGeneration;
    setState(() {
      busy = true;
      error = null;
    });
    try {
      await action();
    } catch (e) {
      if (mounted && generation == widget.api.sessionGeneration) {
        final message = e is ApiException
            ? e.message
            : 'Не удалось выполнить действие. Повторите попытку.';
        setState(() => error = message);
        if (announceFailure) notice(message, failure: true);
      }
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> load() => run(() async {
        final data = await widget.api.request('/me/face-recovery') as Json;
        if (mounted) setState(() => settings = data);
      }, announceFailure: false);
  Future<void> capture() => run(() async {
        final generation = widget.api.sessionGeneration;
        final injected = widget.capturePhoto;
        final sequence = injected == null
            ? await captureFacePhotos(context)
            : await (() async {
                final photo = await injected(context);
                return photo == null
                    ? null
                    : FaceSequence(List.filled(faceSteps.length, photo));
              })();
        if (!mounted ||
            sequence == null ||
            generation != widget.api.sessionGeneration) return;
        final data = await widget.api.request(
            recovering ? '/auth/face-recovery/verify' : '/me/face-recovery',
            method: 'POST',
            authenticated: !recovering,
            body: {
              if (recovering) ...widget.challenge!,
              'photos': [
                for (var i = 0; i < sequence.photos.length; i++)
                  {
                    'step': faceSteps[i],
                    'photo': base64Encode(sequence.photos[i].bytes)
                  }
              ],
              if (!recovering) 'consent': consent,
              if (!recovering) 'current_password': password.text,
            }) as Json;
        if (!mounted || generation != widget.api.sessionGeneration) return;
        if (recovering) {
          if (data['verified'] != true) {
            setState(() => error = data['message'] as String? ??
                'Лицо не совпало. Повторите снимок.');
            notice(error!, failure: true);
            return;
          }
          notice('Лицо подтверждено. Можно установить новый пароль.');
          setState(() => resetToken = data['reset_token'] as String);
        } else {
          notice('Все пять кадров проверены. Шаблоны лица сохранены.');
          widget.onDone();
        }
      });
  Future<void> reset() => run(() async {
        if (next.text.length < 6 || next.text.length > 128) {
          setState(() =>
              error = 'Новый пароль должен содержать от 6 до 128 символов.');
          return;
        }
        if (next.text != repeat.text) {
          setState(() => error = 'Пароли не совпадают.');
          return;
        }
        await widget.api.request('/auth/face-recovery/reset',
            method: 'POST',
            authenticated: false,
            body: {
              'id': widget.challenge!['id'],
              'reset_token': resetToken,
              'new_password': next.text
            });
        if (mounted) widget.onDone();
      });
  Widget field(TextEditingController controller, String label) => Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: TextField(
          controller: controller,
          obscureText: true,
          autocorrect: false,
          enableSuggestions: false,
          decoration: InputDecoration(
              labelText: label, border: const OutlineInputBorder())));
  @override
  Widget build(BuildContext context) => Column(children: [
        Expanded(
            child: ListView(
                keyboardDismissBehavior:
                    ScrollViewKeyboardDismissBehavior.onDrag,
                padding: const EdgeInsets.all(20),
                children: [
              Icon(resetToken != null ? Icons.lock_reset : Icons.face_outlined,
                  size: 48, color: const Color(0xff245bdb)),
              const SizedBox(height: 12),
              Text(
                  resetToken != null
                      ? 'Установите новый пароль'
                      : recovering
                          ? 'Подтвердите личность'
                          : 'Восстановление по лицу',
                  style: Theme.of(context).textTheme.headlineSmall),
              const SizedBox(height: 12),
              Text(resetToken != null
                  ? 'Лицо совпало. После смены пароля войдите с новым паролем. Остальные сессии завершатся.'
                  : recovering
                      ? 'После двух неверных паролей можно сравнить лицо с ранее сохранённым шаблоном. Если способ не настроен, вернитесь ко входу или обратитесь в поддержку.'
                      : 'Настройте восстановление пароля по лицу. Камера сохранит пять кадров: прямо, налево, направо, моргание и улыбка. Это не заменяет проверку документов.'),
              if (resetToken == null)
                const Padding(
                    padding: EdgeInsets.symmetric(vertical: 16),
                    child: Text(
                        'Базовое сравнение без проверки живого присутствия. Фотография или видео могут пройти такую проверку.')),
              if (error != null)
                Semantics(
                    liveRegion: true,
                    child: Padding(
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        child: Text(error!,
                            style: const TextStyle(color: Colors.red)))),
              if (busy) const LinearProgressIndicator(),
              if (resetToken != null) ...[
                field(next, 'Новый пароль'),
                field(repeat, 'Повторите новый пароль'),
                FilledButton(
                    onPressed: busy ? null : reset,
                    child: const Text('Сменить пароль')),
              ] else if (recovering)
                FilledButton(
                    onPressed: busy ? null : capture,
                    child: const Text('Открыть фронтальную камеру'))
              else if (settings != null) ...[
                if (settings!['update_required'] == true)
                  const Text(
                      'Обновите прежний шаблон: теперь процедура состоит из пяти кадров.'),
                if (settings!['enrolled'] == true)
                  const Text(
                      'Шаблоны лица сохранены. Можно пройти процедуру заново или удалить их.'),
                if (settings!['can_enroll_without_password'] != true)
                  field(password, 'Текущий пароль'),
                CheckboxListTile(
                    contentPadding: EdgeInsets.zero,
                    value: consent,
                    onChanged: busy
                        ? null
                        : (v) => setState(() => consent = v ?? false),
                    title: Text(settings!['notice'] as String),
                    controlAffinity: ListTileControlAffinity.leading),
                FilledButton(
                    onPressed: busy || !consent ? null : capture,
                    child: const Text('Сохранить лицо через камеру')),
                if (settings!['enrolled'] == true)
                  OutlinedButton(
                      onPressed: busy
                          ? null
                          : () => run(() async {
                                await widget.api.request('/me/face-recovery',
                                    method: 'DELETE',
                                    body: {'current_password': password.text});
                                if (mounted) widget.onDone();
                              }),
                      child: const Text('Отключить и удалить шаблон')),
              ] else if (!busy)
                TextButton(
                    onPressed: load, child: const Text('Повторить загрузку')),
            ])),
        if (widget.onSkip != null)
          SafeArea(
              top: false,
              minimum: const EdgeInsets.fromLTRB(20, 8, 20, 12),
              child: SizedBox(
                  width: double.infinity,
                  child: TextButton(
                    style: TextButton.styleFrom(
                        minimumSize: const Size.fromHeight(48)),
                    onPressed: busy ? null : widget.onSkip,
                    child: Text(recovering
                        ? 'Вернуться ко входу'
                        : 'Продолжить без настройки лица'),
                  ))),
      ]);
}
