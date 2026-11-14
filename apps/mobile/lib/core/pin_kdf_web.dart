import 'dart:convert';
import 'dart:js_interop';
import 'dart:typed_data';
import 'package:web/web.dart' as web;

// Use the browser crypto worker rather than blocking Flutter's UI with Dart KDF.
Future<String> deriveLocalPin(String pin, String salt) async {
  final subtle = web.window.crypto.subtle;
  final key = await subtle
      .importKey('raw', Uint8List.fromList(utf8.encode(pin)).toJS,
          'PBKDF2'.toJS, false, ['deriveBits'.toJS].toJS)
      .toDart;
  final parameters = <String, Object>{
    'name': 'PBKDF2',
    'hash': 'SHA-256',
    'iterations': 100000,
    'salt': Uint8List.fromList(base64Decode(salt)).toJS,
  }.jsify()!;
  final bits = await subtle.deriveBits(parameters, key, 256).toDart;
  return base64Encode(bits.toDart.asUint8List());
}
