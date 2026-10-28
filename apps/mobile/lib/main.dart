import 'core/navigation_shell.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'core/api.dart';
import 'core/regions.dart';
import 'core/theme.dart';
import 'screens/marketplace.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const JobaApp());
}

class JobaApp extends StatefulWidget {
  final JobaApi? api;
  final RegionGateway? regions;
  final DevicePreferences? preferences;
  const JobaApp({this.api, this.regions, this.preferences, super.key});
  @override
  State<JobaApp> createState() => _JobaAppState();
}

class _JobaAppState extends State<JobaApp> {
  String locale = 'ru';
  final navigation = ValueNotifier<NavigationState?>(null);
  @override
  void dispose() {
    navigation.dispose();
    super.dispose();
  }

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
      builder: (context, child) => ValueListenableBuilder<NavigationState?>(
          valueListenable: navigation,
          builder: (context, value, _) =>
              NavigationFrame(navigation: value, child: child!)),
      home: Marketplace(
          onNavigationChanged: (value) {
            if (mounted &&
                !(value?.sameAs(navigation.value) ?? navigation.value == null))
              navigation.value = value;
          },
          api: widget.api,
          regions: widget.regions,
          preferences: widget.preferences,
          onLocaleChanged: (value) {
            if (locale != value) setState(() => locale = value);
          }));
}
