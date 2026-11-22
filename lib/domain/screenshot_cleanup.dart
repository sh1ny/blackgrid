import 'raid_lifecycle.dart';
import 'screenshot_filename.dart';

/// Metadata for a direct entry in a screenshot folder.
class ScreenshotEntry {
  /// Creates metadata used to decide whether an entry belongs to a raid.
  const ScreenshotEntry({
    required this.name,
    required this.isFile,
    required this.isLink,
    required this.modified,
  });

  /// The direct entry's basename.
  final String name;

  /// Whether the entry is a regular file.
  final bool isFile;

  /// Whether the entry is a link.
  final bool isLink;

  /// The file's last modification time.
  final DateTime modified;
}

/// Selects direct game screenshots modified within the ended [raid].
///
/// Both endpoints are inclusive. An unfinished or reversed raid selects none.
List<String> pickRaidScreenshots(Iterable<ScreenshotEntry> entries, Raid raid) {
  final end = raid.endTime;
  if (end == null || end.isBefore(raid.startTime)) return [];

  final picked = <String>[];
  for (final entry in entries) {
    final name = entry.name;
    if (!entry.isFile ||
        entry.isLink ||
        name.contains('/') ||
        name.contains('\\') ||
        name.contains('..') ||
        entry.modified.isBefore(raid.startTime) ||
        entry.modified.isAfter(end) ||
        parseScreenshotFilename(name) == null) {
      continue;
    }
    picked.add(name);
  }
  return picked;
}
