import 'dart:async';

import 'package:blackgrid/application/local_progress_access.dart';
import 'package:blackgrid/application/progress_authority.dart';
import 'package:blackgrid/domain/catalog.dart';
import 'package:blackgrid/domain/local_progress.dart';
import 'package:blackgrid/domain/local_progress_store.dart';
import 'package:blackgrid/domain/progress_wipe_store.dart';
import 'package:flutter/foundation.dart';

/// A [LocalProgressAccess] that serves fixed winners and never writes.
///
/// Reads finish at once. [changed] simulates a progress revision, and the
/// [unavailableModes] a test fills make those modes unavailable.
class FakeProgressAccess extends ChangeNotifier implements LocalProgressAccess {
  /// Creates an access that serves [winners] for every mode.
  FakeProgressAccess({this.winners = const {}});

  /// The winners every read returns.
  Map<ProgressTarget, ProgressEvent> winners;

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

  /// Signals a new progress revision to the listeners.
  void changed() {
    progressRevision++;
    notifyListeners();
  }

  @override
  Future<ProgressResult<LocalProgressSnapshot>> readCurrent(
    GameMode mode,
  ) async => ProgressSuccess(
    LocalProgressSnapshot(
      scope: ProgressScope(mode: mode, cycleId: '${mode.name}-cycle'),
      winners: winners,
    ),
  );

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

/// The winning events of a synthetic PvP wipe, for [FakeProgressAccess].
///
/// Level 30 and faction `usec` unless set; [tasks] and [objectiveCounts] are
/// keyed by catalog IDs.
Map<ProgressTarget, ProgressEvent> localWinners({
  int? level = 30,
  String? faction = 'usec',
  Map<String, ProgressTaskStatus> tasks = const {},
  Map<String, int> objectiveCounts = const {},
  Map<String, int> stations = const {},
}) {
  var next = 0;
  ProgressEvent event(ProgressTarget target, ProgressValue value) =>
      ProgressEvent(
        eventId: 'synthetic-${++next}',
        deviceId: 'synthetic-device',
        occurredAtMs: next,
        scope: const ProgressScope(mode: GameMode.pvp, cycleId: 'pvp-cycle'),
        source: ProgressSource.manual,
        target: target,
        value: value,
      );
  const self = 'self';
  final winners = <ProgressTarget, ProgressEvent>{};
  void put(ProgressTarget target, ProgressValue value) =>
      winners[target] = event(target, value);
  if (level != null) {
    put(
      const ProgressTarget(
        kind: ProgressEntityKind.player,
        id: self,
        field: ProgressField.level,
      ),
      ProgressInteger(level),
    );
  }
  if (faction != null) {
    put(
      const ProgressTarget(
        kind: ProgressEntityKind.player,
        id: self,
        field: ProgressField.faction,
      ),
      ProgressText(faction),
    );
  }
  for (final MapEntry(:key, :value) in tasks.entries) {
    put(
      ProgressTarget(
        kind: ProgressEntityKind.task,
        id: key,
        field: ProgressField.state,
      ),
      ProgressTaskState(value),
    );
  }
  for (final MapEntry(:key, :value) in objectiveCounts.entries) {
    put(
      ProgressTarget(
        kind: ProgressEntityKind.objective,
        id: key,
        field: ProgressField.count,
      ),
      ProgressInteger(value),
    );
  }
  for (final MapEntry(:key, :value) in stations.entries) {
    put(
      ProgressTarget(
        kind: ProgressEntityKind.station,
        id: key,
        field: ProgressField.level,
      ),
      ProgressInteger(value),
    );
  }
  return winners;
}

/// Completes once [authority] publishes local facts, on its own notification.
Future<void> progressPublished(ProgressAuthority authority) {
  if (authority.status == ProgressAuthorityStatus.local) return Future.value();
  final done = Completer<void>();
  void listener() {
    if (authority.status != ProgressAuthorityStatus.local) return;
    authority.removeListener(listener);
    done.complete();
  }

  authority.addListener(listener);
  return done.future;
}
