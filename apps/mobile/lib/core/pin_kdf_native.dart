import 'package:flutter/foundation.dart';
import 'pin_derivation.dart';

Future<String> deriveLocalPin(String pin, String salt) =>
    compute(derivePin, [pin, salt]);
