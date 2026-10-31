final _pending = <String, Future<void>>{};
Future<void> withSessionRefreshLock(
    String key, Future<void> Function() action) {
  final previous = _pending[key] ?? Future<void>.value();
  late Future<void> pending;
  pending =
      previous.catchError((Object _) {}).then((_) => action()).whenComplete(() {
    if (identical(_pending[key], pending)) _pending.remove(key);
  });
  _pending[key] = pending;
  return pending;
}
