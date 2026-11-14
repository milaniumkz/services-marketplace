import 'package:flutter/services.dart';
import 'external_activity.dart';

Future<Map<String, dynamic>?> currentLocation() =>
    withExternalActivity(() => const MethodChannel('joba.location')
        .invokeMapMethod<String, dynamic>('current')
        .timeout(const Duration(seconds: 45)));
