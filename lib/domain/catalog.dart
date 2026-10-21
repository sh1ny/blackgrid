import 'title_matching.dart' show normaliseTitle;

enum GameMode {
  unknown,
  pvp,
  pve,
  seasonal;

  String? get catalogRoute => switch (this) {
    unknown => null,
    pvp => 'regular',
    pve => 'pve',
    seasonal => 'pvp-season',
  };
  String? get trackerMode => switch (this) {
    unknown => null,
    pvp => 'pvp',
    pve => 'pve',
    seasonal => 'seasonal',
  };
}

enum RequirementKind { task, hideout, craft, barter }

class CashOffer {
  const CashOffer({
    required this.traderId,
    required this.currency,
    required this.price,
    this.barter = false,
  });
  final String traderId;
  final String currency;
  final num? price;
  final bool barter;
  Map<String, Object?> toJson() => {
    'traderId': traderId,
    'currency': currency,
    'price': price,
    'barter': barter,
  };
  factory CashOffer.fromJson(Map<String, dynamic> j) => CashOffer(
    traderId: j['traderId'] as String,
    currency: j['currency'] as String,
    price: j['price'] as num?,
    barter: j['barter'] as bool,
  );
}

class CatalogItem {
  CatalogItem({
    required this.id,
    required this.name,
    this.shortName,
    required this.normalizedName,
    this.width,
    this.height,
    this.noFlea,
    this.minLevelForFlea,
    this.fleaPrice,
    this.quoteAt,
    this.updatedAt,
    this.iconLink,
    Iterable<CashOffer> sellOffers = const [],
  }) : sellOffers = List.unmodifiable(sellOffers);
  final String id, name, normalizedName;
  final String? shortName;

  /// The item's picture URL on `assets.tarkov.dev`, or null for no picture.
  ///
  /// Only values accepted by [acceptedIconLink] are stored here.
  final String? iconLink;
  final num? width, height, fleaPrice;
  final bool? noFlea;
  final int? minLevelForFlea;
  final DateTime? quoteAt, updatedAt;
  final List<CashOffer> sellOffers;
  num? get slots {
    if (width == null ||
        height == null ||
        !width!.isFinite ||
        !height!.isFinite ||
        width! <= 0 ||
        height! <= 0) {
      return null;
    }
    final area = width! * height!;
    return area.isFinite && area > 0 ? area : null;
  }

  Map<String, Object?> toJson() => {
    'id': id,
    'name': name,
    'shortName': shortName,
    'normalizedName': normalizedName,
    'width': width,
    'height': height,
    'noFlea': noFlea,
    'minLevelForFlea': minLevelForFlea,
    'fleaPrice': fleaPrice,
    'quoteAt': quoteAt?.toIso8601String(),
    'updatedAt': updatedAt?.toIso8601String(),
    if (iconLink != null) 'iconLink': iconLink,
    'sellOffers': sellOffers.map((v) => v.toJson()).toList(),
  };
  factory CatalogItem.fromJson(Map<String, dynamic> j) => CatalogItem(
    id: j['id'] as String,
    name: j['name'] as String,
    shortName: j['shortName'] as String?,
    normalizedName: j['normalizedName'] as String,
    width: j['width'] as num?,
    height: j['height'] as num?,
    noFlea: j['noFlea'] as bool?,
    minLevelForFlea: j['minLevelForFlea'] as int?,
    fleaPrice: j['fleaPrice'] as num?,
    quoteAt: _date(j['quoteAt']),
    updatedAt: _date(j['updatedAt']),
    iconLink: acceptedIconLink(j['iconLink']),
    sellOffers: (j['sellOffers'] as List).map(
      (v) => CashOffer.fromJson(Map<String, dynamic>.from(v as Map)),
    ),
  );
}

/// Returns [value] when it is an acceptable item-icon link, otherwise null.
///
/// A link is acceptable when it is a string that parses as an absolute
/// `https` URL on `assets.tarkov.dev`, with no user info, explicit port, query
/// or fragment (even an empty `?` or `#`), and is not the
/// `/unknown-item-icon.jpg` placeholder, which means the item has no picture.
/// A value of any other type, or one that does not parse, yields null; it
/// never throws.
String? acceptedIconLink(Object? value) {
  // Uri drops a default port (`:443`), so the raw text is checked as well to
  // reject any explicit port or user info.
  if (value is! String || !value.startsWith('https://assets.tarkov.dev/')) {
    return null;
  }
  final uri = Uri.tryParse(value);
  if (uri == null ||
      uri.scheme != 'https' ||
      uri.host != 'assets.tarkov.dev' ||
      uri.hasPort ||
      uri.userInfo.isNotEmpty ||
      uri.hasQuery ||
      uri.hasFragment ||
      uri.path == '/unknown-item-icon.jpg') {
    return null;
  }
  return value;
}

class CatalogTrader {
  const CatalogTrader({required this.id, this.name});
  final String id;
  final String? name;
  Map<String, Object?> toJson() => {'id': id, 'name': name};
  factory CatalogTrader.fromJson(Map<String, dynamic> j) =>
      CatalogTrader(id: j['id'] as String, name: j['name'] as String?);
}

class RequirementGate {
  RequirementGate({
    this.minPlayerLevel,
    this.faction,
    Iterable<int>? editions,
    Iterable<String>? editionIds,
    Map<String, List<String>>? taskStatuses,
    Map<String, int>? stations,
    this.unknownTraderOrSkill = false,
    this.incomplete = false,
  }) : editions = editions == null ? null : List.unmodifiable(editions),
       editionIds = editionIds == null ? null : List.unmodifiable(editionIds),
       taskStatuses = taskStatuses == null
           ? null
           : Map.unmodifiable(
               taskStatuses.map(
                 (k, v) => MapEntry(k, List<String>.unmodifiable(v)),
               ),
             ),
       stations = stations == null ? null : Map.unmodifiable(stations);
  final int? minPlayerLevel;
  final String? faction;
  final List<int>? editions;
  final List<String>? editionIds;
  final Map<String, List<String>>? taskStatuses;
  final Map<String, int>? stations;
  final bool unknownTraderOrSkill, incomplete;
  Map<String, Object?> toJson() => {
    'minPlayerLevel': minPlayerLevel,
    'faction': faction,
    'editions': editions,
    'editionIds': editionIds,
    'taskStatuses': taskStatuses,
    'stations': stations,
    'unknownTraderOrSkill': unknownTraderOrSkill,
    'incomplete': incomplete,
  };
  factory RequirementGate.fromJson(Map<String, dynamic> j) => RequirementGate(
    minPlayerLevel: j['minPlayerLevel'] as int?,
    faction: j['faction'] as String?,
    editions: (j['editions'] as List?)?.cast<int>(),
    editionIds: (j['editionIds'] as List?)?.cast<String>(),
    taskStatuses: (j['taskStatuses'] as Map?)?.map(
      (k, v) => MapEntry(k as String, (v as List).cast<String>()),
    ),
    stations: (j['stations'] as Map?)?.cast<String, int>(),
    unknownTraderOrSkill: j['unknownTraderOrSkill'] as bool,
    incomplete: j['incomplete'] as bool,
  );
}

class ItemRequirement {
  ItemRequirement({
    required this.kind,
    required this.sourceId,
    required this.sourceName,
    required this.id,
    required Iterable<String> itemIds,
    required Iterable<String> progressIds,
    this.completionId,
    this.ambiguousProgressIdentity = false,
    this.count,
    this.foundInRaid,
    required this.gate,
    this.optional = false,
    this.stationId,
    this.stationLevel,
  }) : itemIds = List.unmodifiable(itemIds),
       progressIds = List.unmodifiable(progressIds);
  final RequirementKind kind;
  final String sourceId, sourceName, id;
  final List<String> itemIds, progressIds;
  final String? completionId;
  // Tracker objective progress is keyed only by raw objective ID. A shared ID
  // cannot establish completion or quantity for any individual task owner.
  final bool ambiguousProgressIdentity;
  final num? count;
  final bool? foundInRaid;
  final RequirementGate gate;
  final bool optional;
  final String? stationId;
  final int? stationLevel;
  Map<String, Object?> toJson() => {
    'kind': kind.name,
    'sourceId': sourceId,
    'sourceName': sourceName,
    'id': id,
    'itemIds': itemIds,
    'progressIds': progressIds,
    'completionId': completionId,
    'ambiguousProgressIdentity': ambiguousProgressIdentity,
    'count': count,
    'foundInRaid': foundInRaid,
    'gate': gate.toJson(),
    'optional': optional,
    'stationId': stationId,
    'stationLevel': stationLevel,
  };
  factory ItemRequirement.fromJson(Map<String, dynamic> j) => ItemRequirement(
    kind: RequirementKind.values.byName(j['kind'] as String),
    sourceId: j['sourceId'] as String,
    sourceName: j['sourceName'] as String,
    id: j['id'] as String,
    itemIds: (j['itemIds'] as List).cast<String>(),
    progressIds: (j['progressIds'] as List).cast<String>(),
    completionId: j['completionId'] as String?,
    ambiguousProgressIdentity: j['ambiguousProgressIdentity'] as bool? ?? false,
    count: j['count'] as num?,
    foundInRaid: j['foundInRaid'] as bool?,
    gate: RequirementGate.fromJson(Map<String, dynamic>.from(j['gate'] as Map)),
    optional: j['optional'] as bool,
    stationId: j['stationId'] as String?,
    stationLevel: j['stationLevel'] as int?,
  );
}

class CatalogSnapshot {
  CatalogSnapshot({
    required this.mode,
    required this.revision,
    required this.observedAt,
    this.source = 'json.tarkov.dev',
    this.schemaVersion = 1,
    this.normalizerVersion = 1,
    required Map<String, CatalogItem> items,
    required Map<String, CatalogTrader> traders,
    required Iterable<ItemRequirement> requirements,
    Map<String, DateTime?> sourceTimestamps = const {},
    Iterable<String> localizationErrors = const [],
    Map<String, int> datasetCounts = const {},
  }) : items = Map.unmodifiable(items),
       traders = Map.unmodifiable(traders),
       requirements = List.unmodifiable(requirements),
       sourceTimestamps = Map.unmodifiable(sourceTimestamps),
       localizationErrors = List.unmodifiable(localizationErrors),
       datasetCounts = Map.unmodifiable(datasetCounts) {
    final index = <String, List<ItemRequirement>>{};
    for (final r in this.requirements) {
      for (final id in r.itemIds) {
        (index[id] ??= []).add(r);
      }
    }
    requirementIndex = Map.unmodifiable(
      index.map(
        (k, v) => MapEntry(
          k,
          List<ItemRequirement>.unmodifiable(v..sort(compareRequirements)),
        ),
      ),
    );
    final sorted = this.items.values.toList()
      ..sort((a, b) => a.id.compareTo(b.id));
    searchIndex = List.unmodifiable(
      sorted.map(
        (v) => (
          v,
          '${v.id}\n${v.name}\n${v.shortName ?? ''}\n${v.normalizedName}'
              .toLowerCase(),
        ),
      ),
    );
  }
  final GameMode mode;
  final String source, revision;
  final int schemaVersion, normalizerVersion;
  final DateTime observedAt;
  final Map<String, CatalogItem> items;
  final Map<String, CatalogTrader> traders;
  final List<ItemRequirement> requirements;

  /// Source-time evidence for each of the six datasets, for display only.
  ///
  /// The `items` entry is the newest per-item `updated` value. The other
  /// datasets carry no source time, so their entries are null. These times
  /// never grant or revoke [authoritativeAt].
  final Map<String, DateTime?> sourceTimestamps;
  final List<String> localizationErrors;
  final Map<String, int> datasetCounts;
  late final Map<String, List<ItemRequirement>> requirementIndex;
  late final List<(CatalogItem, String)> searchIndex;

  /// Whether this snapshot may back decisions at [now].
  ///
  /// Freshness is measured from download time: the snapshot must come from
  /// the supported source, schema and normalizer for a known mode, and [now]
  /// must be no earlier than [observedAt] and at most 24 hours after it.
  /// [sourceTimestamps] play no part.
  bool authoritativeAt(DateTime now) =>
      source == 'json.tarkov.dev' &&
      schemaVersion == 1 &&
      normalizerVersion == 1 &&
      mode != GameMode.unknown &&
      !now.isBefore(observedAt) &&
      now.difference(observedAt) <= const Duration(hours: 24);
  List<CatalogItem> search(String query) {
    final q = query.trim().toLowerCase();
    if (q.isEmpty) return const [];
    return List.unmodifiable(
      searchIndex.where((v) => v.$2.contains(q)).map((v) => v.$1),
    );
  }

  /// Finds items whose search text holds every word of [text], in any order.
  ///
  /// [text] is normalised with [normaliseTitle] and split on whitespace. An
  /// item matches when its lower-cased ID, name, short name and normalised
  /// name together contain each word as a substring. Results come in ID order,
  /// at most [limit] of them, and are empty when [text] holds no words.
  List<CatalogItem> searchWords(String text, {int limit = 8}) {
    final words = normaliseTitle(text)
        .split(' ')
        .where((w) => w.isNotEmpty)
        .toList();
    if (words.isEmpty || limit <= 0) return const [];
    final found = <CatalogItem>[];
    for (final (item, haystack) in searchIndex) {
      if (words.every(haystack.contains)) {
        found.add(item);
        if (found.length >= limit) break;
      }
    }
    return List.unmodifiable(found);
  }

  Map<String, Object?> toJson() => {
    'mode': mode.name,
    'source': source,
    'revision': revision,
    'schemaVersion': schemaVersion,
    'normalizerVersion': normalizerVersion,
    'observedAt': observedAt.toIso8601String(),
    'items': items.map((k, v) => MapEntry(k, v.toJson())),
    'traders': traders.map((k, v) => MapEntry(k, v.toJson())),
    'requirements': requirements.map((v) => v.toJson()).toList(),
    'sourceTimestamps': sourceTimestamps.map(
      (k, v) => MapEntry(k, v?.toIso8601String()),
    ),
    'localizationErrors': localizationErrors,
    'datasetCounts': datasetCounts,
  };
  factory CatalogSnapshot.fromJson(Map<String, dynamic> j) {
    if (j['schemaVersion'] != 1 || j['normalizerVersion'] != 1) {
      throw const FormatException('Unsupported catalog schema');
    }
    return CatalogSnapshot(
      mode: GameMode.values.byName(j['mode'] as String),
      source: j['source'] as String,
      revision: j['revision'] as String,
      observedAt: DateTime.parse(j['observedAt'] as String),
      items: (j['items'] as Map).map(
        (k, v) => MapEntry(
          k as String,
          CatalogItem.fromJson(Map<String, dynamic>.from(v as Map)),
        ),
      ),
      traders: (j['traders'] as Map).map(
        (k, v) => MapEntry(
          k as String,
          CatalogTrader.fromJson(Map<String, dynamic>.from(v as Map)),
        ),
      ),
      requirements: (j['requirements'] as List).map(
        (v) => ItemRequirement.fromJson(Map<String, dynamic>.from(v as Map)),
      ),
      sourceTimestamps: (j['sourceTimestamps'] as Map).map(
        (k, v) => MapEntry(k as String, _date(v)),
      ),
      localizationErrors: (j['localizationErrors'] as List).cast<String>(),
      datasetCounts: (j['datasetCounts'] as Map).cast<String, int>(),
    );
  }
}

int compareRequirements(ItemRequirement a, ItemRequirement b) {
  final k = a.kind.index.compareTo(b.kind.index);
  if (k != 0) return k;
  final s = a.sourceId.compareTo(b.sourceId);
  return s != 0 ? s : a.id.compareTo(b.id);
}

DateTime? _date(Object? v) => v == null ? null : DateTime.parse(v as String);
