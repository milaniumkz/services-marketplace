import 'package:flutter/material.dart';
import 'api.dart';
import 'design_icons.dart';
import 'l10n.dart';
import 'theme.dart';

class JobaStatePanel extends StatelessWidget {
  final String title, message, icon;
  final String? primaryLabel;
  final VoidCallback? onPrimary;
  final String? secondaryLabel;
  final VoidCallback? onSecondary;
  final bool brand, destructive, busy;
  final EdgeInsets contentPadding;
  final Color iconColor;
  final Color? iconFill;
  const JobaStatePanel(
      {required this.title,
      required this.message,
      required this.icon,
      this.primaryLabel,
      this.onPrimary,
      this.secondaryLabel,
      this.onSecondary,
      this.brand = false,
      this.busy = false,
      this.contentPadding =
          const EdgeInsets.symmetric(horizontal: 23, vertical: 38),
      this.iconColor = navy,
      this.iconFill,
      this.destructive = false,
      super.key});
  @override
  Widget build(BuildContext context) => Padding(
      padding: contentPadding,
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        if (brand)
          ClipRRect(
              borderRadius: BorderRadius.circular(31),
              child: Image.asset('assets/joba-logo-original.jpeg',
                  width: 140, height: 140))
        else
          Container(
              width: 94,
              height: 94,
              decoration: BoxDecoration(
                  color: const Color(0xFFE9EFFB),
                  borderRadius: BorderRadius.circular(30)),
              child: Center(
                  child: JobaIcon(icon,
                      size: 42,
                      color: iconColor,
                      fill: iconFill,
                      strokeWidth: 1.3))),
        SizedBox(height: brand ? 24 : 23),
        Semantics(
            header: true,
            child: UiText(title,
                textAlign: TextAlign.center,
                style: const TextStyle(
                    fontSize: 25,
                    height: 1.28,
                    letterSpacing: -.9,
                    fontWeight: FontWeight.w700))),
        const SizedBox(height: 12),
        UiText(message,
            textAlign: TextAlign.center,
            style: const TextStyle(
                fontSize: 13, height: 1.55, color: Color(0xFF627187))),
        if (primaryLabel != null && onPrimary != null) ...[
          const SizedBox(height: 24),
          SizedBox(
              width: double.infinity,
              child: FilledButton(
                  onPressed: busy ? null : onPrimary,
                  style: destructive
                      ? FilledButton.styleFrom(
                          backgroundColor: const Color(0xFFFBECEC),
                          foregroundColor: const Color(0xFFB83232))
                      : null,
                  child: busy
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(
                              strokeWidth: 2, color: Colors.white))
                      : UiText(primaryLabel!))),
        ],
        if (secondaryLabel != null && onSecondary != null) ...[
          const SizedBox(height: 20),
          SizedBox(
              width: double.infinity,
              child: OutlinedButton(
                  onPressed: onSecondary, child: UiText(secondaryLabel!)))
        ]
      ]));
}

class JobaReadFailure extends StatelessWidget {
  final Object error;
  final VoidCallback onRetry;
  const JobaReadFailure(
      {required this.error, required this.onRetry, super.key});
  @override
  Widget build(BuildContext context) {
    if (error is ApiException) {
      final failure = error as ApiException;
      if (failure.status > 0 &&
          failure.status < 500 &&
          !['OFFLINE', 'TIMEOUT', 'INVALID_RESPONSE'].contains(failure.code)) {
        return Column(children: [
          Notice(errorText(context, error), error: true),
          FilledButton(onPressed: onRetry, child: const UiText('Повторить'))
        ]);
      }
    }
    final offline =
        error is ApiException && (error as ApiException).code == 'OFFLINE';
    return JobaStatePanel(
        title: offline ? 'Вы пока не в сети' : 'Попробуем ещё раз?',
        message: offline
            ? 'Проверьте интернет и повторите запрос.'
            : 'Не получилось получить данные. Можно повторить запрос.',
        icon: offline ? 'wifi' : 'retry',
        primaryLabel: 'Повторить',
        onPrimary: onRetry);
  }
}

class JobaSearchSkeleton extends StatelessWidget {
  const JobaSearchSkeleton({super.key});
  Widget bar({double? width, double height = 16}) => Container(
      width: width,
      height: height,
      margin: const EdgeInsets.symmetric(vertical: 10),
      decoration: BoxDecoration(
          color: const Color(0xFFE9EEF5),
          borderRadius: BorderRadius.circular(8)));
  @override
  Widget build(BuildContext context) => Semantics(
      liveRegion: true,
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const UiText('Загружаем специалистов…',
            style: TextStyle(fontSize: 12, color: Color(0xFF627187))),
        ExcludeSemantics(
            child: Column(children: [
          for (var i = 0; i < 3; i++)
            Container(
                margin: const EdgeInsets.only(top: 16),
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                    color: Colors.white,
                    border: Border.all(color: line),
                    borderRadius: BorderRadius.circular(16)),
                child: Column(children: [
                  Row(children: [
                    bar(width: 52, height: 52),
                    const SizedBox(width: 10),
                    Expanded(
                        child: LayoutBuilder(
                            builder: (context, constraints) =>
                                Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      bar(width: constraints.maxWidth * .7),
                                      bar(width: constraints.maxWidth * .5)
                                    ])))
                  ]),
                  bar(),
                  Align(
                      alignment: Alignment.centerLeft,
                      child:
                          FractionallySizedBox(widthFactor: .8, child: bar()))
                ]))
        ]))
      ]));
}
