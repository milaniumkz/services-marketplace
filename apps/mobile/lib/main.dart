import 'package:flutter/material.dart';
import 'core/api.dart';
import 'core/theme.dart';
import 'screens/marketplace.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const JobaApp());
}

class JobaApp extends StatelessWidget {
  final JobaApi? api;
  const JobaApp({this.api, super.key});
  @override
  Widget build(BuildContext context) => MaterialApp(
      title: 'JOBA',
      debugShowCheckedModeBanner: false,
      theme: jobaTheme(),
      home: Marketplace(api: api));
}
