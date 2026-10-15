import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../core/design_icons.dart';
import '../core/design_states.dart';
import '../core/l10n.dart';
import '../core/theme.dart';

class PinSetup extends StatefulWidget {
  final Future<void> Function(String pin, bool biometry) onSave;
  final Future<void> Function() onPassword;
  const PinSetup({required this.onSave, required this.onPassword, super.key});
  @override
  State<PinSetup> createState() => _PinSetupState();
}

class _PinSetupState extends State<PinSetup> {
  final input = TextEditingController();
  final focus = FocusNode();
  String? first;
  bool bio = false, busy = false;
  Object? error;
  @override
  void dispose() {
    input.dispose();
    focus.dispose();
    first = null;
    super.dispose();
  }

  Future<void> submit() async {
    if (busy || input.text.length != 6) return;
    if (first == null) {
      setState(() {
        first = input.text;
        input.clear();
        error = null;
      });
      focus.requestFocus();
      return;
    }
    if (first != input.text) {
      setState(() => error = Exception('PIN не совпадает'));
      return;
    }
    setState(() {
      busy = true;
      error = null;
    });
    try {
      await widget.onSave(input.text, bio);
    } catch (e) {
      if (mounted) setState(() => error = e);
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => Column(children: [
        Expanded(
            child: ListView(padding: const EdgeInsets.all(20), children: [
          Padding(
              padding: const EdgeInsets.fromLTRB(23, 16, 23, 10),
              child: Column(children: [
                Container(
                    width: 94,
                    height: 94,
                    decoration: BoxDecoration(
                        color: const Color(0xFFE9EFFB),
                        borderRadius: BorderRadius.circular(30)),
                    child: const Center(
                        child: JobaIcon('lock', size: 42, strokeWidth: 1.3))),
                const SizedBox(height: 23),
                UiText(first == null ? 'Придумайте PIN' : 'Повторите PIN',
                    style: const TextStyle(
                        fontSize: 25,
                        fontWeight: FontWeight.w700,
                        letterSpacing: -.9)),
                const SizedBox(height: 12),
                const UiText(
                    '6 цифр для быстрого входа на этом устройстве. PIN не отправляется на сервер.',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                        fontSize: 13, color: Color(0xFF627187), height: 1.55))
              ])),
          const SizedBox(height: 28),
          SizedBox(
              height: 40,
              child: Stack(alignment: Alignment.center, children: [
                Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                  for (var i = 0; i < 6; i++)
                    Container(
                        margin: const EdgeInsets.symmetric(horizontal: 7),
                        width: 12,
                        height: 12,
                        decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: i < input.text.length
                                ? primary
                                : Colors.transparent,
                            border: Border.all(color: primary)))
                ]),
                TextField(
                    key: const ValueKey('secure-pin-input'),
                    controller: input,
                    focusNode: focus,
                    enabled: !busy,
                    obscureText: true,
                    enableSuggestions: false,
                    autocorrect: false,
                    keyboardType: TextInputType.number,
                    inputFormatters: [
                      FilteringTextInputFormatter.digitsOnly,
                      LengthLimitingTextInputFormatter(6)
                    ],
                    style:
                        const TextStyle(color: Colors.transparent, fontSize: 1),
                    showCursor: false,
                    decoration: InputDecoration(
                        border: InputBorder.none,
                        enabledBorder: InputBorder.none,
                        focusedBorder: InputBorder.none,
                        fillColor: Colors.transparent,
                        filled: true,
                        counterText: '',
                        contentPadding: EdgeInsets.zero,
                        labelText: localize(context,
                            first == null ? 'Придумайте PIN' : 'Повторите PIN'),
                        floatingLabelBehavior: FloatingLabelBehavior.never),
                    onChanged: (_) => setState(() => error = null))
              ])),
          const SizedBox(height: 18),
          Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                  color: Colors.white,
                  border: Border.all(color: line),
                  borderRadius: BorderRadius.circular(16)),
              child: Row(children: [
                const Expanded(
                    child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                      UiText('Биометрия',
                          style: TextStyle(
                              fontWeight: FontWeight.w700, fontSize: 16)),
                      SizedBox(height: 4),
                      UiText('Дополнительно к PIN',
                          style:
                              TextStyle(fontSize: 12, color: Color(0xFF627187)))
                    ])),
                Switch(
                    value: bio,
                    onChanged: busy ? null : (v) => setState(() => bio = v))
              ])),
          const Notice(
              'Если безопасная локальная защита недоступна, при открытии потребуется номер и пароль.',
              margin: EdgeInsets.only(top: 20)),
          if (error != null)
            Notice(
                error.toString().contains('PIN не совпадает')
                    ? localize(context, 'PIN не совпадает')
                    : errorText(context, error!),
                error: true),
          TextButton(
              onPressed: busy
                  ? null
                  : () async {
                      setState(() => busy = true);
                      try {
                        await widget.onPassword();
                      } catch (e) {
                        if (mounted) setState(() => error = e);
                      } finally {
                        if (mounted) setState(() => busy = false);
                      }
                    },
              child: const UiText('Вводить номер и пароль'))
        ])),
        Container(
            decoration: const BoxDecoration(
                color: Colors.white,
                border: Border(top: BorderSide(color: line))),
            child: SafeArea(
                top: false,
                child: Padding(
                    padding: const EdgeInsets.fromLTRB(20, 12, 20, 4),
                    child: FilledButton(
                        onPressed:
                            busy || input.text.length != 6 ? null : submit,
                        child: UiText(first == null
                            ? 'Подтвердить PIN'
                            : 'Сохранить PIN')))))
      ]);
}

class BiometrySetup extends StatefulWidget {
  final Future<void> Function() onEnable;
  final VoidCallback onPin;
  const BiometrySetup({required this.onEnable, required this.onPin, super.key});
  @override
  State<BiometrySetup> createState() => _BiometrySetupState();
}

class _BiometrySetupState extends State<BiometrySetup> {
  bool busy = false;
  Object? error;
  @override
  Widget build(BuildContext context) =>
      ListView(padding: const EdgeInsets.all(20), children: [
        JobaStatePanel(
            icon: 'face',
            title: error == null
                ? 'Быстрый вход\nпо биометрии'
                : 'Используйте PIN',
            message: error == null
                ? 'Биометрия открывает только сохранённую сессию на этом устройстве. Для нового устройства нужен номер и пароль.'
                : 'Биометрия сейчас недоступна. Используйте PIN или войдите номером и паролем.',
            primaryLabel: error == null ? 'Включить биометрию' : 'Ввести PIN',
            busy: busy,
            onPrimary: error != null
                ? widget.onPin
                : () async {
                    setState(() => busy = true);
                    try {
                      await widget.onEnable();
                    } catch (e) {
                      if (mounted) setState(() => error = e);
                    } finally {
                      if (mounted) setState(() => busy = false);
                    }
                  },
            secondaryLabel: error == null ? 'Использовать PIN' : null,
            onSecondary: widget.onPin)
      ]);
}
