import 'dart:async';

import 'package:blackgrid/application/local_progress_access.dart';
import 'package:blackgrid/application/progress_authority.dart';
import 'package:blackgrid/domain/catalog.dart';
import 'package:blackgrid/domain/local_progress.dart';
import 'package:blackgrid/domain/local_progress_store.dart';
import 'package:blackgrid/domain/progress_wipe_store.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';

const _shortage = ProgressTarget(
  kind: ProgressEntityKind.task,
  id: 'shortage',
  field: ProgressField.state,
);

ProgressEvent _finished(GameMode mode, {int at = 1}) => ProgressEvent(
  eventId: 'event-${mode.name}-$at',
  deviceId: 'device',
  occurredAtMs: at,
  scope: ProgressScope(mode: mode, cycleId: '${mode.name}-cycle'),
  source: ProgressSource.manual,
  target: _shortage,
  value: const ProgressTaskState(ProgressTaskStatus.finished),
);

/// A mode source the test moves by hand.
class _Mode extends ChangeNotifier {
  GameMode value = GameMode.pvp;

  void change(GameMode mode) {
    value = mode;
    notifyListeners();
  }
}

/// A hand-written access whose reads the test releases one by one.
class _Access extends ChangeNotifier implements LocalProgressAccess {
  @override
  bool loaded = true;
  @override
  String? loadError;
  @override
  int progressRevision = 0;
  @override
  final Map<GameMode, ProgressWipe> wipes = {};
  @override
  final Set<GameMode> unavailableModes = {};

  /// The winners each mode reads next.
  final Map<GameMode, Map<ProgressTarget, ProgressEvent>> heads = {
    GameMode.pvp: {},
    GameMode.pve: {},
  };

  /// Reads begun and not yet released, oldest first.
  final List<_PendingRead> pending = [];

  /// Every mode a read was begun for, in order.
  final List<GameMode> reads = [];

  /// Whether reads wait for [release] instead of finishing at once.
  bool holdReads = false;

  void signal({bool revision = false}) {
    if (revision) progressRevision++;
    notifyListeners();
  }

  @override
  Future<ProgressResult<LocalProgressSnapshot>> readCurrent(
    GameMode mode,
  ) async {
    reads.add(mode);
    final snapshot = LocalProgressSnapshot(
      scope: ProgressScope(mode: mode, cycleId: '${mode.name}-cycle'),
      winners: Map.of(heads[mode] ?? {}),
    );
    if (!holdReads) return ProgressSuccess(snapshot);
    final read = _PendingRead(mode, snapshot);
    pending.add(read);
    return read.completer.future;
  }

  /// Finishes the oldest held read, with [failure] when given.
  void release({ProgressStoreFailure? failure}) {
    final read = pending.removeAt(0);
    read.completer.complete(
      failure == null
          ? ProgressSuccess(read.snapshot)
          : ProgressFailure(failure),
    );
  }

  @override
  Future<ProgressResult<ProgressEvent>> appendManual(
    GameMode mode,
    ProgressTarget target,
    ProgressValue value,
  ) => throw UnimplementedError();

  @override
  Future<ProgressResult<ProgressEvent>> undo(
    GameMode mode,
    String cycleId,
    String targetEventId,
  ) => throw UnimplementedError();

  @override
  Future<ProgressResult<ProgressEvent>> redo(
    GameMode mode,
    String cycleId,
    String undoEventId,
  ) => throw UnimplementedError();
}

class _PendingRead {
  _PendingRead(this.mode, this.snapshot);

  final GameMode mode;
  final LocalProgressSnapshot snapshot;
  final Completer<ProgressResult<LocalProgressSnapshot>> completer =
      Completer();
}

/// Lets the awaited read and its continuation run.
Future<void> _settle() => pumpEventQueue();

void main() {
  late _Mode mode;
  late _Access access;
  late ProgressAuthority authority;
  late List<ProgressAuthorityStatus> seen;

  ProgressAuthority build() {
    final built = ProgressAuthority(
      access: access,
      modeChanges: mode,
      mode: () => mode.value,
    );
    seen = [built.status];
    built.addListener(() => seen.add(built.status));
    return built;
  }

  setUp(() {
    mode = _Mode();
    access = _Access();
  });

  tearDown(() => authority.dispose());

  test('progress-authority: Other mode\'s progress is not used', () async {
    access.heads[GameMode.pve]![_shortage] = _finished(GameMode.pve);
    authority = build();
    await _settle();

    expect(authority.mode, GameMode.pvp);
    expect(authority.status, ProgressAuthorityStatus.local);
    expect(authority.facts!.mode, GameMode.pvp);
    expect(authority.facts!.taskState('shortage'), isNull);
    expect(access.reads, [GameMode.pvp]);
  });

  test('progress-authority: Unknown mode', () async {
    mode.value = GameMode.unknown;
    authority = build();
    await _settle();

    expect(authority.status, ProgressAuthorityStatus.unavailable);
    expect(authority.facts, isNull);
    expect(access.reads, isEmpty);
  });

  test('progress-authority: Wipe history unavailable', () async {
    access.unavailableModes.add(GameMode.pvp);
    authority = build();
    await _settle();

    expect(authority.status, ProgressAuthorityStatus.unavailable);
    expect(authority.facts, isNull);
    expect(access.reads, isEmpty);

    // Recovery reads again and publishes local facts.
    access.unavailableModes.clear();
    access.signal(revision: true);
    await _settle();
    expect(authority.status, ProgressAuthorityStatus.local);
    expect(authority.facts, isNotNull);
  });

  test('a load error makes progress unavailable', () async {
    access.loadError = 'broken';
    authority = build();
    await _settle();

    expect(authority.status, ProgressAuthorityStatus.unavailable);
    expect(authority.facts, isNull);
    expect(access.reads, isEmpty);
  });

  test('progress-authority: Old progress still counts', () async {
    // Nothing in the authority reads a clock, so event age cannot matter.
    access.heads[GameMode.pvp]![_shortage] = _finished(GameMode.pvp, at: 1);
    authority = build();
    await _settle();

    expect(authority.status, ProgressAuthorityStatus.local);
    expect(authority.facts!.taskState('shortage'), ProgressTaskStatus.finished);
  });

  test('progress-authority: Read fails after a good read', () async {
    access.heads[GameMode.pvp]![_shortage] = _finished(GameMode.pvp);
    authority = build();
    await _settle();
    expect(authority.facts, isNotNull);

    access.holdReads = true;
    access.signal(revision: true);
    // The last facts stay while the re-read runs.
    expect(authority.status, ProgressAuthorityStatus.local);
    expect(authority.facts, isNotNull);

    access.release(failure: const ProgressInvalidInput('broken'));
    await _settle();
    expect(authority.status, ProgressAuthorityStatus.unavailable);
    expect(authority.facts, isNull);

    // A later successful read brings the facts back.
    access.signal(revision: true);
    access.release();
    await _settle();
    expect(authority.status, ProgressAuthorityStatus.local);
    expect(authority.facts!.taskState('shortage'), ProgressTaskStatus.finished);
  });

  test('workspace-shell: Loading after a mode switch', () async {
    access.heads[GameMode.pve]![_shortage] = _finished(GameMode.pve);
    authority = build();
    await _settle();
    expect(authority.status, ProgressAuthorityStatus.local);

    access.holdReads = true;
    mode.change(GameMode.pve);
    // Facts go at once, so PvP facts never meet PvE item data.
    expect(authority.mode, GameMode.pve);
    expect(authority.status, ProgressAuthorityStatus.loading);
    expect(authority.facts, isNull);

    access.release();
    await _settle();
    expect(authority.status, ProgressAuthorityStatus.local);
    expect(authority.facts!.mode, GameMode.pve);
    expect(authority.facts!.taskState('shortage'), ProgressTaskStatus.finished);
  });

  test('workspace-shell: Edit keeps the label', () async {
    authority = build();
    await _settle();
    expect(authority.status, ProgressAuthorityStatus.local);
    seen.clear();

    access.holdReads = true;
    access.heads[GameMode.pvp]![_shortage] = _finished(GameMode.pvp);
    access.signal(revision: true);
    expect(authority.status, ProgressAuthorityStatus.local);
    expect(authority.facts!.taskState('shortage'), isNull);

    access.release();
    await _settle();
    expect(seen, isNot(contains(ProgressAuthorityStatus.loading)));
    expect(authority.status, ProgressAuthorityStatus.local);
    expect(authority.facts!.taskState('shortage'), ProgressTaskStatus.finished);
  });

  test('a stale PvP read is dropped after a switch to PvE', () async {
    access.holdReads = true;
    access.heads[GameMode.pvp]![_shortage] = _finished(GameMode.pvp);
    authority = build();
    await _settle();
    expect(access.pending.single.mode, GameMode.pvp);

    mode.change(GameMode.pve);
    // One read in flight: the PvE read waits for the PvP read to end.
    expect(access.reads, [GameMode.pvp]);

    access.release();
    await _settle();
    expect(authority.status, ProgressAuthorityStatus.loading);
    expect(authority.facts, isNull);
    expect(access.reads, [GameMode.pvp, GameMode.pve]);

    access.release();
    await _settle();
    expect(authority.status, ProgressAuthorityStatus.local);
    expect(authority.facts!.mode, GameMode.pve);
    expect(authority.facts!.taskState('shortage'), isNull);
  });

  test('requests during a read coalesce into one more read', () async {
    access.holdReads = true;
    authority = build();
    await _settle();
    expect(access.reads, hasLength(1));

    access.signal(revision: true);
    access.signal(revision: true);
    access.signal(revision: true);
    expect(access.reads, hasLength(1));

    access.release();
    await _settle();
    expect(access.reads, hasLength(2));
    expect(authority.status, ProgressAuthorityStatus.local);

    access.release();
    await _settle();
    expect(access.reads, hasLength(2));
    expect(access.pending, isEmpty);
  });

  test('status is loading while the access has not loaded', () async {
    access.loaded = false;
    authority = build();
    await _settle();

    expect(authority.status, ProgressAuthorityStatus.loading);
    expect(authority.facts, isNull);
    expect(access.reads, isEmpty);

    access.loaded = true;
    access.signal();
    await _settle();
    expect(authority.status, ProgressAuthorityStatus.local);
    expect(access.reads, [GameMode.pvp]);
  });

  test('unrelated access signals start no read', () async {
    authority = build();
    await _settle();
    access.signal();
    await _settle();
    expect(access.reads, hasLength(1));
  });
}
