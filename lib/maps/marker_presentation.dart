import 'package:blackgrid/domain/catalog.dart';
import 'package:blackgrid/domain/marker_categories.dart';
import 'package:blackgrid/maps/prepared_map.dart';

/// A human-readable summary derived from prepared marker facts.
class MarkerPresentation {
  MarkerPresentation({
    required this.title,
    required this.categoryLabel,
    required Iterable<String> facts,
  }) : facts = List.unmodifiable(facts);

  /// The display name, or the category label when the source name is generic.
  final String title;

  /// The player-facing marker category label.
  final String categoryLabel;

  /// The applicable translated or resolved facts in display order.
  final List<String> facts;

  /// The summary text without raw source identifiers.
  String get text => [title, categoryLabel, ...facts].join('\n');
}

/// Derives a summary using only prepared facts and a matching loaded catalog.
///
/// [mapMarkers] supplies the current map inventory for source-linked switches.
/// Item names are used only when [activeMode] and [catalogSnapshot].mode match
/// and are known. Unresolved referenced items are displayed as unavailable.
/// This function performs no fetches and does not include raw source IDs.
MarkerPresentation presentMarker(
  PreparedMarker marker, {
  Iterable<PreparedMarker> mapMarkers = const [],
  GameMode activeMode = GameMode.unknown,
  CatalogSnapshot? catalogSnapshot,
}) {
  final categoryLabel = markerCategoryLabel(marker.filterKey);
  final title = _displayName(marker, categoryLabel);
  final facts = <String>[];
  final details = marker.details;

  final description =
      marker.filterKey == 'QuestItems' || marker.filterKey == 'QuestObjectives'
      ? _text(details['description'])
      : null;
  if (description != null) facts.add(description);

  final quest = details['quest'];
  if (quest is Map) {
    final name = _text(quest['name']);
    if (name != null && name != title) facts.add(name);
    final trader = quest['trader'];
    final traderName = trader is Map ? _text(trader['name']) : _text(trader);
    if (traderName != null) facts.add('Trader: $traderName');
  }

  final questItem = details['questItem'];
  final embeddedItem = details['item'];
  final questItemName = questItem is Map
      ? _text(questItem['name'])
      : embeddedItem is Map
      ? _text(embeddedItem['name'])
      : null;
  if (questItemName != null) facts.add('Item: $questItemName');

  final transferItem = details['transferItem'];
  if (transferItem is Map) {
    final count = transferItem['count'];
    if (count is int && count >= 0) facts.add('Count: $count');
    final itemId = _identifier(transferItem['item']);
    if (itemId != null) {
      facts.add('Item: ${_catalogName(itemId, activeMode, catalogSnapshot)}');
    }
  }

  final keyId = _identifier(details['key']);
  if (keyId != null) {
    facts.add('Key: ${_catalogName(keyId, activeMode, catalogSnapshot)}');
  }
  final lockType = _text(details['lockType']);
  if (lockType != null) facts.add('Lock type: $lockType');
  final needsPower = details['needsPower'];
  if (needsPower is bool) {
    facts.add(needsPower ? 'Needs power' : 'Does not need power');
  }

  final chance = details['spawnChance'];
  if (marker.category == 'bosses' &&
      chance is num &&
      chance.isFinite &&
      chance >= 0 &&
      chance <= 1) {
    final percentage = chance * 100;
    final formatted = percentage == percentage.roundToDouble()
        ? percentage.toInt().toString()
        : percentage.toString();
    facts.add('Spawn chance: $formatted%');
  }

  for (final name in _linkedSwitchNames(marker, mapMarkers)) {
    facts.add('Switch: $name');
  }

  return MarkerPresentation(
    title: title,
    categoryLabel: categoryLabel,
    facts: facts,
  );
}

String _displayName(PreparedMarker marker, String categoryLabel) {
  final name = marker.name.trim();
  final sourceZoneName = _text(marker.details['zoneName']);
  if (name.isEmpty ||
      name.toLowerCase() == marker.category.toLowerCase() ||
      name.toLowerCase() == marker.filterKey.toLowerCase() ||
      (marker.category == 'spawns' && name == sourceZoneName) ||
      name == marker.id ||
      name == marker.details['id'] ||
      name == marker.source['mapId'] ||
      name == marker.source['path']) {
    return categoryLabel;
  }
  return name;
}

String? _text(Object? value) =>
    value is String && value.trim().isNotEmpty ? value.trim() : null;

String? _identifier(Object? value) {
  if (value is String) return _text(value);
  if (value is Map) return _text(value['id']);
  return null;
}

String _catalogName(String id, GameMode activeMode, CatalogSnapshot? snapshot) {
  if (activeMode != GameMode.unknown && snapshot?.mode == activeMode) {
    final item = snapshot!.items[id];
    final name = item?.id == id ? item?.name.trim() : null;
    if (name != null && name.isNotEmpty && name != id) return name;
  }
  return 'unavailable';
}

Set<String> _ids(Object? value) {
  final result = <String>{};
  void addIds(Object? current) {
    if (current is String) {
      final id = _text(current);
      if (id != null) result.add(id);
    } else if (current is Map) {
      final id = _text(current['id']);
      if (id != null) result.add(id);
    } else if (current is List) {
      for (final item in current) {
        addIds(item);
      }
    }
  }

  addIds(value);
  return result;
}

Set<String> _markerIds(PreparedMarker marker) => {
  marker.id,
  if (_text(marker.details['id']) case final String id) id,
};

Iterable<String> _linkedSwitchNames(
  PreparedMarker marker,
  Iterable<PreparedMarker> mapMarkers,
) sync* {
  final mapId = _text(marker.source['mapId']);
  if (mapId == null) return;
  final markerIds = _markerIds(marker);
  final linked = _ids(marker.details['switches'])
    ..addAll(_ids(marker.details['switch']));
  final seen = <String>{};
  for (final candidate in mapMarkers) {
    if (candidate.category != 'switches' ||
        _text(candidate.source['mapId']) != mapId) {
      continue;
    }
    final candidateIds = _markerIds(candidate);
    final pointsToMarker = _ids(candidate.details['activates'])
        .any(markerIds.contains);
    final isLinked = linked.any(candidateIds.contains) || pointsToMarker;
    if (!isLinked || !seen.add(candidate.id)) continue;
    yield _displayName(candidate, markerCategoryLabel(candidate.filterKey));
  }
}
