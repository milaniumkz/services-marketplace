import 'package:flutter/material.dart';

const primary = Color(0xFF245BDB);
const navy = Color(0xFF172B4D);
const canvas = Color(0xFFF5F7FB);
const line = Color(0xFFE3E9F2);
const yellow = Color(0xFFFFD65A);

ThemeData jobaTheme() => ThemeData(
      useMaterial3: true,
      fontFamily: 'Noto',
      scaffoldBackgroundColor: Colors.white,
      colorScheme: ColorScheme.fromSeed(seedColor: primary)
          .copyWith(primary: primary, onSurface: navy),
      appBarTheme: const AppBarTheme(
          backgroundColor: Colors.white,
          surfaceTintColor: Colors.transparent,
          centerTitle: true,
          toolbarHeight: 60,
          titleTextStyle: TextStyle(
              fontFamily: 'Noto',
              fontSize: 17,
              fontWeight: FontWeight.w700,
              color: navy)),
      inputDecorationTheme: InputDecorationTheme(
          filled: true,
          fillColor: Colors.white,
          contentPadding:
              const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
          border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(13),
              borderSide: const BorderSide(color: line)),
          enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(13),
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
      outlinedButtonTheme: OutlinedButtonThemeData(
          style: OutlinedButton.styleFrom(
              foregroundColor: navy,
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
                fontWeight: FontWeight.w700,
                height: 1.269,
                color: navy)),
        if (subtitle.isNotEmpty)
          Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(subtitle,
                  style: const TextStyle(
                      fontSize: 13, color: Color(0xFF6B7890), height: 1.5))),
      ]));
}

class Notice extends StatelessWidget {
  final String text;
  final bool error;
  const Notice(this.text, {this.error = false, super.key});
  @override
  Widget build(BuildContext context) => Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      margin: const EdgeInsets.symmetric(vertical: 12),
      decoration: BoxDecoration(
          color: error ? const Color(0xFFFFEEEE) : const Color(0xFFEAF0FC),
          borderRadius: BorderRadius.circular(14)),
      child: Text(text,
          style: TextStyle(
              color: error ? const Color(0xFFA02C32) : navy,
              fontSize: 12,
              height: 1.583)));
}
