import 'dart:convert';
import 'package:flutter/material.dart';
import '../core/api.dart';
import '../core/photo_picker.dart';

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

  Future<void> run(Future<void> Function() action) async {
    if (busy) return;
    final generation = widget.api.sessionGeneration;
    setState(() {
      busy = true;
      error = null;
    });
    try {
      await action();
    } catch (e) {
      if (mounted && generation == widget.api.sessionGeneration)
        setState(() => error = e is ApiException
            ? e.message
            : 'Не удалось выполнить действие. Повторите попытку.');
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> load() => run(() async {
        final data = await widget.api.request('/me/face-recovery') as Json;
        if (mounted) setState(() => settings = data);
      });
  Future<void> capture() => run(() async {
        final generation = widget.api.sessionGeneration;
        final image = await (widget.capturePhoto?.call(context) ??
            choosePhoto(context, selfie: true));
        if (!mounted ||
            image == null ||
            generation != widget.api.sessionGeneration) return;
        final data = await widget.api.request(
            recovering ? '/auth/face-recovery/verify' : '/me/face-recovery',
            method: 'POST',
            authenticated: !recovering,
            body: {
              if (recovering) ...widget.challenge!,
              'photo': base64Encode(image.bytes),
              if (!recovering) 'consent': consent,
              if (!recovering) 'current_password': password.text,
            }) as Json;
        if (!mounted || generation != widget.api.sessionGeneration) return;
        if (recovering) {
          if (data['verified'] != true) {
            setState(() => error = data['message'] as String? ??
                'Лицо не совпало. Повторите снимок.');
            return;
          }
          setState(() => resetToken = data['reset_token'] as String);
        } else {
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
  Widget build(BuildContext context) =>
      ListView(padding: const EdgeInsets.all(20), children: [
        Icon(resetToken != null ? Icons.lock_reset : Icons.face_outlined,
            size: 68, color: const Color(0xff245bdb)),
        const SizedBox(height: 20),
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
                : 'Сохраните шаблон лица для восстановления пароля. Это отдельная настройка: проверка документов и биометрия устройства не изменятся.'),
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
                  child:
                      Text(error!, style: const TextStyle(color: Colors.red)))),
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
          if (settings!['enrolled'] == true)
            const Text(
                'Шаблон лица уже сохранён. Можно заменить его новым снимком или удалить.'),
          if (settings!['can_enroll_without_password'] != true)
            field(password, 'Текущий пароль'),
          CheckboxListTile(
              contentPadding: EdgeInsets.zero,
              value: consent,
              onChanged:
                  busy ? null : (v) => setState(() => consent = v ?? false),
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
          TextButton(onPressed: load, child: const Text('Повторить загрузку')),
        if (widget.onSkip != null)
          TextButton(
              onPressed: busy ? null : widget.onSkip,
              child: Text(recovering
                  ? 'Вернуться ко входу'
                  : 'Продолжить без настройки лица')),
      ]);
}
