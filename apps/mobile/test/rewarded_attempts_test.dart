import 'package:flutter_test/flutter_test.dart';
import 'package:services_marketplace/advertising/rewarded_attempts.dart';

void main() {
  test(
      'a failed primary is closed before opening fallback and only fallback can earn',
      () async {
    final events = <String>[];
    await runRewardedAttempts<String>(
        providers: ['google', 'yandex'],
        current: () => true,
        start: (p) async {
          events.add('start:$p');
          return p;
        },
        play: (p, s) async {
          events.add('play:$p');
          if (p == 'google') throw StateError('no fill');
          return true;
        },
        report: (c) async {
          events.add('report:$c');
        });
    expect(events, [
      'start:google',
      'play:google',
      'report:false',
      'start:yandex',
      'play:yandex',
      'report:true'
    ]);
  });
  test('early close never auto-opens another video', () async {
    final started = <String>[], results = <bool>[];
    await runRewardedAttempts<String>(
        providers: ['yandex', 'google'],
        current: () => true,
        start: (p) async {
          started.add(p);
          return p;
        },
        play: (p, s) async => false,
        report: (c) async {
          results.add(c);
        });
    expect(started, ['yandex']);
    expect(results, [false]);
  });
  for (final loadFailure in [true, false]) {
    test(
        'unknown confirmation stops fallback and retains completion for retry: $loadFailure',
        () async {
      var starts = 0;
      bool? reported;
      await expectLater(
          runRewardedAttempts<String>(
              providers: ['google', 'yandex'],
              current: () => true,
              start: (p) async {
                starts++;
                return p;
              },
              play: (p, s) async {
                if (loadFailure) throw StateError('no fill');
                return true;
              },
              report: (c) async {
                reported = c;
                throw StateError('offline');
              }),
          throwsStateError);
      expect(starts, 1);
      expect(reported, !loadFailure);
    });
  }
  test(
      'a changed account during load cannot report an outcome or start fallback',
      () async {
    var active = true, reports = 0, starts = 0;
    await runRewardedAttempts<String>(
        providers: ['google', 'yandex'],
        current: () => active,
        start: (p) async {
          starts++;
          return p;
        },
        play: (p, s) async {
          active = false;
          throw StateError('session changed');
        },
        report: (c) async {
          reports++;
        });
    expect(starts, 1);
    expect(reports, 0);
  });
}
