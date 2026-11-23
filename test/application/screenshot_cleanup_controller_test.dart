import 'dart:async';

import 'package:blackgrid/application/recycle_port.dart';
import 'package:blackgrid/application/screenshot_cleanup_controller.dart';
import 'package:blackgrid/application/settings_controller.dart';
import 'package:blackgrid/data/screenshot_folder_lister.dart';
import 'package:blackgrid/domain/raid_lifecycle.dart';
import 'package:blackgrid/domain/screenshot_cleanup.dart';
import 'package:blackgrid/domain/settings.dart';
import 'package:fake_async/fake_async.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/fake_recycle_port.dart';

final _now = DateTime(2026, 11, 22, 14, 30);
const _base = '2026-11-22[14-05]_-120.5, 2.1, 33.4_0, 0.70711, 0, 0.70711';

LogRecordId _id(int value) =>
    LogRecordId('session', LogFile.application, value);
Raid _raid(
  int id, {
  DateTime? end,
  RaidEndCause cause = RaidEndCause.raidExit,
}) => Raid(
  mapId: null,
  mode: null,
  queueTime: null,
  startTime: _now.subtract(const Duration(minutes: 30)),
  startId: _id(id),
  entry: RaidEntry.noQueue,
  endTime: end ?? _now,
  endCause: cause,
);

class _Lifecycle {
  final _stream = StreamController<RaidTransition>.broadcast(sync: true);
  Stream<RaidTransition> get transitions => _stream.stream;
  void emit(RaidTransition transition) => _stream.add(transition);
  void end(Raid raid) =>
      emit(RaidEndedTransition(raid.startId, raid.endTime!, raid));
  void reduceEvents(Iterable<GameLogEvent> events) {
    var current = RaidLifecycleState.initial;
    for (final event in events) {
      final (next, transitions) = reduce(current, event);
      current = next;
      transitions.forEach(emit);
    }
  }

  void dispose() => unawaited(_stream.close());
}

class _Settings extends ChangeNotifier implements SettingsController {
  bool enabled = true;
  @override
  AppSettings get settings => AppSettings(cleanUpRaidScreenshots: enabled);
  void setEnabled(bool value) {
    enabled = value;
    notifyListeners();
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Harness {
  _Harness({
    int count = 1,
    bool enabled = true,
    Future<bool> Function(LogRecordId)? claim,
  }) {
    final claimed = <LogRecordId>{};
    settings.enabled = enabled;
    entries = List.generate(
      count,
      (i) => ScreenshotEntry(
        name: '${_base}_${i + 1}.png',
        isFile: true,
        isLink: false,
        modified: _now.subtract(const Duration(minutes: 1)),
      ),
    );
    controller = ScreenshotCleanupController(
      transitions: lifecycle.transitions,
      settings: settings,
      folder: () async => folder,
      listFolder: (path) async {
        listed.add(path);
        if (heldListing case final held?) return held.future;
        return listing ?? ScreenshotFolderListed(entries);
      },
      claim: claim ?? ((id) async => claimed.add(id)),
      recycle: recycle,
      clock: () => now,
      backstop: (_) => const Duration(seconds: 2),
      cancelWait: const Duration(seconds: 3),
    );
    now = _now;
  }
  final lifecycle = _Lifecycle();
  final settings = _Settings();
  final recycle = FakeRecyclePort();
  DateTime now = _now.subtract(const Duration(hours: 1));
  final listed = <String>[];
  late List<ScreenshotEntry> entries;
  ScreenshotFolderListing? listing;
  Completer<ScreenshotFolderListing>? heldListing;
  String folder = 'first';
  late ScreenshotCleanupController controller;
  void close() {
    controller.dispose();
    lifecycle.dispose();
    settings.dispose();
  }
}

void main() {
  test(
    'screenshot-cleanup: A live raid ends',
    () => fakeAsync((async) {
      final h = _Harness();
      expect(h.controller.lastResult, isNull);
      h.lifecycle.end(_raid(1));
      async.flushMicrotasks();
      expect(h.recycle.calls, hasLength(1));
      h.recycle.calls.single.complete();
      async.flushMicrotasks();
      expect(h.controller.lastResult!.moved, 1);
      h.close();
    }),
  );

  test(
    'screenshot-cleanup: A raid ended by a client restart',
    () => fakeAsync((async) {
      final h = _Harness();
      final old = _now.subtract(const Duration(minutes: 2));
      h.entries = [
        ScreenshotEntry(
          name: '${_base}_1.png',
          isFile: true,
          isLink: false,
          modified: _now.subtract(const Duration(minutes: 3)),
        ),
        ScreenshotEntry(
          name: '${_base}_2.png',
          isFile: true,
          isLink: false,
          modified: _now.subtract(const Duration(minutes: 1)),
        ),
      ];
      h.lifecycle.reduceEvents([
        RaidStarted(_id(1), _now.subtract(const Duration(minutes: 30))),
        SessionFolderChanged('stale-restart', old),
        ProfileSelected(_id(3), old),
        QueueEntered(_id(10), old),
      ]);
      async.flushMicrotasks();
      expect(h.recycle.calls, isEmpty);
      h.lifecycle.reduceEvents([
        RaidStarted(_id(2), _now.subtract(const Duration(minutes: 30))),
        SessionFolderChanged('live-restart', old),
        ProfileSelected(_id(4), old),
        QueueEntered(_id(11), _now),
      ]);
      async.flushMicrotasks();
      expect(h.recycle.calls, hasLength(1));
      expect(h.recycle.calls.single.names, ['${_base}_1.png']);
      h.recycle.calls.single.complete();
      async.flushMicrotasks();
      h.close();
    }),
  );

  test(
    'screenshot-cleanup: Replay at start-up',
    () => fakeAsync((async) {
      final h = _Harness();
      h.lifecycle.end(
        _raid(1, end: _now.subtract(const Duration(seconds: 31))),
      );
      async.flushMicrotasks();
      expect(h.recycle.calls, isEmpty);
      expect(h.controller.lastResult, isNull);
      h.close();
    }),
  );

  test(
    'screenshot-cleanup: Switched on after the raid ended',
    () => fakeAsync((async) {
      final h = _Harness(enabled: false);
      final earlier = _now.subtract(const Duration(seconds: 1));
      h.settings.setEnabled(true);
      h.lifecycle.end(_raid(1, end: earlier));
      h.lifecycle.end(
        _raid(2, end: earlier, cause: RaidEndCause.clientRestart),
      );
      h.lifecycle.emit(QueueEnteredTransition(_id(10), _now));
      async.flushMicrotasks();
      expect(h.recycle.calls, isEmpty);
      expect(h.controller.lastResult, isNull);
      h.close();
    }),
  );

  test(
    'screenshot-cleanup: Matching aborted',
    () => fakeAsync((async) {
      final h = _Harness();
      h.lifecycle.emit(MatchingAbortedTransition(_id(1), _now));
      async.flushMicrotasks();
      expect(h.recycle.calls, isEmpty);
      expect(h.controller.lastResult, isNull);
      h.close();
    }),
  );

  test(
    'screenshot-cleanup: The same raid ends again',
    () => fakeAsync((async) {
      final h = _Harness();
      final raid = _raid(1);
      h.lifecycle.end(raid);
      h.lifecycle.end(raid);
      async.flushMicrotasks();
      expect(h.recycle.calls, hasLength(1));
      h.recycle.calls.single.complete();
      async.flushMicrotasks();
      h.lifecycle.end(raid);
      async.flushMicrotasks();
      expect(h.recycle.calls, hasLength(1));
      h.close();
    }),
  );

  test(
    'reconnect with the same start identity is cleaned once',
    () => fakeAsync((async) {
      final h = _Harness();
      final start = _now.subtract(const Duration(minutes: 30));
      final restart = _now.subtract(const Duration(minutes: 3));
      h.lifecycle.reduceEvents([
        RaidStarted(_id(1), start),
        SessionFolderChanged('reconnect', restart),
        ProfileSelected(_id(3), restart),
        RaidRejoined(_id(4), restart, 'MatchWait', 'bigmap', 'customs'),
        RaidStarted(_id(5), restart),
        RaidExit(_id(6), _now),
      ]);
      async.flushMicrotasks();
      h.recycle.calls.single.complete();
      async.flushMicrotasks();
      h.lifecycle.end(_raid(1));
      async.flushMicrotasks();
      expect(h.recycle.calls, hasLength(1));
      h.close();
    }),
  );

  test(
    'held restart ending is discarded when the next transition is not a queue',
    () => fakeAsync((async) {
      final h = _Harness();
      h.lifecycle.end(_raid(1, cause: RaidEndCause.clientRestart));
      h.lifecycle.emit(MatchingAbortedTransition(_id(2), _now));
      h.lifecycle.emit(QueueEnteredTransition(_id(3), _now));
      async.flushMicrotasks();
      expect(h.recycle.calls, isEmpty);
      h.close();
    }),
  );

  test(
    'screenshot-cleanup: Every file moves',
    () => fakeAsync((async) {
      final h = _Harness(count: 3);
      h.lifecycle.end(_raid(1));
      async.flushMicrotasks();
      h.recycle.calls.single.complete();
      async.flushMicrotasks();
      expect(h.controller.lastResult!.moved, 3);
      expect(h.controller.lastResult!.notMoved, 0);
      h.close();
    }),
  );

  test(
    'screenshot-cleanup: The Recycle Bin cannot take a file',
    () => fakeAsync((async) {
      final h = _Harness(count: 2);
      h.lifecycle.end(_raid(1));
      async.flushMicrotasks();
      final call = h.recycle.calls.single;
      call.complete({call.names.first: const RecycleNotRecyclable()});
      async.flushMicrotasks();
      expect(h.controller.lastResult!.moved, 1);
      expect(h.controller.lastResult!.notMoved, 1);
      h.close();
    }),
  );

  test(
    'screenshot-cleanup: The recycle call fails',
    () => fakeAsync((async) {
      final h = _Harness(count: 2);
      h.lifecycle.end(_raid(1));
      async.flushMicrotasks();
      h.recycle.calls.single.completion.complete(const RecycleCallFailure());
      async.flushMicrotasks();
      expect(h.controller.lastResult!.moved, 0);
      expect(h.controller.lastResult!.notMoved, 2);
      h.close();
    }),
  );

  test(
    'invalid acknowledgement leaves move counts unconfirmed',
    () => fakeAsync((async) {
      final h = _Harness(count: 2);
      h.lifecycle.end(_raid(1));
      async.flushMicrotasks();
      h.recycle.calls.single.completion.complete(const RecycleUnknownOutcome());
      async.flushMicrotasks();
      expect(h.controller.lastResult!.notMoved, 0);
      expect(h.controller.lastResult!.unconfirmed, 2);
      h.close();
    }),
  );

  test(
    'claim failure leaves all files alone',
    () => fakeAsync((async) {
      final h = _Harness(claim: (_) async => throw StateError('unwritable'));
      h.lifecycle.end(_raid(1));
      async.flushMicrotasks();
      expect(h.recycle.calls, isEmpty);
      expect(h.controller.lastResult!.claimFailed, isTrue);
      h.close();
    }),
  );

  test(
    'screenshot-cleanup: One file is locked',
    () => fakeAsync((async) {
      final h = _Harness(count: 2);
      h.lifecycle.end(_raid(1));
      async.flushMicrotasks();
      final call = h.recycle.calls.single;
      call.complete({call.names.first: const RecycleFailed()});
      async.flushMicrotasks();
      expect(h.controller.lastResult!.moved, 1);
      expect(h.controller.lastResult!.notMoved, 1);
      h.close();
    }),
  );

  test(
    'screenshot-cleanup: A file vanished before the move',
    () => fakeAsync((async) {
      final h = _Harness(count: 2);
      h.lifecycle.end(_raid(1));
      async.flushMicrotasks();
      final call = h.recycle.calls.single;
      call.complete({call.names.first: const RecycleMissing()});
      async.flushMicrotasks();
      expect(h.controller.lastResult!.moved, 1);
      expect(h.controller.lastResult!.notMoved, 0);
      h.close();
    }),
  );

  test(
    'screenshot-cleanup: The folder changed during the raid',
    () => fakeAsync((async) {
      final h = _Harness();
      h.folder = 'changed';
      h.lifecycle.end(_raid(1));
      async.flushMicrotasks();
      expect(h.listed, ['changed']);
      expect(h.recycle.calls.single.folder, 'changed');
      h.recycle.calls.single.complete();
      async.flushMicrotasks();
      h.close();
    }),
  );

  test(
    'screenshot-cleanup: Two raids end close together',
    () => fakeAsync((async) {
      final h = _Harness();
      h.lifecycle.end(_raid(1));
      async.flushMicrotasks();
      h.lifecycle.end(_raid(2));
      async.flushMicrotasks();
      expect(h.recycle.calls, hasLength(1));
      h.folder = 'second';
      h.recycle.calls[0].complete();
      async.flushMicrotasks();
      expect(h.recycle.calls, hasLength(2));
      expect(h.recycle.calls[1].folder, 'second');
      h.recycle.calls[1].complete();
      async.flushMicrotasks();
      h.close();
    }),
  );

  test(
    'screenshot-cleanup: Switched off while a cleanup waits',
    () => fakeAsync((async) {
      final h = _Harness();
      h.lifecycle.end(_raid(1));
      async.flushMicrotasks();
      h.lifecycle.end(_raid(2));
      h.settings.setEnabled(false);
      h.recycle.calls[0].complete();
      async.flushMicrotasks();
      expect(h.recycle.calls, hasLength(1));
      expect(h.controller.lastResult!.moved, 1);
      h.close();
    }),
  );

  test(
    'opt-out during preparation prevents dispatch',
    () => fakeAsync((async) {
      final h = _Harness();
      final listing = h.heldListing = Completer<ScreenshotFolderListing>();
      h.lifecycle.end(_raid(1));
      async.flushMicrotasks();
      expect(h.listed, ['first']);
      h.settings.setEnabled(false);
      h.settings.setEnabled(true);
      listing.complete(ScreenshotFolderListed(h.entries));
      async.flushMicrotasks();
      expect(h.recycle.calls, isEmpty);
      h.close();
    }),
  );

  test(
    'screenshot-cleanup: Blackgrid closes during a cleanup',
    () => fakeAsync((async) {
      final h = _Harness();
      var notifications = 0;
      h.controller.addListener(() => notifications++);
      h.lifecycle.end(_raid(1));
      async.flushMicrotasks();
      h.lifecycle.end(_raid(2));
      h.controller.dispose();
      expect(h.recycle.cancellations, 1);
      h.recycle.calls[0].complete();
      async.flushMicrotasks();
      expect(h.recycle.calls, hasLength(1));
      expect(notifications, 0);
      h.lifecycle.dispose();
      h.settings.dispose();
    }),
  );

  test(
    'screenshot-cleanup: Too many cleanups waiting',
    () => fakeAsync((async) {
      final h = _Harness();
      h.lifecycle.end(_raid(1));
      async.flushMicrotasks();
      for (var i = 2; i <= 6; i++) {
        h.lifecycle.end(_raid(i));
      }
      h.recycle.calls[0].complete();
      async.flushMicrotasks();
      expect(h.controller.lastResult!.skippedRaids, 1);
      for (var i = 1; i < 5; i++) {
        expect(h.recycle.calls, hasLength(i + 1));
        h.recycle.calls[i].complete();
        async.flushMicrotasks();
      }
      expect(h.recycle.calls, hasLength(5));
      h.close();
    }),
  );

  test(
    'screenshot-cleanup: The folder is missing',
    () => fakeAsync((async) {
      final h = _Harness();
      h.listing = const ScreenshotFolderMissing();
      h.lifecycle.end(_raid(1));
      async.flushMicrotasks();
      expect(h.controller.lastResult!.folderUnreadable, isTrue);
      expect(h.recycle.calls, isEmpty);
      h.close();
    }),
  );

  test(
    'unreadable and empty folders and no matches are reported',
    () => fakeAsync((async) {
      final h = _Harness();
      h.listing = const ScreenshotFolderUnreadable();
      h.lifecycle.end(_raid(1));
      async.flushMicrotasks();
      expect(h.controller.lastResult!.folderUnreadable, isTrue);
      h.folder = '';
      h.lifecycle.end(_raid(2));
      async.flushMicrotasks();
      expect(h.controller.lastResult!.folderUnreadable, isTrue);
      h.folder = 'first';
      h.listing = const ScreenshotFolderListed([]);
      h.lifecycle.end(_raid(3));
      async.flushMicrotasks();
      expect(h.controller.lastResult!.noScreenshots, isTrue);
      expect(h.recycle.calls, isEmpty);
      h.close();
    }),
  );

  test(
    'batches at most 64 names serially',
    () => fakeAsync((async) {
      final h = _Harness(count: 130);
      h.lifecycle.end(_raid(1));
      async.flushMicrotasks();
      expect(h.recycle.calls.single.names, hasLength(64));
      h.recycle.calls[0].complete();
      async.flushMicrotasks();
      expect(h.recycle.calls[1].names, hasLength(64));
      h.recycle.calls[1].complete();
      async.flushMicrotasks();
      expect(h.recycle.calls[2].names, hasLength(2));
      h.recycle.calls[2].complete();
      async.flushMicrotasks();
      expect(h.controller.lastResult!.moved, 130);
      h.close();
    }),
  );

  test(
    'screenshot-cleanup: The recycle call does not answer',
    () => fakeAsync((async) {
      final h = _Harness(count: 65);
      h.lifecycle.end(_raid(1));
      async.flushMicrotasks();
      h.lifecycle.end(_raid(2));
      async.elapse(const Duration(seconds: 2));
      async.flushMicrotasks();
      expect(h.recycle.cancellations, 1);
      expect(h.recycle.calls, hasLength(1));
      expect(h.controller.lastResult!.unconfirmed, 64);
      expect(h.controller.lastResult!.notMoved, 1);
      async.elapse(const Duration(seconds: 3));
      async.flushMicrotasks();
      expect(h.recycle.calls, hasLength(1));
      expect(h.controller.lastResult!.unavailable, isTrue);
      expect(h.controller.lastResult!.unconfirmed, 64);
      expect(h.controller.lastResult!.notMoved, 1);
      h.lifecycle.end(_raid(3));
      async.flushMicrotasks();
      expect(h.recycle.calls, hasLength(1));
      expect(h.controller.lastResult!.unconfirmed, 64);
      h.recycle.calls[0].complete();
      async.flushMicrotasks();
      h.close();
    }),
  );

  test(
    'late reply after timeout permits the next raid without overlap',
    () => fakeAsync((async) {
      final h = _Harness();
      h.lifecycle.end(_raid(1));
      async.flushMicrotasks();
      h.lifecycle.end(_raid(2));
      async.elapse(const Duration(seconds: 2));
      async.flushMicrotasks();
      expect(h.recycle.calls, hasLength(1));
      h.recycle.calls[0].complete();
      async.flushMicrotasks();
      expect(h.recycle.calls, hasLength(2));
      h.recycle.calls[1].complete();
      async.flushMicrotasks();
      expect(h.controller.lastResult!.moved, 1);
      h.close();
    }),
  );
}
