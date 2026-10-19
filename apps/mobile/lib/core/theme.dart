import 'package:flutter/material.dart';
import 'l10n.dart';
import 'design_icons.dart';

const primary = Color(0xFF245BDB);
const navy = Color(0xFF172B4D);
const canvas = Color(0xFFF5F7FB);
const line = Color(0xFFE5EAF2);
const yellow = Color(0xFFFFD65A);

ThemeData jobaTheme() => ThemeData(
      useMaterial3: true,
      visualDensity: VisualDensity.standard,
      materialTapTargetSize: MaterialTapTargetSize.padded,
      fontFamily: 'Noto',
      textTheme: const TextTheme(
          bodyMedium: TextStyle(
              fontFamily: 'Noto',
              fontSize: 14,
              letterSpacing: 0,
              height: 1.55,
              color: navy),
          bodyLarge: TextStyle(
              fontFamily: 'Noto', fontSize: 16, letterSpacing: 0, color: navy)),
      dividerTheme: const DividerThemeData(color: line, thickness: 1),
      scaffoldBackgroundColor: Colors.white,
      colorScheme: ColorScheme.fromSeed(seedColor: primary)
          .copyWith(primary: primary, onSurface: navy),
      appBarTheme: const AppBarTheme(
          backgroundColor: Colors.white,
          surfaceTintColor: Colors.transparent,
          centerTitle: true,
          shape: Border(bottom: BorderSide(color: line)),
          toolbarHeight: 60,
          titleTextStyle: TextStyle(
              fontFamily: 'Noto',
              fontSize: 17,
              fontWeight: FontWeight.w700,
              color: navy,
              letterSpacing: -.3)),
      inputDecorationTheme: InputDecorationTheme(
          filled: true,
          fillColor: Colors.white,
          contentPadding:
              const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
          border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: const BorderSide(color: line)),
          enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: const BorderSide(color: line))),
      filledButtonTheme: FilledButtonThemeData(
          style: FilledButton.styleFrom(
              backgroundColor: primary,
              foregroundColor: Colors.white,
              minimumSize: const Size(double.infinity, 52),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14)),
              textStyle: const TextStyle(
                  fontFamily: 'Noto',
                  fontWeight: FontWeight.w700,
                  fontSize: 14))),
      textButtonTheme: TextButtonThemeData(
          style: TextButton.styleFrom(
              textStyle: const TextStyle(
                  fontFamily: 'Noto',
                  fontWeight: FontWeight.w700,
                  fontSize: 14,
                  letterSpacing: 0))),
      outlinedButtonTheme: OutlinedButtonThemeData(
          style: OutlinedButton.styleFrom(
              foregroundColor: navy,
              backgroundColor: Colors.white,
              textStyle: const TextStyle(
                  fontFamily: 'Noto',
                  fontWeight: FontWeight.w700,
                  fontSize: 14,
                  letterSpacing: 0),
              minimumSize: const Size(double.infinity, 52),
              side: const BorderSide(color: line),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14)))),
    );

class Heading extends StatelessWidget {
  final String title, subtitle;
  const Heading(this.title, [this.subtitle = '', Key? key]) : super(key: key);
  @override
  Widget build(BuildContext context) => Padding(
      padding: const EdgeInsets.only(bottom: 20),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(title,
            style: const TextStyle(
                fontSize: 26,
                letterSpacing: -.9,
                fontWeight: FontWeight.w700,
                height: 1.269,
                color: navy)),
        if (subtitle.isNotEmpty)
          Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(subtitle,
                  style: const TextStyle(
                      fontSize: 12,
                      letterSpacing: 0,
                      color: Color(0xFF627187),
                      height: 1.5))),
      ]));
}

class UiHeading extends StatelessWidget {
  final String title, subtitle;
  const UiHeading(this.title, [this.subtitle = '', Key? key]) : super(key: key);
  @override
  Widget build(BuildContext context) =>
      Heading(localize(context, title), localize(context, subtitle));
}

class Notice extends StatelessWidget {
  final String text;
  final bool error, warning;
  final String? icon;
  final Color? backgroundColor, textColor;
  final double iconSize;
  final EdgeInsets margin;
  const Notice(this.text,
      {this.error = false,
      this.warning = false,
      this.icon,
      this.backgroundColor,
      this.textColor,
      this.iconSize = 19,
      this.margin = const EdgeInsets.symmetric(vertical: 12),
      super.key});
  @override
  Widget build(BuildContext context) => Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
      margin: margin,
      decoration: BoxDecoration(
          color: backgroundColor ?? (error ? const Color(0xFFFFEEEE) : warning ? const Color(0xFFFFF4D4) : const Color(0xFFEAF0FC)),
          borderRadius: BorderRadius.circular(12)),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        if (icon != null) ...[
          JobaIcon(icon!,
              size: iconSize, color: error ? const Color(0xFFA02C32) : navy),
          const SizedBox(width: 10)
        ],
        Expanded(
            child: UiText(text,
                style: TextStyle(
                    color: textColor ?? (error
                        ? const Color(0xFFA02C32)
                        : warning ? const Color(0xFF705000) : const Color(0xFF3C5A8B)),
                    fontSize: 12,
                    letterSpacing: 0,
                    height: 1.583)))
      ]));
}
