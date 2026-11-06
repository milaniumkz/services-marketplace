/// Presentation clock anchored to a valid UTC API timestamp. Permissions remain
/// server-enforced; a monotonic elapsed duration avoids device-clock changes.
class ServerClock {
  final Stopwatch _watch = Stopwatch()..start();
  late final Duration Function() _elapsed;
  late final DateTime Function() _deviceNow;
  DateTime? _anchor;
  Duration _at = Duration.zero;
  ServerClock({Duration Function()? elapsed, DateTime Function()? deviceNow}) {
    _elapsed = elapsed ?? () => _watch.elapsed;
    _deviceNow = deviceNow ?? DateTime.now;
  }
  bool get synchronized => _anchor != null;
  DateTime get now {
    final anchor = _anchor;
    if (anchor == null) return _deviceNow().toUtc();
    final passed = _elapsed() - _at;
    return anchor.add(passed.isNegative ? Duration.zero : passed);
  }

  bool synchronize(String? timestamp) {
    final sample = DateTime.tryParse(timestamp ?? '');
    if (sample == null || !sample.isUtc) return false;
    // Concurrent responses may arrive out of order. Do not move time backwards.
    if (_anchor != null && sample.isBefore(now)) return false;
    _anchor = sample;
    _at = _elapsed();
    return true;
  }
}
