import 'dart:convert';
import 'package:crypto/crypto.dart';
import 'api.dart';

/// Encrypted device draft, isolated by account UUID, country and API endpoint.
class OrderDraftStore {
  final SessionVault Function(String) vault;
  Future<void> _writes = Future.value();
  OrderDraftStore({SessionVault Function(String)? vault})
      : vault = vault ?? ((key) => SecureSessionVault(key));
  String key(String scope) => 'joba.order-draft.${sha256.convert(utf8.encode(scope))}';
  Future<Json?> read(String scope) async {
    try {
      await _writes.catchError((Object _) {});
      final raw=await vault(key(scope)).read();
      return raw==null?null:Json.from(jsonDecode(raw));
    } catch (_) { return null; }
  }
  Future<void> save(String scope, Json value) {
    // Serialize captured snapshots so older storage writes cannot win a race.
    final encoded=jsonEncode(value);
    return _writes=_writes.catchError((Object _) {}).then((_)=>vault(key(scope)).write(encoded));
  }
  Future<void> clear(String scope) => _writes=_writes.catchError((Object _) {}).then((_)=>vault(key(scope)).clear());
}
