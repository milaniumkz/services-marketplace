// Camera, gallery and rewarded ads belong to the current foreground task.
// Their Android activities must not be treated as leaving JOBA unattended.
int _depth = 0;
DateTime? _returnedAt;
bool get externalActivityActive => _depth > 0 || (_returnedAt!=null&&DateTime.now().difference(_returnedAt!)<const Duration(seconds:3));
Future<T> withExternalActivity<T>(Future<T> Function() action) async {
  _depth++;
  try { return await action(); } finally { _depth--; _returnedAt=DateTime.now(); }
}
