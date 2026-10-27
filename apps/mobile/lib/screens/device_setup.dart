import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import '../core/design_icons.dart';
import '../core/design_states.dart';
import '../core/l10n.dart';
import '../core/theme.dart';

class PinSetup extends StatefulWidget {
  final Future<void> Function(String pin, bool biometry) onSave;
  final Future<void> Function() onPassword;
  final bool showBiometry;
  const PinSetup({required this.onSave, required this.onPassword, this.showBiometry = true, super.key});
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
      setState(() {
        input.clear();
        error = Exception('PIN не совпадает');
      });
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

  void digit(String value) {
    if (busy || input.text.length >= 6) return;
    setState(() {
      input.text += value;
      error = null;
    });
    if (input.text.length == 6) submit();
  }

  @override
  Widget build(BuildContext context) => Column(children: [
        Expanded(
            child: SingleChildScrollView(
                padding:
                    const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                child: Center(
                    child: ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 340),
                        child: Column(children: [
                          const SizedBox(height: 12),
                          const JobaIcon('lock', size: 40),
                          const SizedBox(height: 20),
                          UiText(
                              first == null
                                  ? 'Придумайте PIN'
                                  : 'Повторите PIN',
                              textAlign: TextAlign.center,
                              style: const TextStyle(
                                  fontSize: 26, fontWeight: FontWeight.w700)),
                          const SizedBox(height: 8),
                          const UiText('6 цифр для быстрого входа',
                              textAlign: TextAlign.center),
                          const SizedBox(height: 24),
                          Semantics(
                              label: 'Введено цифр: ${input.text.length} из 6',
                              child: Row(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    for (var i = 0; i < 6; i++)
                                      Container(
                                          width: 14,
                                          height: 14,
                                          margin: const EdgeInsets.symmetric(
                                              horizontal: 8),
                                          decoration: BoxDecoration(
                                              shape: BoxShape.circle,
                                              color: i < input.text.length
                                                  ? primary
                                                  : Colors.transparent,
                                              border: Border.all(
                                                  color: primary, width: 1.5)))
                                  ])),
                          SizedBox(
                              height: 1,
                              child: Opacity(
                                  opacity: .01,
                                  child: TextField(
                                      key: const ValueKey('secure-pin-input'),
                                      controller: input,
                                      focusNode: focus,
                                      enabled: !busy,
                                      obscureText: true,
                                      keyboardType: TextInputType.none,
                                      autocorrect: false,
                                      enableSuggestions: false,
                                      inputFormatters: [
                                        FilteringTextInputFormatter.digitsOnly,
                                        LengthLimitingTextInputFormatter(6)
                                      ],
                                      decoration: null,
                                      onChanged: (_) =>
                                          setState(() => error = null),
                                      onSubmitted: (_) => submit()))),
                          if (error != null)
                            Padding(
                                padding: const EdgeInsets.only(top: 12),
                                child: Notice(
                                    error
                                            .toString()
                                            .contains('PIN не совпадает')
                                        ? localize(context, 'PIN не совпадает')
                                        : errorText(context, error!),
                                    error: true)),
                          const SizedBox(height: 20),
                          for (final row in [
                            ['1', '2', '3'],
                            ['4', '5', '6'],
                            ['7', '8', '9'],
                            ['', '0', 'delete']
                          ])
                            Padding(
                                padding: const EdgeInsets.only(bottom: 8),
                                child: Row(children: [
                                  for (final key in row)
                                    Expanded(
                                        child: Padding(
                                            padding: const EdgeInsets.symmetric(
                                                horizontal: 6),
                                            child: key.isEmpty
                                                ? const SizedBox(height: 62)
                                                : SizedBox(
                                                    height: 62,
                                                    child: TextButton(
                                                        style: TextButton.styleFrom(
                                                            backgroundColor:
                                                                Colors.white,
                                                            foregroundColor:
                                                                primary,
                                                            shape: RoundedRectangleBorder(
                                                                borderRadius:
                                                                    BorderRadius.circular(
                                                                        18))),
                                                        onPressed: busy
                                                            ? null
                                                            : () => key ==
                                                                    'delete'
                                                                ? setState(() {
                                                                    if (input
                                                                        .text
                                                                        .isNotEmpty)
                                                                      input.text = input
                                                                          .text
                                                                          .substring(
                                                                              0,
                                                                              input.text.length - 1);
                                                                    error =
                                                                        null;
                                                                  })
                                                                : digit(key),
                                                        child: key == 'delete'
                                                            ? const Icon(Icons.backspace_outlined,
                                                                semanticLabel:
                                                                    'Удалить цифру')
                                                            : Text(key,
                                                                style: const TextStyle(
                                                                    fontSize:
                                                                        28,
                                                                    fontWeight:
                                                                        FontWeight
                                                                            .w500))))))
                                ])),
                          if (widget.showBiometry) SwitchListTile(
                              contentPadding: EdgeInsets.zero,
                              title: const UiText('Биометрия'),
                              subtitle: const UiText('Дополнительно к PIN'),
                              value: bio,
                              onChanged:
                                  busy ? null : (v) => setState(() => bio = v)),
                          TextButton(
                              onPressed: busy
                                  ? null
                                  : () async {
                                      setState(() {
                                        busy = true;
                                        error = null;
                                      });
                                      try {
                                        await widget.onPassword();
                                      } catch (e) {
                                        if (mounted) setState(() => error = e);
                                      } finally {
                                        if (mounted)
                                          setState(() => busy = false);
                                      }
                                    },
                              child: const UiText('Вводить номер и пароль')),
                        ]))))),
        SafeArea(
            top: false,
            child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 8, 20, 8),
                child: SizedBox(
                    width: double.infinity,
                    child: FilledButton(
                        onPressed:
                            busy || input.text.length != 6 ? null : submit,
                        child: UiText(busy
                            ? 'Сохранение…'
                            : first == null
                                ? 'Подтвердить PIN'
                                : 'Сохранить PIN')))))
      ]);
}

class BiometrySetup extends StatefulWidget {
  final Future<void> Function() onEnable;
  final VoidCallback onPin;
  final Future<void> Function()? onContinue;
  const BiometrySetup({required this.onEnable, required this.onPin, this.onContinue, super.key});
  @override
  State<BiometrySetup> createState() => _BiometrySetupState();
}

class _BiometrySetupState extends State<BiometrySetup> {
  bool busy = false;
  Object? error;
  Future<void> continueWithPin() async {
    if (busy) return;
    if (widget.onContinue == null) { widget.onPin(); return; }
    setState(() { busy = true; error = null; });
    try { await widget.onContinue!(); }
    catch (e) { if (mounted) setState(() => error = e); }
    finally { if (mounted) setState(() => busy = false); }
  }
  @override
  Widget build(BuildContext context) =>
      ListView(padding: const EdgeInsets.all(20), children: [
        JobaStatePanel(
            icon: 'face',
            title: kIsWeb ? 'PIN сохранён' : error == null
                ? 'Быстрый вход\nпо биометрии'
                : 'Используйте PIN',
            message: kIsWeb
                ? 'В браузере используйте PIN. Touch ID и Face ID доступны в мобильном приложении на поддерживаемых устройствах.'
                : error == null
                ? 'Биометрия открывает только сохранённую сессию на этом устройстве. Для нового устройства нужен номер и пароль.'
                : 'Биометрия сейчас недоступна. Используйте PIN или войдите номером и паролем.',
            primaryLabel: kIsWeb ? 'Продолжить с PIN' : error == null ? 'Включить биометрию' : 'Продолжить с PIN',
            busy: busy,
            onPrimary: kIsWeb || error != null
                ? continueWithPin
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
            secondaryLabel: !kIsWeb && error == null ? 'Использовать PIN' : null,
            onSecondary: continueWithPin)
      ]);
}
