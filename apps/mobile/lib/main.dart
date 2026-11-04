import 'dart:async';
import 'core/native_diagnostics.dart';
import 'dart:ui';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_crashlytics/firebase_crashlytics.dart';
import 'package:flutter/foundation.dart';
import 'core/push_notifications.dart';
import 'screens/web_push_permission_prompt.dart';
import 'core/navigation_shell.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'core/api.dart';
import 'core/regions.dart';
import 'core/theme.dart';
import 'screens/marketplace.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  PaintingBinding.instance.imageCache.maximumSizeBytes=48*1024*1024;
  PaintingBinding.instance.imageCache.maximumSize=60;
  if(!kIsWeb&&(defaultTargetPlatform==TargetPlatform.android||defaultTargetPlatform==TargetPlatform.iOS)){
    try{
      await Firebase.initializeApp();
      await FirebaseCrashlytics.instance.setCrashlyticsCollectionEnabled(kReleaseMode);
      NativeDiagnostics.enabled=kReleaseMode;
      unawaited(NativeDiagnostics.previousExits());
      FlutterError.onError=(details){FlutterError.presentError(details);unawaited(FirebaseCrashlytics.instance.recordFlutterFatalError(details).catchError((Object _){}));};
      PlatformDispatcher.instance.onError=(error,stack){unawaited(FirebaseCrashlytics.instance.recordError(error,stack,fatal:true).catchError((Object _){}));return true;};
    }catch(_){/* Diagnostics initialization must never prevent startup. */}
  }
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
          builder: (context, value, _) => NavigationFrame(
              navigation: value,
              child: Stack(fit: StackFit.expand, children: [
                child!,
                if (kIsWeb && value != null)
                  WebPushPermissionPrompt(controller: JobaPush.instance)
              ]))),
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
