import 'dart:async';
import 'dart:isolate';
import 'dart:typed_data';

import '../domain/catalog.dart';
import '../maps/live_map_budget.dart';
import '../maps/live_map_inventory.dart';
import '../maps/live_map_normalizer.dart';
import '../maps/live_map_snapshot.dart';

/// Normalizes a source bundle on a disposable isolate that is killed on cancel.
Future<Uint8List> normalizeLiveMapInWorker({
  required Map<LiveMapSourceDataset, Uint8List> sources,
  required Iterable<LiveMapBinding> bindings,
  required GameMode mode,
  required int maxMaterializedBytes,
  required int maxSerializedBytes,
  required void Function(int) reserveHandoff,
  required void Function(int) releaseHandoff,
  required Future<void>? cancellation,
}) async {
  final response = ReceivePort();
  Isolate? isolate;
  StreamIterator<Object?>? replies;
  try {
    isolate = await Isolate.spawn(_workerMain, response.sendPort);
    final iterator = StreamIterator<Object?>(response);
    replies = iterator;
    await iterator.moveNext();
    final workerPort = iterator.current as SendPort;
    var inputBytes = 0;
    for (final source in sources.values) {
      inputBytes += source.length;
    }
    final transferCharge = inputBytes;
    if (transferCharge > maxMaterializedBytes) {
      throw const LiveMapResourceLimitException(
        'Live-map worker input exceeds the materialized-data limit.',
      );
    }
    workerPort.send({
      'sources': {
        for (final entry in sources.entries) entry.key.name: entry.value,
      },
      'bindings': [
        for (final binding in bindings)
          {
            'sourceKey': binding.sourceKey,
            'mapId': binding.mapId,
            'calibration': binding.calibration,
          },
      ],
      'mode': mode.catalogRoute,
      'maxMaterializedBytes': maxMaterializedBytes,
      'maxSerializedBytes': maxSerializedBytes,
    });
    final result = await Future.any<Object?>([
      iterator.moveNext().then((_) => iterator.current),
      if (cancellation != null)
        cancellation.then<Object?>((_) => const _Cancelled()),
    ]);
    if (result is _Cancelled) {
      throw StateError('Normalizer worker was cancelled.');
    }
    if (result is _WorkerFailure) {
      if (result.resourceLimit) {
        throw LiveMapResourceLimitException(result.message);
      }
      throw FormatException(result.message);
    }
    if (result is! Map<Object?, Object?> ||
        result['payload'] is! TransferableTypedData ||
        result['length'] is! int) {
      throw StateError('Normalizer worker returned an invalid result.');
    }
    final length = result['length']! as int;
    reserveHandoff(length);
    try {
      return (result['payload']! as TransferableTypedData)
          .materialize()
          .asUint8List();
    } finally {
      releaseHandoff(length);
    }
  } finally {
    isolate?.kill(priority: Isolate.immediate);
    try {
      await replies?.cancel();
    } finally {
      response.close();
    }
  }
}

LiveMapInventory _buildInventory(
  Map<Object?, Object?> rawSources,
  List<LiveMapBinding> bindings,
  String mode,
  LiveMapBudget budget,
) {
  final decoded = <LiveMapSourceDataset, Map<String, dynamic>>{};
  for (final dataset in LiveMapSourceDataset.values) {
    final bytes = rawSources[dataset.name];
    if (bytes is! Uint8List) {
      throw FormatException('Missing ${dataset.name} source body.');
    }
    final value = budget.decodeJson(bytes, maxBytes: 16 * 1024 * 1024);
    if (value is! Map<String, dynamic>) {
      throw FormatException('${dataset.name} source root must be an object.');
    }
    decoded[dataset] = value;
  }
  return LiveMapInventory.fromSources(
    sources: LiveMapSourceBodies(
      maps: decoded[LiveMapSourceDataset.maps]!,
      mapTranslations: decoded[LiveMapSourceDataset.mapTranslations]!,
      tasks: decoded[LiveMapSourceDataset.tasks]!,
      taskTranslations: decoded[LiveMapSourceDataset.taskTranslations]!,
      traders: decoded[LiveMapSourceDataset.traders]!,
      traderTranslations: decoded[LiveMapSourceDataset.traderTranslations]!,
    ),
    bindings: bindings,
    mode: mode,
    budget: budget,
  );
}

class _Cancelled {
  const _Cancelled();
}

class _WorkerFailure {
  const _WorkerFailure(this.message, {this.resourceLimit = false});
  final String message;
  final bool resourceLimit;
}

void _workerMain(SendPort parent) {
  final messages = ReceivePort();
  parent.send(messages.sendPort);
  messages.listen((message) {
    try {
      final input = message as Map<Object?, Object?>;
      final rawSources = input['sources']! as Map<Object?, Object?>;
      final rawBindings = input['bindings']! as List<Object?>;
      final bindings = <LiveMapBinding>[];
      for (final value in rawBindings) {
        final raw = value! as Map<Object?, Object?>;
        bindings.add(
          LiveMapBinding(
            sourceKey: raw['sourceKey']! as String,
            mapId: raw['mapId']! as String,
            calibration: Map<String, Object?>.from(
              raw['calibration']! as Map<Object?, Object?>,
            ),
          ),
        );
      }
      final budget = LiveMapBudget(
        maxMaterializedBytes: input['maxMaterializedBytes']! as int,
        maxSerializedBytes: input['maxSerializedBytes']! as int,
      );
      final inventory = _buildInventory(
        rawSources,
        bindings,
        input['mode']! as String,
        budget,
      );
      // The helper frame has retired its decoded source trees and normalization
      // workspace. Shared scalar values remain owned and charged by the result.
      budget.releaseMaterialized(
        budget.materializedBytes - inventory.retainedMaterializedBytes,
      );
      final payload = inventory.encode(budget: budget);
      budget.reserveMaterialized(payload.length);
      parent.send({
        'payload': TransferableTypedData.fromList([payload]),
        'length': payload.length,
      });
    } on Object catch (error) {
      parent.send(
        _WorkerFailure(
          error.toString(),
          resourceLimit: error is LiveMapResourceLimitException,
        ),
      );
    } finally {
      messages.close();
    }
  });
}
