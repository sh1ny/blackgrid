/// Metadata consumed by Map search, quest eligibility and marker details.
///
/// It retains source identities rather than inferring relationships from names
/// or proximity. Geometry is deliberately not a searchable metadata field.
class MapMarkerMetadata {
  MapMarkerMetadata({
    required this.name,
    required this.type,
    required this.category,
    required Map<String, dynamic> details,
    required Map<String, dynamic> source,
  }) : fields = Map.unmodifiable({
         for (final entry in details.entries)
           if (!const {
             'position',
             'outline',
             'size',
             'bottom',
             'top',
           }.contains(entry.key))
             entry.key: entry.value,
       }) {
    sourceId = _text(details['id']);
    final quests = <Map<String, dynamic>>[];
    for (final key in ['quest', 'task', 'quests', 'tasks']) {
      final value = details[key];
      if (value is Map<String, dynamic>) quests.add(value);
      if (value is List) quests.addAll(value.whereType<Map<String, dynamic>>());
    }
    questNames = List.unmodifiable([
      for (final quest in quests)
        if (_text(quest['name']) case final String name) name,
      if (_text(details['questName']) case final String name) name,
      if (_text(details['taskName']) case final String name) name,
    ]);
    traders = List.unmodifiable([
      for (final quest in quests) ..._names(quest['trader']),
      ..._names(details['trader']),
    ]);
    questLinks = List.unmodifiable([
      for (final quest in quests)
        if (_text(quest['wikiLink'] ?? quest['link']) case final String link)
          link,
      if (_text(details['wikiLink']) case final String link) link,
    ]);
    linkedSwitchIds = Set.unmodifiable(_ids(details['switches']));
    activatedIds = Set.unmodifiable(_ids(details['activates']));
    isQuest =
        type == 'QuestItems' ||
        type == 'QuestObjectives' ||
        category.toLowerCase().contains('quest');
    final terms = <String>[name, type, category];
    _searchValues(fields, terms);
    // Provenance has source identity but not invented human-facing metadata.
    if (_text(source['name']) case final String name) terms.add(name);
    searchText = terms.join(' ').toLowerCase();
  }

  final String name;
  final String type;
  final String category;
  final Map<String, dynamic> fields;
  late final String? sourceId;
  late final List<String> questNames;
  late final List<String> traders;
  late final List<String> questLinks;
  late final Set<String> linkedSwitchIds;
  late final Set<String> activatedIds;
  late final bool isQuest;
  late final String searchText;

  bool matchesSearch(List<String> terms) =>
      terms.isEmpty || terms.any(searchText.contains);

  bool matchesQuest({required String name, required String trader}) {
    if (!isQuest) return true;
    final query = name.trim().toLowerCase();
    final traderQuery = trader.trim().toLowerCase();
    return (query.isEmpty ||
            questNames.any((name) => name.toLowerCase().contains(query))) &&
        (traderQuery.isEmpty ||
            traderQuery == 'all' ||
            traders.any((name) => name.toLowerCase() == traderQuery));
  }
}

/// Commas are OR separators; empty terms do not accidentally match everything.
List<String> mapSearchTerms(String value) => List.unmodifiable(
  value
      .split(',')
      .map((term) => term.trim().toLowerCase())
      .where((term) => term.isNotEmpty),
);

String? _text(Object? value) =>
    value is String && value.trim().isNotEmpty ? value.trim() : null;

Iterable<String> _names(Object? value) sync* {
  if (_text(value) case final String name) yield name;
  if (value is Map) {
    if (_text(value['name']) case final String name) yield name;
  }
  if (value is List) {
    for (final item in value) {
      yield* _names(item);
    }
  }
}

Iterable<String> _ids(Object? value) sync* {
  if (_text(value) case final String id) yield id;
  if (value is Map) {
    if (_text(value['id']) case final String id) yield id;
  }
  if (value is List) {
    for (final item in value) {
      yield* _ids(item);
    }
  }
}

void _searchValues(Object? value, List<String> result) {
  if (value is String || value is num || value is bool) {
    result.add(value.toString());
  } else if (value is Map) {
    for (final entry in value.entries) {
      if (!const {'position', 'outline', 'size'}.contains(entry.key)) {
        _searchValues(entry.value, result);
      }
    }
  } else if (value is List) {
    for (final item in value) {
      _searchValues(item, result);
    }
  }
}
