import 'settings.dart';

class ImportAccounting {
  const ImportAccounting({
    required this.kind,
    required this.key,
    required this.inputOrder,
    required this.disposition,
    required this.reason,
  });
  final String kind, key, disposition, reason;
  final int inputOrder;
}

class ImportPreview {
  ImportPreview({
    required this.digest,
    this.formatVersion = 1,
    this.settings,
    required Iterable<CustomPin> pins,
    required Iterable<ItemActivity> winningActivity,
    required Iterable<ImportAccounting> accounting,
    required Iterable<String> exclusions,
    required Iterable<String> sourcePaths,
    this.alreadyImported = false,
  }) : pins = List.unmodifiable(pins),
       winningActivity = List.unmodifiable(winningActivity),
       accounting = List.unmodifiable(accounting),
       exclusions = List.unmodifiable(exclusions),
       sourcePaths = List.unmodifiable(sourcePaths);
  final String digest;
  final int formatVersion;
  final AppSettings? settings;
  final List<CustomPin> pins;
  final List<ItemActivity> winningActivity;
  final List<ImportAccounting> accounting;
  final List<String> exclusions, sourcePaths;
  final bool alreadyImported;
}
