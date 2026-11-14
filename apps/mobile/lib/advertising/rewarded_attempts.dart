// Fallback is allowed only after the failed attempt is durably closed. A lost
// confirmation must be retried, not followed by another potentially paid view.
Future<void> runRewardedAttempts<T>({
  required List<String> providers,
  required bool Function() current,
  required Future<T> Function(String provider) start,
  required Future<bool> Function(String provider, T session) play,
  required Future<void> Function(bool completed) report,
}) async {
  if (providers.isEmpty) throw StateError('Rewarded is not configured');
  for (var i = 0; i < providers.length; i++) {
    if (!current()) return;
    final provider = providers[i];
    final session = await start(provider);
    if (!current()) return;
    bool completed;
    try {
      completed = await play(provider, session);
    } catch (_) {
      if (!current()) return;
      await report(false);
      if (i + 1 == providers.length) rethrow;
      continue;
    }
    if (current()) await report(completed);
    return; // An early close does not open a second video.
  }
}
