import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../core/design_icons.dart';
import '../core/design_widgets.dart' show muted;
import '../core/l10n.dart';
import '../core/theme.dart';

class UnlockKeypad extends StatefulWidget {
  final String name;
  final bool busy;
  final Future<int?> Function() loadLength;
  final Future<void> Function(String pin) onPin;
  final Future<void> Function() onBiometry, onPassword;
  const UnlockKeypad(
      {required this.name,
      required this.busy,
      required this.loadLength,
      required this.onPin,
      required this.onBiometry,
      required this.onPassword,
      super.key});
  @override
  State<UnlockKeypad> createState() => _UnlockKeypadState();
}

class _UnlockKeypadState extends State<UnlockKeypad> {
  String digits = '';
  int? length;
  bool ready = false, sending = false;
  Object? error;
  bool get blocked => widget.busy || sending || !ready;
  @override
  void initState() {
    super.initState();
    load();
  }

  Future<void> load() async {
    try {
      final value = await widget.loadLength();
      if (mounted)
        setState(() {
          length = value;
          ready = true;
        });
    } catch (e) {
      if (mounted) setState(() => error = e);
    }
  }

  Future<void> run(Future<void> Function() action) async {
    if (sending || widget.busy) return;
    setState(() {
      sending = true;
      error = null;
    });
    try {
      await action();
    } catch (e) {
      if (mounted) setState(() => error = e);
    } finally {
      if (mounted)
        setState(() {
          sending = false;
          digits = '';
        });
    }
  }

  void digit(String value) {
    if (blocked || digits.length >= (length ?? 8)) return;
    setState(() {
      digits += value;
      error = null;
    });
    if (length != null && digits.length == length) submit();
  }

  void remove() {
    if (blocked || digits.isEmpty) return;
    setState(() {
      digits = digits.substring(0, digits.length - 1);
      error = null;
    });
  }

  void submit() {
    if (blocked ||
        (length == null ? digits.length < 6 : digits.length != length)) return;
    final pin = digits;
    run(() => widget.onPin(pin));
  }

  Widget keyButton(
          String id, Widget child, VoidCallback callback, String label) =>
      Center(
          child: SizedBox(
              width: 64,
              height: 60 *
                  (MediaQuery.textScalerOf(context).scale(26) / 26).clamp(1, 3),
              child: Semantics(
                  key: ValueKey('unlock-semantics-$id'),
                  onTap: blocked ? null : callback,
                  label: label,
                  button: true,
                  enabled: !blocked,
                  child: ExcludeSemantics(
                      child: Material(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(32),
                          clipBehavior: Clip.antiAlias,
                          child: InkWell(
                              key: ValueKey('unlock-key-$id'),
                              onTap: blocked ? null : callback,
                              child: Center(child: child)))))));
  Widget number(String value) => keyButton(
      value,
      Text(value, style: const TextStyle(fontSize: 26, height: 1.45)),
      () => digit(value),
      value);
  @override
  Widget build(BuildContext context) {
    final words = widget.name
        .trim()
        .split(RegExp(r'\s+'))
        .where((s) => s.isNotEmpty)
        .toList();
    final initials =
        words.take(2).map((s) => s.characters.first).join().toUpperCase();
    return Focus(
        autofocus: true,
        onKeyEvent: (node, event) {
          if (event is! KeyDownEvent) return KeyEventResult.ignored;
          if (RegExp(r'^\d$').hasMatch(event.character ?? '')) {
            digit(event.character!);
            return KeyEventResult.handled;
          }
          if (event.logicalKey == LogicalKeyboardKey.backspace) {
            remove();
            return KeyEventResult.handled;
          }
          if (event.logicalKey == LogicalKeyboardKey.enter ||
              event.logicalKey == LogicalKeyboardKey.numpadEnter) {
            if (!node.hasPrimaryFocus) return KeyEventResult.ignored;
            submit();
            return KeyEventResult.handled;
          }
          return KeyEventResult.ignored;
        },
        child: ListView(
            padding: const EdgeInsets.fromLTRB(20, 40, 20, 20),
            children: [
              Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    const Text('JOBA',
                        style: TextStyle(
                            fontSize: 25,
                            height: 1.45,
                            fontWeight: FontWeight.w700,
                            letterSpacing: -1.8,
                            color: primary)),
                    Padding(
                        padding: const EdgeInsets.only(left: 2, bottom: 11),
                        child: Container(
                            width: 7,
                            height: 7,
                            decoration: const BoxDecoration(
                                color: Color(0xFFFFD65A),
                                shape: BoxShape.circle))),
                  ]),
              const SizedBox(height: 26),
              Center(
                  child: Container(
                      width: 82,
                      height: 82,
                      decoration: BoxDecoration(
                          color: const Color(0xFFE6E1F0),
                          border: Border.all(color: Colors.white, width: 4),
                          borderRadius: BorderRadius.circular(24)),
                      clipBehavior: Clip.antiAlias,
                      child: Stack(children: [
                        Center(
                            child: Text(initials.isEmpty ? 'J' : initials,
                                style: const TextStyle(
                                    fontSize: 27,
                                    fontWeight: FontWeight.w700,
                                    color: Color(0xFF6F608A)))),
                        Positioned(
                            right: -35,
                            bottom: -25,
                            child: Container(
                                width: 70,
                                height: 70,
                                decoration: BoxDecoration(
                                    shape: BoxShape.circle,
                                    border: Border.all(
                                        color: const Color(0x65FFFFFF)))))
                      ]))),
              const SizedBox(height: 20),
              Text(
                  '${localize(context, 'С возвращением')}${words.isEmpty ? '' : ',\n${words.first}'}',
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                      fontSize: 25,
                      height: 1.4,
                      letterSpacing: -.9,
                      fontWeight: FontWeight.w700)),
              const SizedBox(height: 12),
              const UiText('Введите PIN приложения',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 12, height: 1.5, color: muted)),
              if (error != null)
                Notice(errorText(context, error!), error: true),
              const SizedBox(height: 28),
              Semantics(
                  label: localize(context, 'Введено цифр: {count}')
                      .replaceAll('{count}', '${digits.length}'),
                  liveRegion: true,
                  child: ExcludeSemantics(
                      child: SizedBox(
                          height: 12,
                          child: Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                for (var i = 0;
                                    i <
                                        (length ??
                                            (digits.length > 6
                                                ? digits.length
                                                : 6));
                                    i++)
                                  Padding(
                                      padding: EdgeInsets.only(
                                          left: i == 0 ? 0 : 14),
                                      child: Container(
                                          key: ValueKey('unlock-dot-$i'),
                                          width: 12,
                                          height: 12,
                                          decoration: BoxDecoration(
                                              shape: BoxShape.circle,
                                              color: i < digits.length
                                                  ? primary
                                                  : Colors.transparent,
                                              border: Border.all(
                                                  color: i < digits.length
                                                      ? primary
                                                      : const Color(
                                                          0xFFBBC8DE))))),
                              ])))),
              const SizedBox(height: 28),
              Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  child: Transform.translate(
                      offset: const Offset(16, 0),
                      child: Column(children: [
                        for (var row = 0; row < 4; row++) ...[
                          if (row > 0) const SizedBox(height: 10),
                          Row(children: [
                            for (var column = 0; column < 3; column++) ...[
                              if (column > 0) const SizedBox(width: 12),
                              Expanded(
                                  child: row < 3
                                      ? number('${row * 3 + column + 1}')
                                      : column == 0
                                          ? keyButton(
                                              'biometry',
                                              const JobaIcon('face'),
                                              () => run(widget.onBiometry),
                                              localize(context,
                                                  'Разблокировать биометрией'))
                                          : column == 1
                                              ? number('0')
                                              : keyButton(
                                                  'delete',
                                                  const JobaIcon('back'),
                                                  remove,
                                                  localize(context,
                                                      'Удалить цифру'))),
                            ]
                          ]),
                        ],
                      ]))),
              if (length == null && digits.length >= 6)
                Padding(
                    padding: const EdgeInsets.only(top: 12),
                    child: FilledButton(
                        onPressed: blocked ? null : submit,
                        child: const UiText('Разблокировать'))),
              if (sending || widget.busy)
                const Padding(
                    padding: EdgeInsets.only(top: 12),
                    child: Center(
                        child: SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2)))),
              const SizedBox(height: 24),
              TextButton(
                  key: const ValueKey('unlock-password'),
                  onPressed: sending || widget.busy
                      ? null
                      : () => run(widget.onPassword),
                  style: TextButton.styleFrom(
                      minimumSize: const Size(double.infinity, 52),
                      padding: const EdgeInsets.symmetric(
                          horizontal: 18, vertical: 12)),
                  child: const UiText('Войти номером и паролем',
                      style: TextStyle(
                          fontSize: 14, fontWeight: FontWeight.w700))),
              const SizedBox(height: 8),
              const UiText('PIN действует только на этом устройстве.',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 10, height: 1.4, color: muted)),
            ]));
  }
}
