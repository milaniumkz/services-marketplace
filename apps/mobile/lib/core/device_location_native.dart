import 'package:flutter/services.dart';

Future<Map<String, dynamic>?> currentLocation() =>
    const MethodChannel('joba.location')
        .invokeMapMethod<String, dynamic>('current')
        .timeout(const Duration(seconds: 20));
