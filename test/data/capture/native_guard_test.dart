import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'support/native_guard.dart';

ProcessResult _listing(String stdout, {int exitCode = 0}) =>
    ProcessResult(0, exitCode, stdout, '');

void main() {
  group('native capture guard', () {
    const clean = '"explorer.exe","1","Console","1","10 K"\n';
    const confirmed = {noGamesRunningVariable: '1'};

    test('refuses without the explicit no-games confirmation', () {
      var listed = false;
      for (final env in <Map<String, String>>[
        {},
        {noGamesRunningVariable: ''},
        {noGamesRunningVariable: '0'},
        {noGamesRunningVariable: 'yes'},
      ]) {
        final reason = nativeCaptureSkipReason(
          isWindows: true,
          environment: env,
          listProcesses: () {
            listed = true;
            return _listing(clean);
          },
        );
        expect(reason, contains(noGamesRunningVariable), reason: '$env');
      }
      // The confirmation is checked before anything else runs.
      expect(listed, isFalse);
    });

    test('runs when confirmed and no known game is listed', () {
      expect(
        nativeCaptureSkipReason(
          isWindows: true,
          environment: confirmed,
          listProcesses: () => _listing(clean),
        ),
        isNull,
      );
    });

    test('still refuses a listed game even when confirmed', () {
      for (final game in ['EscapeFromTarkov.exe', 'EscapeFromTarkov_BE.exe']) {
        final reason = nativeCaptureSkipReason(
          isWindows: true,
          environment: confirmed,
          listProcesses: () =>
              _listing('$clean"$game","2","Console","1","9 K"'),
        );
        expect(reason, contains(game.toLowerCase()));
      }
    });

    test('refuses when the process listing fails', () {
      expect(
        nativeCaptureSkipReason(
          isWindows: true,
          environment: confirmed,
          listProcesses: () => _listing('', exitCode: 1),
        ),
        contains('tasklist failed'),
      );
    });

    test('skips off Windows', () {
      expect(
        nativeCaptureSkipReason(
          isWindows: false,
          environment: confirmed,
          listProcesses: () => _listing(clean),
        ),
        contains('Windows-only'),
      );
    });
  });
}
