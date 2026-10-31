import 'dart:convert';
import 'package:crypto/crypto.dart';

// PBKDF2-HMAC-SHA256. Work executes off the UI isolate; PIN never leaves the device.
String derivePin(List<String> input) {
  final prf = Hmac(sha256, utf8.encode(input[0]));
  var block = prf.convert([...base64Decode(input[1]), 0, 0, 0, 1]).bytes;
  final result = List<int>.from(block);
  for (var iteration = 1; iteration < 100000; iteration++) {
    block = prf.convert(block).bytes;
    for (var i = 0; i < result.length; i++) {
      result[i] ^= block[i];
    }
  }
  return base64Encode(result);
}
