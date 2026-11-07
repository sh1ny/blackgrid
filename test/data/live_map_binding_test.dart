import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:test/test.dart';

import 'package:blackgrid/data/live_map_refresh.dart';
import 'package:blackgrid/domain/catalog.dart';
import 'package:blackgrid/maps/live_map_budget.dart';
import 'package:blackgrid/maps/live_map_inventory.dart';
import 'package:blackgrid/maps/live_map_snapshot.dart';
import 'package:blackgrid/maps/prepared_map.dart';

import '../support/prepared_pack_manifest.dart' show minimalPreparedMap;

final _now = DateTime.utc(2026, 1, 2);

Map<String, Object?> _body(LiveMapSourceDataset dataset) => switch (dataset) {
  LiveMapSourceDataset.maps => {
    'data': {'maps': <String, Object?>{}, 'mobs': <String, Object?>{}},
  },
  LiveMapSourceDataset.mapTranslations => {'data': <String, Object?>{}},
  LiveMapSourceDataset.tasks => {
    'data': {'tasks': <String, Object?>{}, 'questItems': <String, Object?>{}},
  },
  LiveMapSourceDataset.taskTranslations => {'data': <String, Object?>{}},
  LiveMapSourceDataset.traders => {'data': <String, Object?>{}},
  LiveMapSourceDataset.traderTranslations => {'data': <String, Object?>{}},
};

class _Client extends http.BaseClient {
  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    final dataset = LiveMapSourceDataset.values.singleWhere(
      (value) => request.url.path.endsWith(
        '/${switch (value) {
          LiveMapSourceDataset.maps => 'maps',
          LiveMapSourceDataset.mapTranslations => 'maps_en',
          LiveMapSourceDataset.tasks => 'tasks',
          LiveMapSourceDataset.taskTranslations => 'tasks_en',
          LiveMapSourceDataset.traders => 'traders',
          LiveMapSourceDataset.traderTranslations => 'traders_en',
        }}',
      ),
    );
    return http.StreamedResponse(
      Stream<List<int>>.value(utf8.encode(jsonEncode(_body(dataset)))),
      200,
    );
  }

  @override
  void close() {}
}

class _Store implements LiveMapStore {
  @override
  Future<LiveMapSnapshot?> read(
    GameMode mode, {
    required LiveMapCompatibility compatibility,
    void Function(Object failure)? onRejected,
  }) async => null;

  @override
  Future<void> commit(
    LiveMapSnapshot snapshot, {
    LiveMapBudget? budget,
  }) async {}
}

void main() {
  test(
    'normalizes with a small binding despite large unrelated prepared markers',
    () async {
      final manifestMap = minimalPreparedMap('customs-map')
        ..['sourceKey'] = 'customs'
        ..['markers'] = [
          {
            'id': 'bundled-large-detail',
            'category': 'lootLoose',
            'name': 'Bundled detail',
            'position': {'x': 1, 'z': 2},
            'details': {'description': 'x' * (64 * 1024)},
            'source': {'kind': 'prepared'},
          },
        ];
      final pack = PreparedMapPack(
        version: 'resource-test',
        assetRoot: 'test',
        maps: [PreparedMap.fromJson(manifestMap, assetRoot: 'test')],
      );
      final store = _Store();
      final acquirer = LiveMapRefreshAcquirer(
        client: _Client(),
        store: store,
        clock: () => _now,
        limits: const LiveMapRefreshLimits(
          maxMaterializedBytes: 100 * 1024,
          maxSerializedBytes: 100 * 1024,
        ),
      );

      final snapshot = await acquirer.refresh(
        mode: GameMode.pve,
        intent: LiveMapRefreshIntent(startedAt: _now, isCurrent: () => true),
        pack: pack,
        bindings: pack.liveMapBindings,
      );

      final inventory = LiveMapInventory.decode(
        snapshot.normalizedPayload,
        budget: LiveMapBudget(),
      );
      expect(inventory.maps.keys, unorderedEquals(['customs-map']));
      expect(
        inventory.maps['customs-map'],
        isEmpty,
        reason: 'Absent upstream metadata must not resurrect bundled markers.',
      );
    },
  );
}
