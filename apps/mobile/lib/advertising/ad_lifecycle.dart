import 'package:flutter/widgets.dart';

Future<void>? _release;
void releaseBanner(Future<void> Function() dispose) {
  final future = (_release ?? Future<void>.value())
      .then((_) => dispose())
      .catchError((Object _) {});
  _release = future;
  future.whenComplete(() {
    if (identical(_release, future)) _release = null;
  });
}

Future<void> waitForBannerRelease() async {
  // The previous platform view is disposed in finalizeTree before this frame ends.
  await WidgetsBinding.instance.endOfFrame;
  final pending = _release;
  if (pending != null) await pending;
}
