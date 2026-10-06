// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'database.dart';

// ignore_for_file: type=lint
class $PreferencesTable extends Preferences
    with TableInfo<$PreferencesTable, Preference> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $PreferencesTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<int> id = GeneratedColumn<int>(
    'id',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _payloadMeta = const VerificationMeta(
    'payload',
  );
  @override
  late final GeneratedColumn<String> payload = GeneratedColumn<String>(
    'payload',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  @override
  List<GeneratedColumn> get $columns => [id, payload];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'preferences';
  @override
  VerificationContext validateIntegrity(
    Insertable<Preference> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    }
    if (data.containsKey('payload')) {
      context.handle(
        _payloadMeta,
        payload.isAcceptableOrUnknown(data['payload']!, _payloadMeta),
      );
    } else if (isInserting) {
      context.missing(_payloadMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  Preference map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return Preference(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}id'],
      )!,
      payload: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}payload'],
      )!,
    );
  }

  @override
  $PreferencesTable createAlias(String alias) {
    return $PreferencesTable(attachedDatabase, alias);
  }
}

class Preference extends DataClass implements Insertable<Preference> {
  final int id;
  final String payload;
  const Preference({required this.id, required this.payload});
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<int>(id);
    map['payload'] = Variable<String>(payload);
    return map;
  }

  PreferencesCompanion toCompanion(bool nullToAbsent) {
    return PreferencesCompanion(id: Value(id), payload: Value(payload));
  }

  factory Preference.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return Preference(
      id: serializer.fromJson<int>(json['id']),
      payload: serializer.fromJson<String>(json['payload']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<int>(id),
      'payload': serializer.toJson<String>(payload),
    };
  }

  Preference copyWith({int? id, String? payload}) =>
      Preference(id: id ?? this.id, payload: payload ?? this.payload);
  Preference copyWithCompanion(PreferencesCompanion data) {
    return Preference(
      id: data.id.present ? data.id.value : this.id,
      payload: data.payload.present ? data.payload.value : this.payload,
    );
  }

  @override
  String toString() {
    return (StringBuffer('Preference(')
          ..write('id: $id, ')
          ..write('payload: $payload')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(id, payload);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is Preference &&
          other.id == this.id &&
          other.payload == this.payload);
}

class PreferencesCompanion extends UpdateCompanion<Preference> {
  final Value<int> id;
  final Value<String> payload;
  const PreferencesCompanion({
    this.id = const Value.absent(),
    this.payload = const Value.absent(),
  });
  PreferencesCompanion.insert({
    this.id = const Value.absent(),
    required String payload,
  }) : payload = Value(payload);
  static Insertable<Preference> custom({
    Expression<int>? id,
    Expression<String>? payload,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (payload != null) 'payload': payload,
    });
  }

  PreferencesCompanion copyWith({Value<int>? id, Value<String>? payload}) {
    return PreferencesCompanion(
      id: id ?? this.id,
      payload: payload ?? this.payload,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<int>(id.value);
    }
    if (payload.present) {
      map['payload'] = Variable<String>(payload.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('PreferencesCompanion(')
          ..write('id: $id, ')
          ..write('payload: $payload')
          ..write(')'))
        .toString();
  }
}

class $PinRecordsTable extends PinRecords
    with TableInfo<$PinRecordsTable, PinRecord> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $PinRecordsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _mapIdMeta = const VerificationMeta('mapId');
  @override
  late final GeneratedColumn<String> mapId = GeneratedColumn<String>(
    'map_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _pinIdMeta = const VerificationMeta('pinId');
  @override
  late final GeneratedColumn<String> pinId = GeneratedColumn<String>(
    'pin_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _payloadMeta = const VerificationMeta(
    'payload',
  );
  @override
  late final GeneratedColumn<String> payload = GeneratedColumn<String>(
    'payload',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  @override
  List<GeneratedColumn> get $columns => [mapId, pinId, payload];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'pin_records';
  @override
  VerificationContext validateIntegrity(
    Insertable<PinRecord> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('map_id')) {
      context.handle(
        _mapIdMeta,
        mapId.isAcceptableOrUnknown(data['map_id']!, _mapIdMeta),
      );
    } else if (isInserting) {
      context.missing(_mapIdMeta);
    }
    if (data.containsKey('pin_id')) {
      context.handle(
        _pinIdMeta,
        pinId.isAcceptableOrUnknown(data['pin_id']!, _pinIdMeta),
      );
    } else if (isInserting) {
      context.missing(_pinIdMeta);
    }
    if (data.containsKey('payload')) {
      context.handle(
        _payloadMeta,
        payload.isAcceptableOrUnknown(data['payload']!, _payloadMeta),
      );
    } else if (isInserting) {
      context.missing(_payloadMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {mapId, pinId};
  @override
  PinRecord map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return PinRecord(
      mapId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}map_id'],
      )!,
      pinId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}pin_id'],
      )!,
      payload: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}payload'],
      )!,
    );
  }

  @override
  $PinRecordsTable createAlias(String alias) {
    return $PinRecordsTable(attachedDatabase, alias);
  }
}

class PinRecord extends DataClass implements Insertable<PinRecord> {
  final String mapId;
  final String pinId;
  final String payload;
  const PinRecord({
    required this.mapId,
    required this.pinId,
    required this.payload,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['map_id'] = Variable<String>(mapId);
    map['pin_id'] = Variable<String>(pinId);
    map['payload'] = Variable<String>(payload);
    return map;
  }

  PinRecordsCompanion toCompanion(bool nullToAbsent) {
    return PinRecordsCompanion(
      mapId: Value(mapId),
      pinId: Value(pinId),
      payload: Value(payload),
    );
  }

  factory PinRecord.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return PinRecord(
      mapId: serializer.fromJson<String>(json['mapId']),
      pinId: serializer.fromJson<String>(json['pinId']),
      payload: serializer.fromJson<String>(json['payload']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'mapId': serializer.toJson<String>(mapId),
      'pinId': serializer.toJson<String>(pinId),
      'payload': serializer.toJson<String>(payload),
    };
  }

  PinRecord copyWith({String? mapId, String? pinId, String? payload}) =>
      PinRecord(
        mapId: mapId ?? this.mapId,
        pinId: pinId ?? this.pinId,
        payload: payload ?? this.payload,
      );
  PinRecord copyWithCompanion(PinRecordsCompanion data) {
    return PinRecord(
      mapId: data.mapId.present ? data.mapId.value : this.mapId,
      pinId: data.pinId.present ? data.pinId.value : this.pinId,
      payload: data.payload.present ? data.payload.value : this.payload,
    );
  }

  @override
  String toString() {
    return (StringBuffer('PinRecord(')
          ..write('mapId: $mapId, ')
          ..write('pinId: $pinId, ')
          ..write('payload: $payload')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(mapId, pinId, payload);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is PinRecord &&
          other.mapId == this.mapId &&
          other.pinId == this.pinId &&
          other.payload == this.payload);
}

class PinRecordsCompanion extends UpdateCompanion<PinRecord> {
  final Value<String> mapId;
  final Value<String> pinId;
  final Value<String> payload;
  final Value<int> rowid;
  const PinRecordsCompanion({
    this.mapId = const Value.absent(),
    this.pinId = const Value.absent(),
    this.payload = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  PinRecordsCompanion.insert({
    required String mapId,
    required String pinId,
    required String payload,
    this.rowid = const Value.absent(),
  }) : mapId = Value(mapId),
       pinId = Value(pinId),
       payload = Value(payload);
  static Insertable<PinRecord> custom({
    Expression<String>? mapId,
    Expression<String>? pinId,
    Expression<String>? payload,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (mapId != null) 'map_id': mapId,
      if (pinId != null) 'pin_id': pinId,
      if (payload != null) 'payload': payload,
      if (rowid != null) 'rowid': rowid,
    });
  }

  PinRecordsCompanion copyWith({
    Value<String>? mapId,
    Value<String>? pinId,
    Value<String>? payload,
    Value<int>? rowid,
  }) {
    return PinRecordsCompanion(
      mapId: mapId ?? this.mapId,
      pinId: pinId ?? this.pinId,
      payload: payload ?? this.payload,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (mapId.present) {
      map['map_id'] = Variable<String>(mapId.value);
    }
    if (pinId.present) {
      map['pin_id'] = Variable<String>(pinId.value);
    }
    if (payload.present) {
      map['payload'] = Variable<String>(payload.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('PinRecordsCompanion(')
          ..write('mapId: $mapId, ')
          ..write('pinId: $pinId, ')
          ..write('payload: $payload, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $ActivityRecordsTable extends ActivityRecords
    with TableInfo<$ActivityRecordsTable, ActivityRecord> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $ActivityRecordsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _itemIdMeta = const VerificationMeta('itemId');
  @override
  late final GeneratedColumn<String> itemId = GeneratedColumn<String>(
    'item_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _modeMeta = const VerificationMeta('mode');
  @override
  late final GeneratedColumn<String> mode = GeneratedColumn<String>(
    'mode',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _sourceMeta = const VerificationMeta('source');
  @override
  late final GeneratedColumn<String> source = GeneratedColumn<String>(
    'source',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _observedAtMeta = const VerificationMeta(
    'observedAt',
  );
  @override
  late final GeneratedColumn<DateTime> observedAt = GeneratedColumn<DateTime>(
    'observed_at',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _revisionMeta = const VerificationMeta(
    'revision',
  );
  @override
  late final GeneratedColumn<int> revision = GeneratedColumn<int>(
    'revision',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  @override
  List<GeneratedColumn> get $columns => [
    itemId,
    mode,
    source,
    observedAt,
    revision,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'activity_records';
  @override
  VerificationContext validateIntegrity(
    Insertable<ActivityRecord> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('item_id')) {
      context.handle(
        _itemIdMeta,
        itemId.isAcceptableOrUnknown(data['item_id']!, _itemIdMeta),
      );
    } else if (isInserting) {
      context.missing(_itemIdMeta);
    }
    if (data.containsKey('mode')) {
      context.handle(
        _modeMeta,
        mode.isAcceptableOrUnknown(data['mode']!, _modeMeta),
      );
    } else if (isInserting) {
      context.missing(_modeMeta);
    }
    if (data.containsKey('source')) {
      context.handle(
        _sourceMeta,
        source.isAcceptableOrUnknown(data['source']!, _sourceMeta),
      );
    } else if (isInserting) {
      context.missing(_sourceMeta);
    }
    if (data.containsKey('observed_at')) {
      context.handle(
        _observedAtMeta,
        observedAt.isAcceptableOrUnknown(data['observed_at']!, _observedAtMeta),
      );
    } else if (isInserting) {
      context.missing(_observedAtMeta);
    }
    if (data.containsKey('revision')) {
      context.handle(
        _revisionMeta,
        revision.isAcceptableOrUnknown(data['revision']!, _revisionMeta),
      );
    } else if (isInserting) {
      context.missing(_revisionMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {itemId, mode};
  @override
  ActivityRecord map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return ActivityRecord(
      itemId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}item_id'],
      )!,
      mode: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}mode'],
      )!,
      source: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}source'],
      )!,
      observedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}observed_at'],
      )!,
      revision: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}revision'],
      )!,
    );
  }

  @override
  $ActivityRecordsTable createAlias(String alias) {
    return $ActivityRecordsTable(attachedDatabase, alias);
  }
}

class ActivityRecord extends DataClass implements Insertable<ActivityRecord> {
  final String itemId;
  final String mode;
  final String source;
  final DateTime observedAt;
  final int revision;
  const ActivityRecord({
    required this.itemId,
    required this.mode,
    required this.source,
    required this.observedAt,
    required this.revision,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['item_id'] = Variable<String>(itemId);
    map['mode'] = Variable<String>(mode);
    map['source'] = Variable<String>(source);
    map['observed_at'] = Variable<DateTime>(observedAt);
    map['revision'] = Variable<int>(revision);
    return map;
  }

  ActivityRecordsCompanion toCompanion(bool nullToAbsent) {
    return ActivityRecordsCompanion(
      itemId: Value(itemId),
      mode: Value(mode),
      source: Value(source),
      observedAt: Value(observedAt),
      revision: Value(revision),
    );
  }

  factory ActivityRecord.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return ActivityRecord(
      itemId: serializer.fromJson<String>(json['itemId']),
      mode: serializer.fromJson<String>(json['mode']),
      source: serializer.fromJson<String>(json['source']),
      observedAt: serializer.fromJson<DateTime>(json['observedAt']),
      revision: serializer.fromJson<int>(json['revision']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'itemId': serializer.toJson<String>(itemId),
      'mode': serializer.toJson<String>(mode),
      'source': serializer.toJson<String>(source),
      'observedAt': serializer.toJson<DateTime>(observedAt),
      'revision': serializer.toJson<int>(revision),
    };
  }

  ActivityRecord copyWith({
    String? itemId,
    String? mode,
    String? source,
    DateTime? observedAt,
    int? revision,
  }) => ActivityRecord(
    itemId: itemId ?? this.itemId,
    mode: mode ?? this.mode,
    source: source ?? this.source,
    observedAt: observedAt ?? this.observedAt,
    revision: revision ?? this.revision,
  );
  ActivityRecord copyWithCompanion(ActivityRecordsCompanion data) {
    return ActivityRecord(
      itemId: data.itemId.present ? data.itemId.value : this.itemId,
      mode: data.mode.present ? data.mode.value : this.mode,
      source: data.source.present ? data.source.value : this.source,
      observedAt: data.observedAt.present
          ? data.observedAt.value
          : this.observedAt,
      revision: data.revision.present ? data.revision.value : this.revision,
    );
  }

  @override
  String toString() {
    return (StringBuffer('ActivityRecord(')
          ..write('itemId: $itemId, ')
          ..write('mode: $mode, ')
          ..write('source: $source, ')
          ..write('observedAt: $observedAt, ')
          ..write('revision: $revision')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(itemId, mode, source, observedAt, revision);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is ActivityRecord &&
          other.itemId == this.itemId &&
          other.mode == this.mode &&
          other.source == this.source &&
          other.observedAt == this.observedAt &&
          other.revision == this.revision);
}

class ActivityRecordsCompanion extends UpdateCompanion<ActivityRecord> {
  final Value<String> itemId;
  final Value<String> mode;
  final Value<String> source;
  final Value<DateTime> observedAt;
  final Value<int> revision;
  final Value<int> rowid;
  const ActivityRecordsCompanion({
    this.itemId = const Value.absent(),
    this.mode = const Value.absent(),
    this.source = const Value.absent(),
    this.observedAt = const Value.absent(),
    this.revision = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  ActivityRecordsCompanion.insert({
    required String itemId,
    required String mode,
    required String source,
    required DateTime observedAt,
    required int revision,
    this.rowid = const Value.absent(),
  }) : itemId = Value(itemId),
       mode = Value(mode),
       source = Value(source),
       observedAt = Value(observedAt),
       revision = Value(revision);
  static Insertable<ActivityRecord> custom({
    Expression<String>? itemId,
    Expression<String>? mode,
    Expression<String>? source,
    Expression<DateTime>? observedAt,
    Expression<int>? revision,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (itemId != null) 'item_id': itemId,
      if (mode != null) 'mode': mode,
      if (source != null) 'source': source,
      if (observedAt != null) 'observed_at': observedAt,
      if (revision != null) 'revision': revision,
      if (rowid != null) 'rowid': rowid,
    });
  }

  ActivityRecordsCompanion copyWith({
    Value<String>? itemId,
    Value<String>? mode,
    Value<String>? source,
    Value<DateTime>? observedAt,
    Value<int>? revision,
    Value<int>? rowid,
  }) {
    return ActivityRecordsCompanion(
      itemId: itemId ?? this.itemId,
      mode: mode ?? this.mode,
      source: source ?? this.source,
      observedAt: observedAt ?? this.observedAt,
      revision: revision ?? this.revision,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (itemId.present) {
      map['item_id'] = Variable<String>(itemId.value);
    }
    if (mode.present) {
      map['mode'] = Variable<String>(mode.value);
    }
    if (source.present) {
      map['source'] = Variable<String>(source.value);
    }
    if (observedAt.present) {
      map['observed_at'] = Variable<DateTime>(observedAt.value);
    }
    if (revision.present) {
      map['revision'] = Variable<int>(revision.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('ActivityRecordsCompanion(')
          ..write('itemId: $itemId, ')
          ..write('mode: $mode, ')
          ..write('source: $source, ')
          ..write('observedAt: $observedAt, ')
          ..write('revision: $revision, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $CatalogRecordsTable extends CatalogRecords
    with TableInfo<$CatalogRecordsTable, CatalogRecord> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $CatalogRecordsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<int> id = GeneratedColumn<int>(
    'id',
    aliasedName,
    false,
    hasAutoIncrement: true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'PRIMARY KEY AUTOINCREMENT',
    ),
  );
  static const VerificationMeta _cacheKeyMeta = const VerificationMeta(
    'cacheKey',
  );
  @override
  late final GeneratedColumn<String> cacheKey = GeneratedColumn<String>(
    'cache_key',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _revisionMeta = const VerificationMeta(
    'revision',
  );
  @override
  late final GeneratedColumn<String> revision = GeneratedColumn<String>(
    'revision',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _payloadMeta = const VerificationMeta(
    'payload',
  );
  @override
  late final GeneratedColumn<String> payload = GeneratedColumn<String>(
    'payload',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  @override
  List<GeneratedColumn> get $columns => [id, cacheKey, revision, payload];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'catalog_records';
  @override
  VerificationContext validateIntegrity(
    Insertable<CatalogRecord> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    }
    if (data.containsKey('cache_key')) {
      context.handle(
        _cacheKeyMeta,
        cacheKey.isAcceptableOrUnknown(data['cache_key']!, _cacheKeyMeta),
      );
    } else if (isInserting) {
      context.missing(_cacheKeyMeta);
    }
    if (data.containsKey('revision')) {
      context.handle(
        _revisionMeta,
        revision.isAcceptableOrUnknown(data['revision']!, _revisionMeta),
      );
    } else if (isInserting) {
      context.missing(_revisionMeta);
    }
    if (data.containsKey('payload')) {
      context.handle(
        _payloadMeta,
        payload.isAcceptableOrUnknown(data['payload']!, _payloadMeta),
      );
    } else if (isInserting) {
      context.missing(_payloadMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  List<Set<GeneratedColumn>> get uniqueKeys => [
    {cacheKey, revision},
  ];
  @override
  CatalogRecord map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return CatalogRecord(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}id'],
      )!,
      cacheKey: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}cache_key'],
      )!,
      revision: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}revision'],
      )!,
      payload: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}payload'],
      )!,
    );
  }

  @override
  $CatalogRecordsTable createAlias(String alias) {
    return $CatalogRecordsTable(attachedDatabase, alias);
  }
}

class CatalogRecord extends DataClass implements Insertable<CatalogRecord> {
  final int id;
  final String cacheKey;
  final String revision;
  final String payload;
  const CatalogRecord({
    required this.id,
    required this.cacheKey,
    required this.revision,
    required this.payload,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<int>(id);
    map['cache_key'] = Variable<String>(cacheKey);
    map['revision'] = Variable<String>(revision);
    map['payload'] = Variable<String>(payload);
    return map;
  }

  CatalogRecordsCompanion toCompanion(bool nullToAbsent) {
    return CatalogRecordsCompanion(
      id: Value(id),
      cacheKey: Value(cacheKey),
      revision: Value(revision),
      payload: Value(payload),
    );
  }

  factory CatalogRecord.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return CatalogRecord(
      id: serializer.fromJson<int>(json['id']),
      cacheKey: serializer.fromJson<String>(json['cacheKey']),
      revision: serializer.fromJson<String>(json['revision']),
      payload: serializer.fromJson<String>(json['payload']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<int>(id),
      'cacheKey': serializer.toJson<String>(cacheKey),
      'revision': serializer.toJson<String>(revision),
      'payload': serializer.toJson<String>(payload),
    };
  }

  CatalogRecord copyWith({
    int? id,
    String? cacheKey,
    String? revision,
    String? payload,
  }) => CatalogRecord(
    id: id ?? this.id,
    cacheKey: cacheKey ?? this.cacheKey,
    revision: revision ?? this.revision,
    payload: payload ?? this.payload,
  );
  CatalogRecord copyWithCompanion(CatalogRecordsCompanion data) {
    return CatalogRecord(
      id: data.id.present ? data.id.value : this.id,
      cacheKey: data.cacheKey.present ? data.cacheKey.value : this.cacheKey,
      revision: data.revision.present ? data.revision.value : this.revision,
      payload: data.payload.present ? data.payload.value : this.payload,
    );
  }

  @override
  String toString() {
    return (StringBuffer('CatalogRecord(')
          ..write('id: $id, ')
          ..write('cacheKey: $cacheKey, ')
          ..write('revision: $revision, ')
          ..write('payload: $payload')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(id, cacheKey, revision, payload);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is CatalogRecord &&
          other.id == this.id &&
          other.cacheKey == this.cacheKey &&
          other.revision == this.revision &&
          other.payload == this.payload);
}

class CatalogRecordsCompanion extends UpdateCompanion<CatalogRecord> {
  final Value<int> id;
  final Value<String> cacheKey;
  final Value<String> revision;
  final Value<String> payload;
  const CatalogRecordsCompanion({
    this.id = const Value.absent(),
    this.cacheKey = const Value.absent(),
    this.revision = const Value.absent(),
    this.payload = const Value.absent(),
  });
  CatalogRecordsCompanion.insert({
    this.id = const Value.absent(),
    required String cacheKey,
    required String revision,
    required String payload,
  }) : cacheKey = Value(cacheKey),
       revision = Value(revision),
       payload = Value(payload);
  static Insertable<CatalogRecord> custom({
    Expression<int>? id,
    Expression<String>? cacheKey,
    Expression<String>? revision,
    Expression<String>? payload,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (cacheKey != null) 'cache_key': cacheKey,
      if (revision != null) 'revision': revision,
      if (payload != null) 'payload': payload,
    });
  }

  CatalogRecordsCompanion copyWith({
    Value<int>? id,
    Value<String>? cacheKey,
    Value<String>? revision,
    Value<String>? payload,
  }) {
    return CatalogRecordsCompanion(
      id: id ?? this.id,
      cacheKey: cacheKey ?? this.cacheKey,
      revision: revision ?? this.revision,
      payload: payload ?? this.payload,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<int>(id.value);
    }
    if (cacheKey.present) {
      map['cache_key'] = Variable<String>(cacheKey.value);
    }
    if (revision.present) {
      map['revision'] = Variable<String>(revision.value);
    }
    if (payload.present) {
      map['payload'] = Variable<String>(payload.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('CatalogRecordsCompanion(')
          ..write('id: $id, ')
          ..write('cacheKey: $cacheKey, ')
          ..write('revision: $revision, ')
          ..write('payload: $payload')
          ..write(')'))
        .toString();
  }
}

class $ActiveCatalogsTable extends ActiveCatalogs
    with TableInfo<$ActiveCatalogsTable, ActiveCatalog> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $ActiveCatalogsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _cacheKeyMeta = const VerificationMeta(
    'cacheKey',
  );
  @override
  late final GeneratedColumn<String> cacheKey = GeneratedColumn<String>(
    'cache_key',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _recordIdMeta = const VerificationMeta(
    'recordId',
  );
  @override
  late final GeneratedColumn<int> recordId = GeneratedColumn<int>(
    'record_id',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'REFERENCES catalog_records (id)',
    ),
  );
  @override
  List<GeneratedColumn> get $columns => [cacheKey, recordId];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'active_catalogs';
  @override
  VerificationContext validateIntegrity(
    Insertable<ActiveCatalog> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('cache_key')) {
      context.handle(
        _cacheKeyMeta,
        cacheKey.isAcceptableOrUnknown(data['cache_key']!, _cacheKeyMeta),
      );
    } else if (isInserting) {
      context.missing(_cacheKeyMeta);
    }
    if (data.containsKey('record_id')) {
      context.handle(
        _recordIdMeta,
        recordId.isAcceptableOrUnknown(data['record_id']!, _recordIdMeta),
      );
    } else if (isInserting) {
      context.missing(_recordIdMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {cacheKey};
  @override
  ActiveCatalog map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return ActiveCatalog(
      cacheKey: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}cache_key'],
      )!,
      recordId: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}record_id'],
      )!,
    );
  }

  @override
  $ActiveCatalogsTable createAlias(String alias) {
    return $ActiveCatalogsTable(attachedDatabase, alias);
  }
}

class ActiveCatalog extends DataClass implements Insertable<ActiveCatalog> {
  final String cacheKey;
  final int recordId;
  const ActiveCatalog({required this.cacheKey, required this.recordId});
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['cache_key'] = Variable<String>(cacheKey);
    map['record_id'] = Variable<int>(recordId);
    return map;
  }

  ActiveCatalogsCompanion toCompanion(bool nullToAbsent) {
    return ActiveCatalogsCompanion(
      cacheKey: Value(cacheKey),
      recordId: Value(recordId),
    );
  }

  factory ActiveCatalog.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return ActiveCatalog(
      cacheKey: serializer.fromJson<String>(json['cacheKey']),
      recordId: serializer.fromJson<int>(json['recordId']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'cacheKey': serializer.toJson<String>(cacheKey),
      'recordId': serializer.toJson<int>(recordId),
    };
  }

  ActiveCatalog copyWith({String? cacheKey, int? recordId}) => ActiveCatalog(
    cacheKey: cacheKey ?? this.cacheKey,
    recordId: recordId ?? this.recordId,
  );
  ActiveCatalog copyWithCompanion(ActiveCatalogsCompanion data) {
    return ActiveCatalog(
      cacheKey: data.cacheKey.present ? data.cacheKey.value : this.cacheKey,
      recordId: data.recordId.present ? data.recordId.value : this.recordId,
    );
  }

  @override
  String toString() {
    return (StringBuffer('ActiveCatalog(')
          ..write('cacheKey: $cacheKey, ')
          ..write('recordId: $recordId')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(cacheKey, recordId);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is ActiveCatalog &&
          other.cacheKey == this.cacheKey &&
          other.recordId == this.recordId);
}

class ActiveCatalogsCompanion extends UpdateCompanion<ActiveCatalog> {
  final Value<String> cacheKey;
  final Value<int> recordId;
  final Value<int> rowid;
  const ActiveCatalogsCompanion({
    this.cacheKey = const Value.absent(),
    this.recordId = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  ActiveCatalogsCompanion.insert({
    required String cacheKey,
    required int recordId,
    this.rowid = const Value.absent(),
  }) : cacheKey = Value(cacheKey),
       recordId = Value(recordId);
  static Insertable<ActiveCatalog> custom({
    Expression<String>? cacheKey,
    Expression<int>? recordId,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (cacheKey != null) 'cache_key': cacheKey,
      if (recordId != null) 'record_id': recordId,
      if (rowid != null) 'rowid': rowid,
    });
  }

  ActiveCatalogsCompanion copyWith({
    Value<String>? cacheKey,
    Value<int>? recordId,
    Value<int>? rowid,
  }) {
    return ActiveCatalogsCompanion(
      cacheKey: cacheKey ?? this.cacheKey,
      recordId: recordId ?? this.recordId,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (cacheKey.present) {
      map['cache_key'] = Variable<String>(cacheKey.value);
    }
    if (recordId.present) {
      map['record_id'] = Variable<int>(recordId.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('ActiveCatalogsCompanion(')
          ..write('cacheKey: $cacheKey, ')
          ..write('recordId: $recordId, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $ImportRecordsTable extends ImportRecords
    with TableInfo<$ImportRecordsTable, ImportRecord> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $ImportRecordsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _digestMeta = const VerificationMeta('digest');
  @override
  late final GeneratedColumn<String> digest = GeneratedColumn<String>(
    'digest',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _formatVersionMeta = const VerificationMeta(
    'formatVersion',
  );
  @override
  late final GeneratedColumn<int> formatVersion = GeneratedColumn<int>(
    'format_version',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _importedAtMeta = const VerificationMeta(
    'importedAt',
  );
  @override
  late final GeneratedColumn<DateTime> importedAt = GeneratedColumn<DateTime>(
    'imported_at',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _recordCountMeta = const VerificationMeta(
    'recordCount',
  );
  @override
  late final GeneratedColumn<int> recordCount = GeneratedColumn<int>(
    'record_count',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  @override
  List<GeneratedColumn> get $columns => [
    digest,
    formatVersion,
    importedAt,
    recordCount,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'import_records';
  @override
  VerificationContext validateIntegrity(
    Insertable<ImportRecord> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('digest')) {
      context.handle(
        _digestMeta,
        digest.isAcceptableOrUnknown(data['digest']!, _digestMeta),
      );
    } else if (isInserting) {
      context.missing(_digestMeta);
    }
    if (data.containsKey('format_version')) {
      context.handle(
        _formatVersionMeta,
        formatVersion.isAcceptableOrUnknown(
          data['format_version']!,
          _formatVersionMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_formatVersionMeta);
    }
    if (data.containsKey('imported_at')) {
      context.handle(
        _importedAtMeta,
        importedAt.isAcceptableOrUnknown(data['imported_at']!, _importedAtMeta),
      );
    } else if (isInserting) {
      context.missing(_importedAtMeta);
    }
    if (data.containsKey('record_count')) {
      context.handle(
        _recordCountMeta,
        recordCount.isAcceptableOrUnknown(
          data['record_count']!,
          _recordCountMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_recordCountMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {digest};
  @override
  ImportRecord map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return ImportRecord(
      digest: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}digest'],
      )!,
      formatVersion: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}format_version'],
      )!,
      importedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}imported_at'],
      )!,
      recordCount: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}record_count'],
      )!,
    );
  }

  @override
  $ImportRecordsTable createAlias(String alias) {
    return $ImportRecordsTable(attachedDatabase, alias);
  }
}

class ImportRecord extends DataClass implements Insertable<ImportRecord> {
  final String digest;
  final int formatVersion;
  final DateTime importedAt;
  final int recordCount;
  const ImportRecord({
    required this.digest,
    required this.formatVersion,
    required this.importedAt,
    required this.recordCount,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['digest'] = Variable<String>(digest);
    map['format_version'] = Variable<int>(formatVersion);
    map['imported_at'] = Variable<DateTime>(importedAt);
    map['record_count'] = Variable<int>(recordCount);
    return map;
  }

  ImportRecordsCompanion toCompanion(bool nullToAbsent) {
    return ImportRecordsCompanion(
      digest: Value(digest),
      formatVersion: Value(formatVersion),
      importedAt: Value(importedAt),
      recordCount: Value(recordCount),
    );
  }

  factory ImportRecord.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return ImportRecord(
      digest: serializer.fromJson<String>(json['digest']),
      formatVersion: serializer.fromJson<int>(json['formatVersion']),
      importedAt: serializer.fromJson<DateTime>(json['importedAt']),
      recordCount: serializer.fromJson<int>(json['recordCount']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'digest': serializer.toJson<String>(digest),
      'formatVersion': serializer.toJson<int>(formatVersion),
      'importedAt': serializer.toJson<DateTime>(importedAt),
      'recordCount': serializer.toJson<int>(recordCount),
    };
  }

  ImportRecord copyWith({
    String? digest,
    int? formatVersion,
    DateTime? importedAt,
    int? recordCount,
  }) => ImportRecord(
    digest: digest ?? this.digest,
    formatVersion: formatVersion ?? this.formatVersion,
    importedAt: importedAt ?? this.importedAt,
    recordCount: recordCount ?? this.recordCount,
  );
  ImportRecord copyWithCompanion(ImportRecordsCompanion data) {
    return ImportRecord(
      digest: data.digest.present ? data.digest.value : this.digest,
      formatVersion: data.formatVersion.present
          ? data.formatVersion.value
          : this.formatVersion,
      importedAt: data.importedAt.present
          ? data.importedAt.value
          : this.importedAt,
      recordCount: data.recordCount.present
          ? data.recordCount.value
          : this.recordCount,
    );
  }

  @override
  String toString() {
    return (StringBuffer('ImportRecord(')
          ..write('digest: $digest, ')
          ..write('formatVersion: $formatVersion, ')
          ..write('importedAt: $importedAt, ')
          ..write('recordCount: $recordCount')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode =>
      Object.hash(digest, formatVersion, importedAt, recordCount);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is ImportRecord &&
          other.digest == this.digest &&
          other.formatVersion == this.formatVersion &&
          other.importedAt == this.importedAt &&
          other.recordCount == this.recordCount);
}

class ImportRecordsCompanion extends UpdateCompanion<ImportRecord> {
  final Value<String> digest;
  final Value<int> formatVersion;
  final Value<DateTime> importedAt;
  final Value<int> recordCount;
  final Value<int> rowid;
  const ImportRecordsCompanion({
    this.digest = const Value.absent(),
    this.formatVersion = const Value.absent(),
    this.importedAt = const Value.absent(),
    this.recordCount = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  ImportRecordsCompanion.insert({
    required String digest,
    required int formatVersion,
    required DateTime importedAt,
    required int recordCount,
    this.rowid = const Value.absent(),
  }) : digest = Value(digest),
       formatVersion = Value(formatVersion),
       importedAt = Value(importedAt),
       recordCount = Value(recordCount);
  static Insertable<ImportRecord> custom({
    Expression<String>? digest,
    Expression<int>? formatVersion,
    Expression<DateTime>? importedAt,
    Expression<int>? recordCount,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (digest != null) 'digest': digest,
      if (formatVersion != null) 'format_version': formatVersion,
      if (importedAt != null) 'imported_at': importedAt,
      if (recordCount != null) 'record_count': recordCount,
      if (rowid != null) 'rowid': rowid,
    });
  }

  ImportRecordsCompanion copyWith({
    Value<String>? digest,
    Value<int>? formatVersion,
    Value<DateTime>? importedAt,
    Value<int>? recordCount,
    Value<int>? rowid,
  }) {
    return ImportRecordsCompanion(
      digest: digest ?? this.digest,
      formatVersion: formatVersion ?? this.formatVersion,
      importedAt: importedAt ?? this.importedAt,
      recordCount: recordCount ?? this.recordCount,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (digest.present) {
      map['digest'] = Variable<String>(digest.value);
    }
    if (formatVersion.present) {
      map['format_version'] = Variable<int>(formatVersion.value);
    }
    if (importedAt.present) {
      map['imported_at'] = Variable<DateTime>(importedAt.value);
    }
    if (recordCount.present) {
      map['record_count'] = Variable<int>(recordCount.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('ImportRecordsCompanion(')
          ..write('digest: $digest, ')
          ..write('formatVersion: $formatVersion, ')
          ..write('importedAt: $importedAt, ')
          ..write('recordCount: $recordCount, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

abstract class _$BlackgridDatabase extends GeneratedDatabase {
  _$BlackgridDatabase(QueryExecutor e) : super(e);
  $BlackgridDatabaseManager get managers => $BlackgridDatabaseManager(this);
  late final $PreferencesTable preferences = $PreferencesTable(this);
  late final $PinRecordsTable pinRecords = $PinRecordsTable(this);
  late final $ActivityRecordsTable activityRecords = $ActivityRecordsTable(
    this,
  );
  late final $CatalogRecordsTable catalogRecords = $CatalogRecordsTable(this);
  late final $ActiveCatalogsTable activeCatalogs = $ActiveCatalogsTable(this);
  late final $ImportRecordsTable importRecords = $ImportRecordsTable(this);
  @override
  Iterable<TableInfo<Table, Object?>> get allTables =>
      allSchemaEntities.whereType<TableInfo<Table, Object?>>();
  @override
  List<DatabaseSchemaEntity> get allSchemaEntities => [
    preferences,
    pinRecords,
    activityRecords,
    catalogRecords,
    activeCatalogs,
    importRecords,
  ];
}

typedef $$PreferencesTableCreateCompanionBuilder =
    PreferencesCompanion Function({Value<int> id, required String payload});
typedef $$PreferencesTableUpdateCompanionBuilder =
    PreferencesCompanion Function({Value<int> id, Value<String> payload});

class $$PreferencesTableFilterComposer
    extends Composer<_$BlackgridDatabase, $PreferencesTable> {
  $$PreferencesTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<int> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get payload => $composableBuilder(
    column: $table.payload,
    builder: (column) => ColumnFilters(column),
  );
}

class $$PreferencesTableOrderingComposer
    extends Composer<_$BlackgridDatabase, $PreferencesTable> {
  $$PreferencesTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<int> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get payload => $composableBuilder(
    column: $table.payload,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$PreferencesTableAnnotationComposer
    extends Composer<_$BlackgridDatabase, $PreferencesTable> {
  $$PreferencesTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<int> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get payload =>
      $composableBuilder(column: $table.payload, builder: (column) => column);
}

class $$PreferencesTableTableManager
    extends
        RootTableManager<
          _$BlackgridDatabase,
          $PreferencesTable,
          Preference,
          $$PreferencesTableFilterComposer,
          $$PreferencesTableOrderingComposer,
          $$PreferencesTableAnnotationComposer,
          $$PreferencesTableCreateCompanionBuilder,
          $$PreferencesTableUpdateCompanionBuilder,
          (
            Preference,
            BaseReferences<_$BlackgridDatabase, $PreferencesTable, Preference>,
          ),
          Preference,
          PrefetchHooks Function()
        > {
  $$PreferencesTableTableManager(
    _$BlackgridDatabase db,
    $PreferencesTable table,
  ) : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$PreferencesTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$PreferencesTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$PreferencesTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback: ({
            Value<int> id = const Value.absent(),
            Value<String> payload = const Value.absent(),
          }) => PreferencesCompanion(id: id, payload: payload),
          createCompanionCallback: ({
            Value<int> id = const Value.absent(),
            required String payload,
          }) => PreferencesCompanion.insert(id: id, payload: payload),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable<$PreferencesTable, Preference>(table),
                  BaseReferences<
                    _$BlackgridDatabase,
                    $PreferencesTable,
                    Preference
                  >(db, table, e),
                ),
              )
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$PreferencesTableProcessedTableManager =
    ProcessedTableManager<
      _$BlackgridDatabase,
      $PreferencesTable,
      Preference,
      $$PreferencesTableFilterComposer,
      $$PreferencesTableOrderingComposer,
      $$PreferencesTableAnnotationComposer,
      $$PreferencesTableCreateCompanionBuilder,
      $$PreferencesTableUpdateCompanionBuilder,
      (
        Preference,
        BaseReferences<_$BlackgridDatabase, $PreferencesTable, Preference>,
      ),
      Preference,
      PrefetchHooks Function()
    >;
typedef $$PinRecordsTableCreateCompanionBuilder = PinRecordsCompanion Function({
  required String mapId,
  required String pinId,
  required String payload,
  Value<int> rowid,
});
typedef $$PinRecordsTableUpdateCompanionBuilder = PinRecordsCompanion Function({
  Value<String> mapId,
  Value<String> pinId,
  Value<String> payload,
  Value<int> rowid,
});

class $$PinRecordsTableFilterComposer
    extends Composer<_$BlackgridDatabase, $PinRecordsTable> {
  $$PinRecordsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get mapId => $composableBuilder(
    column: $table.mapId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get pinId => $composableBuilder(
    column: $table.pinId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get payload => $composableBuilder(
    column: $table.payload,
    builder: (column) => ColumnFilters(column),
  );
}

class $$PinRecordsTableOrderingComposer
    extends Composer<_$BlackgridDatabase, $PinRecordsTable> {
  $$PinRecordsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get mapId => $composableBuilder(
    column: $table.mapId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get pinId => $composableBuilder(
    column: $table.pinId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get payload => $composableBuilder(
    column: $table.payload,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$PinRecordsTableAnnotationComposer
    extends Composer<_$BlackgridDatabase, $PinRecordsTable> {
  $$PinRecordsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get mapId =>
      $composableBuilder(column: $table.mapId, builder: (column) => column);

  GeneratedColumn<String> get pinId =>
      $composableBuilder(column: $table.pinId, builder: (column) => column);

  GeneratedColumn<String> get payload =>
      $composableBuilder(column: $table.payload, builder: (column) => column);
}

class $$PinRecordsTableTableManager
    extends
        RootTableManager<
          _$BlackgridDatabase,
          $PinRecordsTable,
          PinRecord,
          $$PinRecordsTableFilterComposer,
          $$PinRecordsTableOrderingComposer,
          $$PinRecordsTableAnnotationComposer,
          $$PinRecordsTableCreateCompanionBuilder,
          $$PinRecordsTableUpdateCompanionBuilder,
          (
            PinRecord,
            BaseReferences<_$BlackgridDatabase, $PinRecordsTable, PinRecord>,
          ),
          PinRecord,
          PrefetchHooks Function()
        > {
  $$PinRecordsTableTableManager(_$BlackgridDatabase db, $PinRecordsTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$PinRecordsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$PinRecordsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$PinRecordsTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> mapId = const Value.absent(),
                Value<String> pinId = const Value.absent(),
                Value<String> payload = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => PinRecordsCompanion(
                mapId: mapId,
                pinId: pinId,
                payload: payload,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String mapId,
                required String pinId,
                required String payload,
                Value<int> rowid = const Value.absent(),
              }) => PinRecordsCompanion.insert(
                mapId: mapId,
                pinId: pinId,
                payload: payload,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable<$PinRecordsTable, PinRecord>(table),
                  BaseReferences<
                    _$BlackgridDatabase,
                    $PinRecordsTable,
                    PinRecord
                  >(db, table, e),
                ),
              )
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$PinRecordsTableProcessedTableManager =
    ProcessedTableManager<
      _$BlackgridDatabase,
      $PinRecordsTable,
      PinRecord,
      $$PinRecordsTableFilterComposer,
      $$PinRecordsTableOrderingComposer,
      $$PinRecordsTableAnnotationComposer,
      $$PinRecordsTableCreateCompanionBuilder,
      $$PinRecordsTableUpdateCompanionBuilder,
      (
        PinRecord,
        BaseReferences<_$BlackgridDatabase, $PinRecordsTable, PinRecord>,
      ),
      PinRecord,
      PrefetchHooks Function()
    >;
typedef $$ActivityRecordsTableCreateCompanionBuilder =
    ActivityRecordsCompanion Function({
      required String itemId,
      required String mode,
      required String source,
      required DateTime observedAt,
      required int revision,
      Value<int> rowid,
    });
typedef $$ActivityRecordsTableUpdateCompanionBuilder =
    ActivityRecordsCompanion Function({
      Value<String> itemId,
      Value<String> mode,
      Value<String> source,
      Value<DateTime> observedAt,
      Value<int> revision,
      Value<int> rowid,
    });

class $$ActivityRecordsTableFilterComposer
    extends Composer<_$BlackgridDatabase, $ActivityRecordsTable> {
  $$ActivityRecordsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get itemId => $composableBuilder(
    column: $table.itemId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get mode => $composableBuilder(
    column: $table.mode,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get source => $composableBuilder(
    column: $table.source,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get observedAt => $composableBuilder(
    column: $table.observedAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get revision => $composableBuilder(
    column: $table.revision,
    builder: (column) => ColumnFilters(column),
  );
}

class $$ActivityRecordsTableOrderingComposer
    extends Composer<_$BlackgridDatabase, $ActivityRecordsTable> {
  $$ActivityRecordsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get itemId => $composableBuilder(
    column: $table.itemId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get mode => $composableBuilder(
    column: $table.mode,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get source => $composableBuilder(
    column: $table.source,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get observedAt => $composableBuilder(
    column: $table.observedAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get revision => $composableBuilder(
    column: $table.revision,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$ActivityRecordsTableAnnotationComposer
    extends Composer<_$BlackgridDatabase, $ActivityRecordsTable> {
  $$ActivityRecordsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get itemId =>
      $composableBuilder(column: $table.itemId, builder: (column) => column);

  GeneratedColumn<String> get mode =>
      $composableBuilder(column: $table.mode, builder: (column) => column);

  GeneratedColumn<String> get source =>
      $composableBuilder(column: $table.source, builder: (column) => column);

  GeneratedColumn<DateTime> get observedAt => $composableBuilder(
    column: $table.observedAt,
    builder: (column) => column,
  );

  GeneratedColumn<int> get revision =>
      $composableBuilder(column: $table.revision, builder: (column) => column);
}

class $$ActivityRecordsTableTableManager
    extends
        RootTableManager<
          _$BlackgridDatabase,
          $ActivityRecordsTable,
          ActivityRecord,
          $$ActivityRecordsTableFilterComposer,
          $$ActivityRecordsTableOrderingComposer,
          $$ActivityRecordsTableAnnotationComposer,
          $$ActivityRecordsTableCreateCompanionBuilder,
          $$ActivityRecordsTableUpdateCompanionBuilder,
          (
            ActivityRecord,
            BaseReferences<
              _$BlackgridDatabase,
              $ActivityRecordsTable,
              ActivityRecord
            >,
          ),
          ActivityRecord,
          PrefetchHooks Function()
        > {
  $$ActivityRecordsTableTableManager(
    _$BlackgridDatabase db,
    $ActivityRecordsTable table,
  ) : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$ActivityRecordsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$ActivityRecordsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$ActivityRecordsTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> itemId = const Value.absent(),
                Value<String> mode = const Value.absent(),
                Value<String> source = const Value.absent(),
                Value<DateTime> observedAt = const Value.absent(),
                Value<int> revision = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => ActivityRecordsCompanion(
                itemId: itemId,
                mode: mode,
                source: source,
                observedAt: observedAt,
                revision: revision,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String itemId,
                required String mode,
                required String source,
                required DateTime observedAt,
                required int revision,
                Value<int> rowid = const Value.absent(),
              }) => ActivityRecordsCompanion.insert(
                itemId: itemId,
                mode: mode,
                source: source,
                observedAt: observedAt,
                revision: revision,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable<$ActivityRecordsTable, ActivityRecord>(table),
                  BaseReferences<
                    _$BlackgridDatabase,
                    $ActivityRecordsTable,
                    ActivityRecord
                  >(db, table, e),
                ),
              )
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$ActivityRecordsTableProcessedTableManager =
    ProcessedTableManager<
      _$BlackgridDatabase,
      $ActivityRecordsTable,
      ActivityRecord,
      $$ActivityRecordsTableFilterComposer,
      $$ActivityRecordsTableOrderingComposer,
      $$ActivityRecordsTableAnnotationComposer,
      $$ActivityRecordsTableCreateCompanionBuilder,
      $$ActivityRecordsTableUpdateCompanionBuilder,
      (
        ActivityRecord,
        BaseReferences<
          _$BlackgridDatabase,
          $ActivityRecordsTable,
          ActivityRecord
        >,
      ),
      ActivityRecord,
      PrefetchHooks Function()
    >;
typedef $$CatalogRecordsTableCreateCompanionBuilder =
    CatalogRecordsCompanion Function({
      Value<int> id,
      required String cacheKey,
      required String revision,
      required String payload,
    });
typedef $$CatalogRecordsTableUpdateCompanionBuilder =
    CatalogRecordsCompanion Function({
      Value<int> id,
      Value<String> cacheKey,
      Value<String> revision,
      Value<String> payload,
    });

final class $$CatalogRecordsTableReferences
    extends
        BaseReferences<
          _$BlackgridDatabase,
          $CatalogRecordsTable,
          CatalogRecord
        > {
  $$CatalogRecordsTableReferences(
    super.$_db,
    super.$_table,
    super.$_typedResult,
  );

  static MultiTypedResultKey<$ActiveCatalogsTable, List<ActiveCatalog>>
  _activeCatalogsRefsTable(_$BlackgridDatabase db) =>
      MultiTypedResultKey.fromTable(
        db.activeCatalogs,
        aliasName: 'catalog_records__id__active_catalogs__record_id',
      );

  $$ActiveCatalogsTableProcessedTableManager get activeCatalogsRefs {
    final manager = $$ActiveCatalogsTableTableManager(
      $_db,
      $_db.activeCatalogs,
    ).filter((f) => f.recordId.id.sqlEquals($_itemColumn<int>('id')!));

    final cache = $_typedResult.readTableOrNull(_activeCatalogsRefsTable($_db));
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: cache),
    );
  }
}

class $$CatalogRecordsTableFilterComposer
    extends Composer<_$BlackgridDatabase, $CatalogRecordsTable> {
  $$CatalogRecordsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<int> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get cacheKey => $composableBuilder(
    column: $table.cacheKey,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get revision => $composableBuilder(
    column: $table.revision,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get payload => $composableBuilder(
    column: $table.payload,
    builder: (column) => ColumnFilters(column),
  );

  Expression<bool> activeCatalogsRefs(
    Expression<bool> Function($$ActiveCatalogsTableFilterComposer f) f,
  ) {
    final $$ActiveCatalogsTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.id,
      referencedTable: $db.activeCatalogs,
      getReferencedColumn: (t) => t.recordId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$ActiveCatalogsTableFilterComposer(
            $db: $db,
            $table: $db.activeCatalogs,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }
}

class $$CatalogRecordsTableOrderingComposer
    extends Composer<_$BlackgridDatabase, $CatalogRecordsTable> {
  $$CatalogRecordsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<int> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get cacheKey => $composableBuilder(
    column: $table.cacheKey,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get revision => $composableBuilder(
    column: $table.revision,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get payload => $composableBuilder(
    column: $table.payload,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$CatalogRecordsTableAnnotationComposer
    extends Composer<_$BlackgridDatabase, $CatalogRecordsTable> {
  $$CatalogRecordsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<int> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get cacheKey =>
      $composableBuilder(column: $table.cacheKey, builder: (column) => column);

  GeneratedColumn<String> get revision =>
      $composableBuilder(column: $table.revision, builder: (column) => column);

  GeneratedColumn<String> get payload =>
      $composableBuilder(column: $table.payload, builder: (column) => column);

  Expression<T> activeCatalogsRefs<T extends Object>(
    Expression<T> Function($$ActiveCatalogsTableAnnotationComposer a) f,
  ) {
    final $$ActiveCatalogsTableAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.id,
      referencedTable: $db.activeCatalogs,
      getReferencedColumn: (t) => t.recordId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$ActiveCatalogsTableAnnotationComposer(
            $db: $db,
            $table: $db.activeCatalogs,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }
}

class $$CatalogRecordsTableTableManager
    extends
        RootTableManager<
          _$BlackgridDatabase,
          $CatalogRecordsTable,
          CatalogRecord,
          $$CatalogRecordsTableFilterComposer,
          $$CatalogRecordsTableOrderingComposer,
          $$CatalogRecordsTableAnnotationComposer,
          $$CatalogRecordsTableCreateCompanionBuilder,
          $$CatalogRecordsTableUpdateCompanionBuilder,
          (CatalogRecord, $$CatalogRecordsTableReferences),
          CatalogRecord,
          PrefetchHooks Function({bool activeCatalogsRefs})
        > {
  $$CatalogRecordsTableTableManager(
    _$BlackgridDatabase db,
    $CatalogRecordsTable table,
  ) : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$CatalogRecordsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$CatalogRecordsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$CatalogRecordsTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<int> id = const Value.absent(),
                Value<String> cacheKey = const Value.absent(),
                Value<String> revision = const Value.absent(),
                Value<String> payload = const Value.absent(),
              }) => CatalogRecordsCompanion(
                id: id,
                cacheKey: cacheKey,
                revision: revision,
                payload: payload,
              ),
          createCompanionCallback:
              ({
                Value<int> id = const Value.absent(),
                required String cacheKey,
                required String revision,
                required String payload,
              }) => CatalogRecordsCompanion.insert(
                id: id,
                cacheKey: cacheKey,
                revision: revision,
                payload: payload,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable<$CatalogRecordsTable, CatalogRecord>(table),
                  $$CatalogRecordsTableReferences(db, table, e),
                ),
              )
              .toList(),
          prefetchHooksCallback: ({activeCatalogsRefs = false}) {
            return PrefetchHooks(
              db: db,
              explicitlyWatchedTables: [
                if (activeCatalogsRefs) db.activeCatalogs,
              ],
              addJoins: null,
              getPrefetchedDataCallback: (items) async {
                return [
                  if (activeCatalogsRefs)
                    await $_getPrefetchedData<
                      CatalogRecord,
                      $CatalogRecordsTable,
                      ActiveCatalog
                    >(
                      currentTable: table,
                      referencedTable: $$CatalogRecordsTableReferences
                          ._activeCatalogsRefsTable(db),
                      managerFromTypedResult: (p0) =>
                          $$CatalogRecordsTableReferences(
                            db,
                            table,
                            p0,
                          ).activeCatalogsRefs,
                      referencedItemsForCurrentItem: (item, referencedItems) =>
                          referencedItems.where((e) => e.recordId == item.id),
                      typedResults: items,
                    ),
                ];
              },
            );
          },
        ),
      );
}

typedef $$CatalogRecordsTableProcessedTableManager =
    ProcessedTableManager<
      _$BlackgridDatabase,
      $CatalogRecordsTable,
      CatalogRecord,
      $$CatalogRecordsTableFilterComposer,
      $$CatalogRecordsTableOrderingComposer,
      $$CatalogRecordsTableAnnotationComposer,
      $$CatalogRecordsTableCreateCompanionBuilder,
      $$CatalogRecordsTableUpdateCompanionBuilder,
      (CatalogRecord, $$CatalogRecordsTableReferences),
      CatalogRecord,
      PrefetchHooks Function({bool activeCatalogsRefs})
    >;
typedef $$ActiveCatalogsTableCreateCompanionBuilder =
    ActiveCatalogsCompanion Function({
      required String cacheKey,
      required int recordId,
      Value<int> rowid,
    });
typedef $$ActiveCatalogsTableUpdateCompanionBuilder =
    ActiveCatalogsCompanion Function({
      Value<String> cacheKey,
      Value<int> recordId,
      Value<int> rowid,
    });

final class $$ActiveCatalogsTableReferences
    extends
        BaseReferences<
          _$BlackgridDatabase,
          $ActiveCatalogsTable,
          ActiveCatalog
        > {
  $$ActiveCatalogsTableReferences(
    super.$_db,
    super.$_table,
    super.$_typedResult,
  );

  static $CatalogRecordsTable _recordIdTable(_$BlackgridDatabase db) => db
      .catalogRecords
      .createAlias('active_catalogs__record_id__catalog_records__id');

  $$CatalogRecordsTableProcessedTableManager get recordId {
    final $_column = $_itemColumn<int>('record_id')!;

    final manager = $$CatalogRecordsTableTableManager(
      $_db,
      $_db.catalogRecords,
    ).filter((f) => f.id.sqlEquals($_column));
    final item = $_typedResult.readTableOrNull(_recordIdTable($_db));
    if (item == null) return manager;
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: [item]),
    );
  }
}

class $$ActiveCatalogsTableFilterComposer
    extends Composer<_$BlackgridDatabase, $ActiveCatalogsTable> {
  $$ActiveCatalogsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get cacheKey => $composableBuilder(
    column: $table.cacheKey,
    builder: (column) => ColumnFilters(column),
  );

  $$CatalogRecordsTableFilterComposer get recordId {
    final $$CatalogRecordsTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.recordId,
      referencedTable: $db.catalogRecords,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$CatalogRecordsTableFilterComposer(
            $db: $db,
            $table: $db.catalogRecords,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$ActiveCatalogsTableOrderingComposer
    extends Composer<_$BlackgridDatabase, $ActiveCatalogsTable> {
  $$ActiveCatalogsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get cacheKey => $composableBuilder(
    column: $table.cacheKey,
    builder: (column) => ColumnOrderings(column),
  );

  $$CatalogRecordsTableOrderingComposer get recordId {
    final $$CatalogRecordsTableOrderingComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.recordId,
      referencedTable: $db.catalogRecords,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$CatalogRecordsTableOrderingComposer(
            $db: $db,
            $table: $db.catalogRecords,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$ActiveCatalogsTableAnnotationComposer
    extends Composer<_$BlackgridDatabase, $ActiveCatalogsTable> {
  $$ActiveCatalogsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get cacheKey =>
      $composableBuilder(column: $table.cacheKey, builder: (column) => column);

  $$CatalogRecordsTableAnnotationComposer get recordId {
    final $$CatalogRecordsTableAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.recordId,
      referencedTable: $db.catalogRecords,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$CatalogRecordsTableAnnotationComposer(
            $db: $db,
            $table: $db.catalogRecords,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$ActiveCatalogsTableTableManager
    extends
        RootTableManager<
          _$BlackgridDatabase,
          $ActiveCatalogsTable,
          ActiveCatalog,
          $$ActiveCatalogsTableFilterComposer,
          $$ActiveCatalogsTableOrderingComposer,
          $$ActiveCatalogsTableAnnotationComposer,
          $$ActiveCatalogsTableCreateCompanionBuilder,
          $$ActiveCatalogsTableUpdateCompanionBuilder,
          (ActiveCatalog, $$ActiveCatalogsTableReferences),
          ActiveCatalog,
          PrefetchHooks Function({bool recordId})
        > {
  $$ActiveCatalogsTableTableManager(
    _$BlackgridDatabase db,
    $ActiveCatalogsTable table,
  ) : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$ActiveCatalogsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$ActiveCatalogsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$ActiveCatalogsTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> cacheKey = const Value.absent(),
                Value<int> recordId = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => ActiveCatalogsCompanion(
                cacheKey: cacheKey,
                recordId: recordId,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String cacheKey,
                required int recordId,
                Value<int> rowid = const Value.absent(),
              }) => ActiveCatalogsCompanion.insert(
                cacheKey: cacheKey,
                recordId: recordId,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable<$ActiveCatalogsTable, ActiveCatalog>(table),
                  $$ActiveCatalogsTableReferences(db, table, e),
                ),
              )
              .toList(),
          prefetchHooksCallback: ({recordId = false}) {
            return PrefetchHooks(
              db: db,
              explicitlyWatchedTables: [],
              addJoins:
                  <
                    T extends TableManagerState<
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic
                    >
                  >(state) {
                    if (recordId) {
                      state = state.withJoin(
                        currentTable: table,
                        currentColumn: table.recordId,
                        referencedTable: $$ActiveCatalogsTableReferences
                            ._recordIdTable(db),
                        referencedColumn: $$ActiveCatalogsTableReferences
                            ._recordIdTable(db)
                            .id,
                      ) as T;
                    }

                    return state;
                  },
              getPrefetchedDataCallback: (items) async {
                return [];
              },
            );
          },
        ),
      );
}

typedef $$ActiveCatalogsTableProcessedTableManager =
    ProcessedTableManager<
      _$BlackgridDatabase,
      $ActiveCatalogsTable,
      ActiveCatalog,
      $$ActiveCatalogsTableFilterComposer,
      $$ActiveCatalogsTableOrderingComposer,
      $$ActiveCatalogsTableAnnotationComposer,
      $$ActiveCatalogsTableCreateCompanionBuilder,
      $$ActiveCatalogsTableUpdateCompanionBuilder,
      (ActiveCatalog, $$ActiveCatalogsTableReferences),
      ActiveCatalog,
      PrefetchHooks Function({bool recordId})
    >;
typedef $$ImportRecordsTableCreateCompanionBuilder =
    ImportRecordsCompanion Function({
      required String digest,
      required int formatVersion,
      required DateTime importedAt,
      required int recordCount,
      Value<int> rowid,
    });
typedef $$ImportRecordsTableUpdateCompanionBuilder =
    ImportRecordsCompanion Function({
      Value<String> digest,
      Value<int> formatVersion,
      Value<DateTime> importedAt,
      Value<int> recordCount,
      Value<int> rowid,
    });

class $$ImportRecordsTableFilterComposer
    extends Composer<_$BlackgridDatabase, $ImportRecordsTable> {
  $$ImportRecordsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get digest => $composableBuilder(
    column: $table.digest,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get formatVersion => $composableBuilder(
    column: $table.formatVersion,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get importedAt => $composableBuilder(
    column: $table.importedAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get recordCount => $composableBuilder(
    column: $table.recordCount,
    builder: (column) => ColumnFilters(column),
  );
}

class $$ImportRecordsTableOrderingComposer
    extends Composer<_$BlackgridDatabase, $ImportRecordsTable> {
  $$ImportRecordsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get digest => $composableBuilder(
    column: $table.digest,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get formatVersion => $composableBuilder(
    column: $table.formatVersion,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get importedAt => $composableBuilder(
    column: $table.importedAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get recordCount => $composableBuilder(
    column: $table.recordCount,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$ImportRecordsTableAnnotationComposer
    extends Composer<_$BlackgridDatabase, $ImportRecordsTable> {
  $$ImportRecordsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get digest =>
      $composableBuilder(column: $table.digest, builder: (column) => column);

  GeneratedColumn<int> get formatVersion => $composableBuilder(
    column: $table.formatVersion,
    builder: (column) => column,
  );

  GeneratedColumn<DateTime> get importedAt => $composableBuilder(
    column: $table.importedAt,
    builder: (column) => column,
  );

  GeneratedColumn<int> get recordCount => $composableBuilder(
    column: $table.recordCount,
    builder: (column) => column,
  );
}

class $$ImportRecordsTableTableManager
    extends
        RootTableManager<
          _$BlackgridDatabase,
          $ImportRecordsTable,
          ImportRecord,
          $$ImportRecordsTableFilterComposer,
          $$ImportRecordsTableOrderingComposer,
          $$ImportRecordsTableAnnotationComposer,
          $$ImportRecordsTableCreateCompanionBuilder,
          $$ImportRecordsTableUpdateCompanionBuilder,
          (
            ImportRecord,
            BaseReferences<
              _$BlackgridDatabase,
              $ImportRecordsTable,
              ImportRecord
            >,
          ),
          ImportRecord,
          PrefetchHooks Function()
        > {
  $$ImportRecordsTableTableManager(
    _$BlackgridDatabase db,
    $ImportRecordsTable table,
  ) : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$ImportRecordsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$ImportRecordsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$ImportRecordsTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> digest = const Value.absent(),
                Value<int> formatVersion = const Value.absent(),
                Value<DateTime> importedAt = const Value.absent(),
                Value<int> recordCount = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => ImportRecordsCompanion(
                digest: digest,
                formatVersion: formatVersion,
                importedAt: importedAt,
                recordCount: recordCount,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String digest,
                required int formatVersion,
                required DateTime importedAt,
                required int recordCount,
                Value<int> rowid = const Value.absent(),
              }) => ImportRecordsCompanion.insert(
                digest: digest,
                formatVersion: formatVersion,
                importedAt: importedAt,
                recordCount: recordCount,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable<$ImportRecordsTable, ImportRecord>(table),
                  BaseReferences<
                    _$BlackgridDatabase,
                    $ImportRecordsTable,
                    ImportRecord
                  >(db, table, e),
                ),
              )
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$ImportRecordsTableProcessedTableManager =
    ProcessedTableManager<
      _$BlackgridDatabase,
      $ImportRecordsTable,
      ImportRecord,
      $$ImportRecordsTableFilterComposer,
      $$ImportRecordsTableOrderingComposer,
      $$ImportRecordsTableAnnotationComposer,
      $$ImportRecordsTableCreateCompanionBuilder,
      $$ImportRecordsTableUpdateCompanionBuilder,
      (
        ImportRecord,
        BaseReferences<_$BlackgridDatabase, $ImportRecordsTable, ImportRecord>,
      ),
      ImportRecord,
      PrefetchHooks Function()
    >;

class $BlackgridDatabaseManager {
  final _$BlackgridDatabase _db;
  $BlackgridDatabaseManager(this._db);
  $$PreferencesTableTableManager get preferences =>
      $$PreferencesTableTableManager(_db, _db.preferences);
  $$PinRecordsTableTableManager get pinRecords =>
      $$PinRecordsTableTableManager(_db, _db.pinRecords);
  $$ActivityRecordsTableTableManager get activityRecords =>
      $$ActivityRecordsTableTableManager(_db, _db.activityRecords);
  $$CatalogRecordsTableTableManager get catalogRecords =>
      $$CatalogRecordsTableTableManager(_db, _db.catalogRecords);
  $$ActiveCatalogsTableTableManager get activeCatalogs =>
      $$ActiveCatalogsTableTableManager(_db, _db.activeCatalogs);
  $$ImportRecordsTableTableManager get importRecords =>
      $$ImportRecordsTableTableManager(_db, _db.importRecords);
}
