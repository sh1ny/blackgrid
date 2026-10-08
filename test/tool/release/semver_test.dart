import 'package:flutter_test/flutter_test.dart';

import '../../../tool/release/src/semver.dart';

void main() {
  test('0.2.0 after v0.1.0 is accepted', () {
    final latest = latestReleaseTag(['v0.1.0']);
    expect(latest, isNotNull);
    expect(increaseRefusal(SemVer.parseRelease('0.2.0'), latest), isNull);
    expect(increaseRefusal(SemVer.parseRelease('0.1.0'), null), isNull);
  });

  test('prerelease precedence: beta.2 and final follow beta.1', () {
    final latest = latestReleaseTag(['v0.1.0', 'v0.2.0-beta.1']);
    expect(latest!.toString(), '0.2.0-beta.1');
    expect(
      increaseRefusal(SemVer.parseRelease('0.2.0-beta.2'), latest),
      isNull,
    );
    expect(increaseRefusal(SemVer.parseRelease('0.2.0'), latest), isNull);

    // SemVer 2.0.0 section 11 ordering chain.
    final chain = [
      '1.0.0-alpha',
      '1.0.0-alpha.1',
      '1.0.0-alpha.beta',
      '1.0.0-beta',
      '1.0.0-beta.2',
      '1.0.0-beta.11',
      '1.0.0-rc.1',
      '1.0.0',
    ].map(SemVer.parseRelease).toList();
    for (var i = 0; i + 1 < chain.length; i++) {
      expect(chain[i].compareTo(chain[i + 1]), lessThan(0), reason: '$i');
      expect(chain[i + 1].compareTo(chain[i]), greaterThan(0));
    }
    expect(
      SemVer.parseRelease('1.0.0').compareTo(SemVer.parseRelease('1.0.0')),
      0,
    );
  });

  test(
    'equal, lower or older-prerelease versions are refused naming latest tag',
    () {
      final latest = latestReleaseTag(['v0.2.0', 'v0.1.0', 'not-a-version']);
      for (final requested in ['0.2.0', '0.1.9', '0.2.0-beta.3']) {
        final message = increaseRefusal(SemVer.parseRelease(requested), latest);
        expect(message, isNotNull, reason: requested);
        expect(message, contains(requested));
        expect(message, contains('v0.2.0'));
      }
    },
  );

  test(
    'v-prefix, missing patch, leading zeros and build metadata are refused',
    () {
      for (final bad in [
        'v0.2.0',
        '0.2',
        '00.2.0',
        '0.2.0-beta.01',
        '0.2.0+5',
      ]) {
        expect(
          () => SemVer.parseRelease(bad),
          throwsA(
            isA<FormatException>().having(
              (e) => e.message,
              'message',
              contains(bad),
            ),
          ),
          reason: bad,
        );
      }
    },
  );
}
