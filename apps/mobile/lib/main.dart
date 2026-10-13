import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'core/api.dart';
import 'core/theme.dart';
import 'screens/marketplace.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const JobaApp());
}

class JobaApp extends StatefulWidget {
  final JobaApi? api;
  const JobaApp({this.api, super.key});
  @override
  State<JobaApp> createState() => _JobaAppState();
}

class _JobaAppState extends State<JobaApp> {
  String locale = 'ru';
  @override
  Widget build(BuildContext context) => MaterialApp(
      locale: Locale(locale),
      supportedLocales: const [
        Locale('ru'),
        Locale('kk'),
        Locale('sr'),
        Locale('be')
      ],
      localizationsDelegates: GlobalMaterialLocalizations.delegates,
      title: 'JOBA',
      debugShowCheckedModeBanner: false,
      theme: jobaTheme(),
      home: Marketplace(
          api: widget.api,
          onLocaleChanged: (value) {
            if (locale != value) setState(() => locale = value);
          }));
}
