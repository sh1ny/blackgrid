part of 'database.dart';

/// The active progress cycle and log-reading position for one game mode.
@DataClassName('ProgressWipeRecord')
class ProgressWipes extends Table {
  TextColumn get mode => text()();
  TextColumn get cycleId => text()();
  TextColumn get startDate => text()();
  TextColumn get lastFolder => text().nullable()();
  IntColumn get updatedAtMs => integer()();

  @override
  Set<Column> get primaryKey => {mode};

  @override
  List<String> get customConstraints => [
    "CHECK (mode IN ('pvp', 'pve', 'seasonal'))",
    'FOREIGN KEY (mode, cycle_id) REFERENCES progress_cycles (mode, cycle_id)',
  ];
}

String _wipeDate(DateTime date) {
  if (date.year < 0 || date.year > 9999) {
    throw ArgumentError.value(date, 'date', 'Year must fit YYYY-MM-DD');
  }
  return '${date.year.toString().padLeft(4, '0')}-'
      '${date.month.toString().padLeft(2, '0')}-'
      '${date.day.toString().padLeft(2, '0')}';
}

DateTime _parseWipeDate(String value) {
  if (!RegExp(r'^\d{4}-\d{2}-\d{2}$').hasMatch(value)) {
    throw FormatException('Invalid wipe start date', value);
  }
  final date = DateTime(
    int.parse(value.substring(0, 4)),
    int.parse(value.substring(5, 7)),
    int.parse(value.substring(8, 10)),
  );
  if (_wipeDate(date) != value) {
    throw FormatException('Invalid wipe start date', value);
  }
  return date;
}

void _checkWipeMode(GameMode mode) {
  if (mode == GameMode.unknown) {
    throw ArgumentError.value(mode, 'mode', 'Unknown game mode');
  }
}

mixin _ProgressWipeOperations on _$BlackgridDatabase
    implements ProgressWipeStore {
  @override
  Future<List<ProgressWipe>> readProgressWipes() async {
    final rows = await customSelect(
      'SELECT mode, cycle_id, start_date, last_folder, updated_at_ms '
      'FROM progress_wipes',
    ).get();
    return [
      for (final row in rows)
        ProgressWipe(
          mode: GameMode.values.byName(row.read<String>('mode')),
          cycleId: row.read<String>('cycle_id'),
          startDate: _parseWipeDate(row.read<String>('start_date')),
          lastFolder: row.readNullable<String>('last_folder'),
          updatedAtMs: row.read<int>('updated_at_ms'),
        ),
    ];
  }

  @override
  Future<void> replaceProgressWipe(ProgressWipe wipe) async {
    _checkWipeMode(wipe.mode);
    await customStatement(
      'INSERT INTO progress_wipes '
      '(mode, cycle_id, start_date, last_folder, updated_at_ms) '
      'VALUES (?, ?, ?, ?, ?) '
      'ON CONFLICT(mode) DO UPDATE SET cycle_id = excluded.cycle_id, '
      'start_date = excluded.start_date, last_folder = excluded.last_folder, '
      'updated_at_ms = excluded.updated_at_ms',
      [
        wipe.mode.name,
        wipe.cycleId,
        _wipeDate(wipe.startDate),
        wipe.lastFolder,
        wipe.updatedAtMs,
      ],
    );
  }

  @override
  Future<void> advanceProgressWipeFolder(
    GameMode mode,
    String folder,
    int updatedAtMs,
  ) async {
    _checkWipeMode(mode);
    await transaction(() async {
      final row = await customSelect(
        'SELECT last_folder FROM progress_wipes WHERE mode = ?',
        variables: [Variable.withString(mode.name)],
      ).getSingle();
      final current = row.readNullable<String>('last_folder');
      if (current == null || compareSessionFolderNames(folder, current) > 0) {
        await customStatement(
          'UPDATE progress_wipes SET last_folder = ?, updated_at_ms = ? '
          'WHERE mode = ?',
          [folder, updatedAtMs, mode.name],
        );
      }
    });
  }

  @override
  Future<void> moveProgressWipeStartEarlier(
    GameMode mode,
    DateTime startDate,
    int updatedAtMs,
  ) async {
    _checkWipeMode(mode);
    final date = _wipeDate(startDate);
    await transaction(() async {
      final row = await customSelect(
        'SELECT start_date FROM progress_wipes WHERE mode = ?',
        variables: [Variable.withString(mode.name)],
      ).getSingle();
      final current = row.read<String>('start_date');
      _parseWipeDate(current);
      if (date.compareTo(current) < 0) {
        await customStatement(
          'UPDATE progress_wipes SET start_date = ?, updated_at_ms = ? '
          'WHERE mode = ?',
          [date, updatedAtMs, mode.name],
        );
      }
    });
  }
}

String _randomProgressId() {
  final random = Random.secure();
  final bytes = List<int>.generate(16, (_) => random.nextInt(256));
  bytes[6] = (bytes[6] & 0x0f) | 0x40;
  bytes[8] = (bytes[8] & 0x3f) | 0x80;
  final hex = bytes
      .map((byte) => byte.toRadixString(16).padLeft(2, '0'))
      .join();
  return '${hex.substring(0, 8)}-${hex.substring(8, 12)}-'
      '${hex.substring(12, 16)}-${hex.substring(16, 20)}-${hex.substring(20)}';
}

final class _ProgressAbort implements Exception {
  const _ProgressAbort(this.failure);
  final ProgressStoreFailure failure;
}

mixin _LocalProgressOperations on _$BlackgridDatabase
    implements LocalProgressStore {
  late DateTime Function() _progressClock = DateTime.now;
  late String Function() _progressIdGenerator = _randomProgressId;
  bool _progressBusy = false;

  ProgressScope? _validatedProgressScope;
  int? _validatedProgressRevision;
  Future<ProgressResult<T>> _progressOperation<T>(Future<T> Function() action) {
    if (_progressBusy) {
      return Future.value(ProgressFailure<T>(const ProgressBusy()));
    }
    _progressBusy = true;
    return _finishProgressOperation(action);
  }

  Future<ProgressResult<T>> _finishProgressOperation<T>(
    Future<T> Function() action,
  ) async {
    try {
      return ProgressSuccess(await action());
    } on _ProgressAbort catch (error) {
      _clearProgressValidation();
      return ProgressFailure(error.failure);
    } on FormatException catch (error) {
      _clearProgressValidation();
      return ProgressFailure(ProgressInvalidInput(error.message));
    } catch (error) {
      _clearProgressValidation();
      return ProgressFailure(ProgressStorageFailure(error.toString()));
    } finally {
      _progressBusy = false;
    }
  }

  void _clearProgressValidation() {
    _validatedProgressScope = null;
    _validatedProgressRevision = null;
  }

  void _rememberProgressValidation(ProgressCycle cycle) {
    _validatedProgressScope = cycle.scope;
    _validatedProgressRevision = cycle.revision;
  }

  void _checkProgressScope(ProgressScope scope) {
    if (scope.mode == GameMode.unknown) {
      throw const _ProgressAbort(ProgressInvalidInput('Unknown game mode'));
    }
    ProgressEventCodec.validateIdentity(scope.cycleId);
  }

  int _progressNow() {
    final now = _progressClock().millisecondsSinceEpoch;
    if (now < -progressMaxTimestampMs || now > progressMaxTimestampMs) {
      throw const _ProgressAbort(ProgressInvalidInput('Invalid clock time'));
    }
    return now;
  }

  List<Variable> _progressVariables(List<Object> values) => [
    for (final value in values)
      switch (value) {
        String value => Variable.withString(value),
        int value => Variable.withInt(value),
        _ => throw ArgumentError.value(value),
      },
  ];

  Future<List<QueryRow>> _progressSelect(
    String sql, [
    List<Object> values = const [],
  ]) => customSelect(sql, variables: _progressVariables(values)).get();

  Future<ProgressCycle> _progressCycle(ProgressScope scope) async {
    final rows = await _progressSelect(
      'SELECT created_at_ms, revision FROM progress_cycles WHERE mode = ? AND cycle_id = ?',
      [scope.mode.name, scope.cycleId],
    );
    if (rows.isEmpty) {
      throw const _ProgressAbort(
        ProgressInvalidInput('Progress cycle does not exist in this mode'),
      );
    }
    final created = rows.single.read<int>('created_at_ms');
    final revision = rows.single.read<int>('revision');
    if (created < -progressMaxTimestampMs ||
        created > progressMaxTimestampMs ||
        revision < 0 ||
        revision > progressMaxInteger) {
      throw _ProgressAbort(
        ProgressUnavailable(scope: scope, reason: 'Invalid cycle metadata'),
      );
    }
    return ProgressCycle(
      scope: scope,
      createdAtMs: created,
      revision: revision,
    );
  }

  Future<String> _progressDeviceIdInTransaction() async {
    final rows = await _progressSelect(
      'SELECT device_id FROM progress_meta WHERE id = 0',
    );
    if (rows.isNotEmpty) {
      final id = rows.single.read<String>('device_id');
      ProgressEventCodec.validateIdentity(id);
      return id;
    }
    final id = _progressIdGenerator();
    ProgressEventCodec.validateIdentity(id);
    await customStatement(
      'INSERT INTO progress_meta (id, device_id) VALUES (0, ?)',
      [id],
    );
    return id;
  }

  @override
  Future<ProgressResult<String>> progressDeviceId() =>
      _progressOperation(() => transaction(_progressDeviceIdInTransaction));

  @override
  Future<ProgressResult<ProgressCycle>> createProgressCycle(GameMode mode) =>
      _progressOperation(() async {
        if (mode == GameMode.unknown) {
          throw const _ProgressAbort(ProgressInvalidInput('Unknown game mode'));
        }
        final id = _progressIdGenerator();
        ProgressEventCodec.validateIdentity(id);
        final created = _progressNow();
        final scope = ProgressScope(mode: mode, cycleId: id);
        return transaction(() async {
          await customStatement(
            'INSERT INTO progress_cycles (cycle_id, mode, created_at_ms, revision) VALUES (?, ?, ?, 0)',
            [id, mode.name, created],
          );
          return ProgressCycle(scope: scope, createdAtMs: created, revision: 0);
        });
      });

  // The CASE avoids transferring an oversized payload into Dart at all.
  static const _progressEventColumns =
      'sequence, event_id, mode, cycle_id, occurred_at_ms, source_rank, '
      'device_id, entity_kind, entity_id, field, format_version, undo_of, '
      'CASE WHEN length(CAST(canonical_payload AS BLOB)) <= $progressEventByteLimit '
      'THEN canonical_payload ELSE NULL END AS canonical_payload';

  ProgressEvent _decodeProgressRow(QueryRow row, ProgressScope affectedScope) {
    try {
      final payload = row.readNullable<String>('canonical_payload');
      if (payload == null) {
        throw const FormatException('Oversized event payload');
      }
      final event = ProgressEventCodec.decode(payload);
      if (row.read<String>('event_id') != event.eventId ||
          row.read<String>('mode') != event.scope.mode.name ||
          row.read<String>('cycle_id') != event.scope.cycleId ||
          row.read<int>('occurred_at_ms') != event.occurredAtMs ||
          row.read<int>('source_rank') != event.source.index ||
          row.read<String>('device_id') != event.deviceId ||
          row.read<String>('entity_kind') != event.target.kind.name ||
          row.read<String>('entity_id') != event.target.id ||
          row.read<String>('field') != event.target.field.name ||
          row.read<int>('format_version') != event.formatVersion ||
          row.readNullable<String>('undo_of') != event.undoOf) {
        throw const FormatException('Event envelope does not match payload');
      }
      return event;
    } catch (error) {
      throw _ProgressAbort(
        ProgressUnavailable(scope: affectedScope, reason: error.toString()),
      );
    }
  }

  Future<ProgressEvent?> _progressEventById(
    String id,
    ProgressScope affectedScope, {
    bool restrictToScope = false,
  }) async {
    final rows = await _progressSelect(
      'SELECT $_progressEventColumns FROM progress_events WHERE event_id = ?'
      '${restrictToScope ? ' AND mode = ? AND cycle_id = ?' : ''}',
      [
        id,
        if (restrictToScope) ...[
          affectedScope.mode.name,
          affectedScope.cycleId,
        ],
      ],
    );
    return rows.isEmpty ? null : _decodeProgressRow(rows.single, affectedScope);
  }

  Future<ProgressEvent?> _progressHead(
    ProgressScope scope,
    ProgressTarget target,
  ) async {
    final heads = await _progressSelect(
      'SELECT event_id FROM progress_heads WHERE mode = ? AND cycle_id = ? '
      'AND entity_kind = ? AND entity_id = ? AND field = ?',
      [
        scope.mode.name,
        scope.cycleId,
        target.kind.name,
        target.id,
        target.field.name,
      ],
    );
    if (heads.isEmpty) return null;
    final event = await _progressEventById(
      heads.single.read<String>('event_id'),
      scope,
    );
    if (event == null || event.scope != scope || event.target != target) {
      throw _ProgressAbort(
        ProgressUnavailable(scope: scope, reason: 'Invalid progress head'),
      );
    }
    return event;
  }

  Future<void> _putProgressHead(ProgressEvent event) => customStatement(
    'INSERT INTO progress_heads (mode, cycle_id, entity_kind, entity_id, field, event_id) '
    'VALUES (?, ?, ?, ?, ?, ?) ON CONFLICT (mode, cycle_id, entity_kind, entity_id, field) '
    'DO UPDATE SET event_id = excluded.event_id',
    [
      event.scope.mode.name,
      event.scope.cycleId,
      event.target.kind.name,
      event.target.id,
      event.target.field.name,
      event.eventId,
    ],
  );

  Future<ProgressAppendResult> _appendProgressInTransaction(
    ProgressScope scope,
    Map<String, (ProgressEvent, String)> batch, {
    bool historyValidated = false,
  }) async {
    final cycle = await _progressCycle(scope);
    if (!historyValidated &&
        (_validatedProgressScope != scope ||
            _validatedProgressRevision != cycle.revision)) {
      _clearProgressValidation();
      var hasNewEvent = false;
      for (final (event, encoded) in batch.values) {
        final existing = await _progressEventById(event.eventId, scope);
        if (existing == null) {
          hasNewEvent = true;
        } else if (ProgressEventCodec.encode(existing) != encoded) {
          throw const _ProgressAbort(
            ProgressIdentityConflict('Event ID already has different content'),
          );
        }
      }
      await _scanProgressHistory(scope, rebuild: hasNewEvent);
    }
    var inserted = 0;
    for (final (event, encoded) in batch.values) {
      final existing = await _progressEventById(event.eventId, scope);
      if (existing != null) {
        if (ProgressEventCodec.encode(existing) != encoded) {
          throw const _ProgressAbort(
            ProgressIdentityConflict('Event ID already has different content'),
          );
        }
        continue;
      }
      final head = await _progressHead(scope, event.target);
      await customStatement(
        'INSERT INTO progress_events (event_id, mode, cycle_id, occurred_at_ms, source_rank, '
        'device_id, entity_kind, entity_id, field, format_version, canonical_payload, undo_of) '
        'VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)',
        [
          event.eventId,
          scope.mode.name,
          scope.cycleId,
          event.occurredAtMs,
          event.source.index,
          event.deviceId,
          event.target.kind.name,
          event.target.id,
          event.target.field.name,
          event.formatVersion,
          encoded,
          event.undoOf,
        ],
      );
      if (head == null || compareProgressEvents(event, head) > 0) {
        await _putProgressHead(event);
      }
      inserted++;
    }
    if (inserted != 0) {
      if (cycle.revision >= progressMaxInteger) {
        throw _ProgressAbort(
          ProgressUnavailable(scope: scope, reason: 'Cycle revision overflow'),
        );
      }
      await customStatement(
        'UPDATE progress_cycles SET revision = revision + 1 WHERE mode = ? AND cycle_id = ?',
        [scope.mode.name, scope.cycleId],
      );
    }
    return ProgressAppendResult(
      insertedCount: inserted,
      revision: cycle.revision + (inserted == 0 ? 0 : 1),
    );
  }

  @override
  Future<ProgressResult<ProgressAppendResult>> appendProgressEvents(
    ProgressScope scope,
    Iterable<ProgressEvent> events,
  ) => _progressOperation(() async {
    _checkProgressScope(scope);
    final batch = <String, (ProgressEvent, String)>{};
    var count = 0;
    for (final event in events) {
      if (++count > progressPageLimit) {
        throw const _ProgressAbort(
          ProgressInvalidInput('Batch exceeds record limit'),
        );
      }
      final encoded = ProgressEventCodec.encode(event);
      if (event.scope != scope) {
        throw const _ProgressAbort(
          ProgressInvalidInput('Event scope does not match cycle'),
        );
      }
      final previous = batch[event.eventId];
      if (previous != null && previous.$2 != encoded) {
        throw const _ProgressAbort(
          ProgressIdentityConflict(
            'Event ID is repeated with different content',
          ),
        );
      }
      batch[event.eventId] = (event, encoded);
    }
    if (count == 0) {
      throw const _ProgressAbort(ProgressInvalidInput('Batch is empty'));
    }
    final result = await transaction(
      () => _appendProgressInTransaction(scope, batch),
    );
    if (result.insertedCount != 0) {
      _validatedProgressScope = scope;
      _validatedProgressRevision = result.revision;
    }
    return result;
  });

  void _checkProgressLimit(int limit) {
    if (limit < 1 || limit > progressPageLimit) {
      throw const _ProgressAbort(ProgressInvalidInput('Invalid page limit'));
    }
  }

  void _checkProgressTarget(ProgressScope scope, ProgressTarget target) {
    ProgressEventCodec.encode(
      ProgressEvent(
        eventId: 'cursor',
        deviceId: 'cursor',
        occurredAtMs: 0,
        scope: scope,
        source: ProgressSource.manual,
        target: target,
        value: const ProgressUnset(),
      ),
    );
  }

  Future<void> _scanProgressHistory(
    ProgressScope scope, {
    required bool rebuild,
  }) async {
    final invalidSequence = await _progressSelect(
      'SELECT sequence FROM progress_events WHERE mode = ? AND cycle_id = ? '
      'AND sequence <= 0 LIMIT 1',
      [scope.mode.name, scope.cycleId],
    );
    if (invalidSequence.isNotEmpty) {
      throw _ProgressAbort(
        ProgressUnavailable(scope: scope, reason: 'Invalid event sequence'),
      );
    }
    if (rebuild) {
      await customStatement(
        'DELETE FROM progress_heads WHERE mode = ? AND cycle_id = ?',
        [scope.mode.name, scope.cycleId],
      );
    }
    var last = 0;
    while (true) {
      final rows = await _progressSelect(
        'SELECT $_progressEventColumns FROM progress_events '
        'WHERE mode = ? AND cycle_id = ? AND sequence > ? '
        'ORDER BY sequence LIMIT ?',
        [scope.mode.name, scope.cycleId, last, progressPageLimit],
      );
      for (final row in rows) {
        final event = _decodeProgressRow(row, scope);
        if (event.scope != scope) {
          throw _ProgressAbort(
            ProgressUnavailable(scope: scope, reason: 'Event scope mismatch'),
          );
        }
        last = row.read<int>('sequence');
        if (rebuild) {
          final head = await _progressHead(scope, event.target);
          if (head == null || compareProgressEvents(event, head) > 0) {
            await _putProgressHead(event);
          }
        }
      }
      if (rows.length < progressPageLimit) return;
    }
  }

  Future<void> _ensureProgressValidated(ProgressCycle cycle) async {
    if (_validatedProgressScope != cycle.scope ||
        _validatedProgressRevision != cycle.revision) {
      _clearProgressValidation();
      await _scanProgressHistory(cycle.scope, rebuild: true);
    }
  }

  @override
  Future<ProgressResult<ProgressCyclePage>> listProgressCycles(
    GameMode mode, {
    int limit = progressPageLimit,
    String? afterCycleId,
  }) => _progressOperation(() async {
    _checkProgressLimit(limit);
    if (mode == GameMode.unknown) {
      throw const _ProgressAbort(ProgressInvalidInput('Unknown game mode'));
    }
    if (afterCycleId != null) ProgressEventCodec.validateIdentity(afterCycleId);
    final rows = await _progressSelect(
      'SELECT cycle_id, created_at_ms, revision FROM progress_cycles '
      'WHERE mode = ? ${afterCycleId == null ? '' : 'AND cycle_id > ?'} '
      'ORDER BY cycle_id COLLATE BINARY LIMIT ?',
      [mode.name, ?afterCycleId, limit + 1],
    );
    final cycles = <ProgressCycle>[];
    for (final row in rows.take(limit)) {
      final id = row.read<String>('cycle_id');
      final scope = ProgressScope(mode: mode, cycleId: id);
      final created = row.read<int>('created_at_ms');
      final revision = row.read<int>('revision');
      try {
        ProgressEventCodec.validateIdentity(id);
        if (created < -progressMaxTimestampMs ||
            created > progressMaxTimestampMs ||
            revision < 0 ||
            revision > progressMaxInteger) {
          throw const FormatException('Invalid cycle metadata');
        }
      } on FormatException catch (error) {
        throw _ProgressAbort(
          ProgressUnavailable(scope: scope, reason: error.message),
        );
      }
      cycles.add(
        ProgressCycle(scope: scope, createdAtMs: created, revision: revision),
      );
    }
    return ProgressCyclePage(
      cycles: cycles,
      nextCursor: rows.length > limit ? cycles.last.scope.cycleId : null,
    );
  });

  @override
  Future<ProgressResult<ProgressCycle>> openProgressCycle(
    ProgressScope scope,
  ) => _progressOperation(() async {
    _checkProgressScope(scope);
    final cycle = await transaction(() async {
      final cycle = await _progressCycle(scope);
      await _scanProgressHistory(scope, rebuild: true);
      return cycle;
    });
    _rememberProgressValidation(cycle);
    return cycle;
  });

  @override
  Future<ProgressResult<ProgressCycle>> rebuildProgress(ProgressScope scope) =>
      _progressOperation(() async {
        _checkProgressScope(scope);
        final cycle = await transaction(() async {
          final cycle = await _progressCycle(scope);
          await _scanProgressHistory(scope, rebuild: true);
          return cycle;
        });
        _rememberProgressValidation(cycle);
        return cycle;
      });

  @override
  Future<ProgressResult<ProgressEvent?>> readProgressEvent(
    ProgressScope scope,
    String eventId,
  ) => _progressOperation(() async {
    _checkProgressScope(scope);
    ProgressEventCodec.validateIdentity(eventId);
    return transaction(() async {
      final cycle = await _progressCycle(scope);
      if (_validatedProgressScope != scope ||
          _validatedProgressRevision != cycle.revision) {
        await _scanProgressHistory(scope, rebuild: false);
      }
      return _progressEventById(eventId, scope, restrictToScope: true);
    });
  });

  @override
  Future<ProgressResult<ProgressHistoryPage>> readProgressHistory(
    ProgressScope scope, {
    int limit = progressPageLimit,
    ProgressHistoryCursor? cursor,
  }) => _progressOperation(() async {
    _checkProgressScope(scope);
    _checkProgressLimit(limit);
    if (cursor != null &&
        (cursor.scope != scope ||
            cursor.lastSequence <= 0 ||
            cursor.highWaterSequence < cursor.lastSequence)) {
      throw const _ProgressAbort(
        ProgressInvalidInput('Invalid history cursor'),
      );
    }
    final result = await transaction(() async {
      final cycle = await _progressCycle(scope);
      await _ensureProgressValidated(cycle);
      final high =
          cursor?.highWaterSequence ??
          (await _progressSelect(
            'SELECT COALESCE(MAX(sequence), 0) AS high FROM progress_events '
            'WHERE mode = ? AND cycle_id = ?',
            [scope.mode.name, scope.cycleId],
          )).single.read<int>('high');
      if (cursor != null) {
        final bounds = await _progressSelect(
          'SELECT COUNT(*) AS count FROM progress_events WHERE mode = ? AND cycle_id = ? '
          'AND sequence IN (?, ?)',
          [scope.mode.name, scope.cycleId, cursor.lastSequence, high],
        );
        final expected = cursor.lastSequence == high ? 1 : 2;
        if (bounds.single.read<int>('count') != expected) {
          throw const _ProgressAbort(
            ProgressInvalidInput('History cursor is not in this cycle'),
          );
        }
      }
      final rows = await _progressSelect(
        'SELECT $_progressEventColumns FROM progress_events WHERE mode = ? AND cycle_id = ? '
        'AND sequence > ? AND sequence <= ? ORDER BY sequence LIMIT ?',
        [
          scope.mode.name,
          scope.cycleId,
          cursor?.lastSequence ?? 0,
          high,
          limit + 1,
        ],
      );
      final events = <ProgressEvent>[];
      for (final row in rows.take(limit)) {
        final event = _decodeProgressRow(row, scope);
        if (event.scope != scope) {
          throw _ProgressAbort(
            ProgressUnavailable(scope: scope, reason: 'Event scope mismatch'),
          );
        }
        events.add(event);
      }
      final next = rows.length > limit
          ? ProgressHistoryCursor(
              scope: scope,
              highWaterSequence: high,
              lastSequence: rows[limit - 1].read<int>('sequence'),
            )
          : null;
      return (cycle, ProgressHistoryPage(events: events, nextCursor: next));
    });
    _rememberProgressValidation(result.$1);
    return result.$2;
  });

  /// Uses SQLite BINARY order for the target keyset; conflict winners still use
  /// the portable event comparator, including its UTF-16 identity tie-breaks.
  @override
  Future<ProgressResult<ProgressCurrentPage>> readProgressCurrent(
    ProgressScope scope, {
    int limit = progressPageLimit,
    ProgressCurrentCursor? cursor,
  }) => _progressOperation(() async {
    _checkProgressScope(scope);
    _checkProgressLimit(limit);
    if (cursor != null) {
      if (cursor.scope != scope ||
          cursor.revision < 0 ||
          cursor.revision > progressMaxInteger) {
        throw const _ProgressAbort(
          ProgressInvalidInput('Invalid current cursor'),
        );
      }
      _checkProgressTarget(scope, cursor.lastTarget);
    }
    final result = await transaction(() async {
      final cycle = await _progressCycle(scope);
      if (cursor != null && cursor.revision != cycle.revision) {
        throw const _ProgressAbort(ProgressStaleCursor());
      }
      await _ensureProgressValidated(cycle);
      if (cursor != null &&
          await _progressHead(scope, cursor.lastTarget) == null) {
        throw const _ProgressAbort(
          ProgressInvalidInput('Current cursor is not in this cycle'),
        );
      }
      final rows = await _progressSelect(
        'SELECT entity_kind, entity_id, field, event_id FROM progress_heads '
        'WHERE mode = ? AND cycle_id = ? '
        '${cursor == null ? '' : 'AND (entity_kind, entity_id, field) > (?, ?, ?) '}'
        'ORDER BY entity_kind COLLATE BINARY, entity_id COLLATE BINARY, field COLLATE BINARY LIMIT ?',
        [
          scope.mode.name,
          scope.cycleId,
          if (cursor != null) ...[
            cursor.lastTarget.kind.name,
            cursor.lastTarget.id,
            cursor.lastTarget.field.name,
          ],
          limit + 1,
        ],
      );
      final events = <ProgressEvent>[];
      for (final row in rows.take(limit)) {
        final event = await _progressEventById(
          row.read<String>('event_id'),
          scope,
        );
        if (event == null ||
            event.scope != scope ||
            event.target.kind.name != row.read<String>('entity_kind') ||
            event.target.id != row.read<String>('entity_id') ||
            event.target.field.name != row.read<String>('field')) {
          throw _ProgressAbort(
            ProgressUnavailable(scope: scope, reason: 'Invalid progress head'),
          );
        }
        events.add(event);
      }
      final next = rows.length > limit
          ? ProgressCurrentCursor(
              scope: scope,
              revision: cycle.revision,
              lastTarget: events.last.target,
            )
          : null;
      return (
        cycle,
        ProgressCurrentPage(
          events: events,
          revision: cycle.revision,
          nextCursor: next,
        ),
      );
    });
    _rememberProgressValidation(result.$1);
    return result.$2;
  });

  Future<ProgressEvent?> _progressPredecessor(ProgressEvent target) async {
    ProgressEvent? predecessor;
    var last = 0;
    while (true) {
      final rows = await _progressSelect(
        'SELECT $_progressEventColumns FROM progress_events WHERE mode = ? AND cycle_id = ? '
        'AND entity_kind = ? AND entity_id = ? AND field = ? AND sequence > ? '
        'ORDER BY sequence LIMIT ?',
        [
          target.scope.mode.name,
          target.scope.cycleId,
          target.target.kind.name,
          target.target.id,
          target.target.field.name,
          last,
          progressPageLimit,
        ],
      );
      for (final row in rows) {
        final candidate = _decodeProgressRow(row, target.scope);
        if (candidate.scope != target.scope ||
            candidate.target != target.target) {
          throw _ProgressAbort(
            ProgressUnavailable(
              scope: target.scope,
              reason: 'Event register mismatch',
            ),
          );
        }
        if (compareProgressEvents(candidate, target) < 0 &&
            (predecessor == null ||
                compareProgressEvents(candidate, predecessor) > 0)) {
          predecessor = candidate;
        }
        last = row.read<int>('sequence');
      }
      if (rows.length < progressPageLimit) return predecessor;
    }
  }

  @override
  Future<ProgressResult<ProgressEvent>> undoProgress(
    ProgressScope scope, {
    required String targetEventId,
    required String requestEventId,
  }) => _progressOperation(() async {
    _checkProgressScope(scope);
    ProgressEventCodec.validateIdentity(targetEventId);
    ProgressEventCodec.validateIdentity(requestEventId);
    final outcome = await transaction(() async {
      final cycle = await _progressCycle(scope);
      final existing = await _progressEventById(requestEventId, scope);
      if (existing != null) {
        if (existing.scope != scope ||
            existing.undoOf != targetEventId ||
            existing.source != ProgressSource.manual) {
          throw const _ProgressAbort(
            ProgressIdentityConflict(
              'Undo request ID already has different content',
            ),
          );
        }
        if (_validatedProgressScope != scope ||
            _validatedProgressRevision != cycle.revision) {
          _clearProgressValidation();
          await _scanProgressHistory(scope, rebuild: false);
        }
        return (existing, cycle.revision, false);
      }
      await _ensureProgressValidated(cycle);
      final target = await _progressEventById(targetEventId, scope);
      if (target == null || target.scope != scope) {
        throw const _ProgressAbort(
          ProgressUndoConflict('Undo target does not exist in this cycle'),
        );
      }
      final head = await _progressHead(scope, target.target);
      if (head == null || head.eventId != targetEventId) {
        throw const _ProgressAbort(
          ProgressUndoConflict('Undo target is not the current winner'),
        );
      }
      if (target.occurredAtMs >= progressMaxTimestampMs) {
        throw const _ProgressAbort(
          ProgressInvalidInput('Undo timestamp overflows'),
        );
      }
      final now = _progressNow();
      final later = target.occurredAtMs + 1;
      final predecessor = await _progressPredecessor(target);
      final event = ProgressEvent(
        eventId: requestEventId,
        deviceId: await _progressDeviceIdInTransaction(),
        occurredAtMs: now > later ? now : later,
        scope: scope,
        source: ProgressSource.manual,
        target: target.target,
        value: predecessor?.value ?? const ProgressUnset(),
        undoOf: targetEventId,
      );
      final encoded = ProgressEventCodec.encode(event);
      final appended = await _appendProgressInTransaction(scope, {
        requestEventId: (event, encoded),
      }, historyValidated: true);
      return (event, appended.revision, true);
    });
    if (outcome.$3) {
      _validatedProgressScope = scope;
      _validatedProgressRevision = outcome.$2;
    }
    return outcome.$1;
  });
}
