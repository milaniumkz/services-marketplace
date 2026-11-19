import 'package:flutter/material.dart';
import '../core/design_icons.dart';
import '../core/l10n.dart';

class PinLimit extends StatelessWidget {
  final VoidCallback onLogin, onHelp;
  const PinLimit({required this.onLogin, required this.onHelp, super.key});
  @override
  Widget build(BuildContext context) => Column(children: [
        Expanded(
            child: ListView(
                padding: const EdgeInsets.fromLTRB(43, 58, 43, 58),
                children: [
              Center(
                  child: Container(
                      width: 94,
                      height: 94,
                      decoration: BoxDecoration(
                          color: const Color(0xFFE9EFFB),
                          borderRadius: BorderRadius.circular(30)),
                      child: const Center(
                          child:
                              JobaIcon('lock', size: 42, strokeWidth: 1.3)))),
              const SizedBox(height: 23),
              Semantics(
                  header: true,
                  child: const UiText('Войдите снова',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                          fontSize: 25,
                          height: 1.28,
                          letterSpacing: -.9,
                          fontWeight: FontWeight.w700))),
              const SizedBox(height: 12),
              const UiText(
                  'После 5 неверных попыток PIN локальная разблокировка отключена для безопасности.',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                      fontSize: 13, height: 1.55, color: Color(0xFF627187))),
              const SizedBox(height: 24),
              FilledButton(
                  onPressed: onLogin,
                  child: const UiText('Войти номером и паролем')),
              const SizedBox(height: 24),
              TextButton(
                  onPressed: onHelp,
                  style: TextButton.styleFrom(
                      minimumSize: const Size(double.infinity, 52),
                      padding: const EdgeInsets.symmetric(
                          horizontal: 18, vertical: 12)),
                  child: const UiText('Помощь со входом')),
            ])),
        Container(
            height: MediaQuery.paddingOf(context).bottom, color: Colors.white),
      ]);
}
