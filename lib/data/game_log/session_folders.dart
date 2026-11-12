import 'dart:io';

import '../../domain/raid_lifecycle.dart';

/// A session folder and the local time encoded in its name.
final class SessionFolder {
  /// Creates a folder description.
  const SessionFolder(this.name, this.path, this.time);

  /// The folder's basename.
  final String name;

  /// The folder's path.
  final String path;

  /// The local session start time encoded in the name.
  final DateTime time;
}

/// The accepted session folder name pattern.
final sessionFolderPattern = RegExp(
  r'^log_(\d{4})\.(\d{2})\.(\d{2})_(\d{1,2})-(\d{2})-(\d{2})(?:_[^\\/]*)?$',
  caseSensitive: false,
);

/// The accepted log file patterns, indexed by log kind.
final sessionLogFilePatterns = <LogFile, RegExp>{
  LogFile.application: RegExp(
    r'application(?:_000)?\.log$',
    caseSensitive: false,
  ),
  LogFile.backend: RegExp(r'backend(?:_000)?\.log$', caseSensitive: false),
  LogFile.pushNotifications: RegExp(
    r'push-notifications(?:_000)?\.log$',
    caseSensitive: false,
  ),
};

/// Returns the last component of a log path on either supported separator.
String sessionPathBasename(String path) =>
    path.replaceAll('\\', '/').split('/').last;

/// Parses the local date and time in a valid session folder name.
DateTime? parseSessionFolderTime(String name) {
  final match = sessionFolderPattern.firstMatch(name);
  if (match == null) return null;
  final time = DateTime.tryParse(
    '${match[1]}-${match[2]}-${match[3]}T${match[4]!.padLeft(2, '0')}:${match[5]}:${match[6]}',
  );
  if (time == null ||
      time.year != int.parse(match[1]!) ||
      time.month != int.parse(match[2]!) ||
      time.day != int.parse(match[3]!) ||
      time.hour != int.parse(match[4]!) ||
      time.minute != int.parse(match[5]!) ||
      time.second != int.parse(match[6]!)) {
    return null;
  }
  return time;
}

/// Compares session names by their parsed local time, then by name.
///
/// Names that do not parse are ordered lexically after valid names.
int compareSessionFolderNames(String a, String b) {
  final first = parseSessionFolderTime(a);
  final second = parseSessionFolderTime(b);
  if (first == null) return second == null ? a.compareTo(b) : 1;
  if (second == null) return -1;
  final comparison = first.compareTo(second);
  return comparison == 0 ? a.compareTo(b) : comparison;
}

/// Lists session directories under [root] in date-time and name order.
Future<List<SessionFolder>> listSessionFolders(String root) async {
  final directory = Directory(root);
  if (!await directory.exists()) return [];
  final folders = <SessionFolder>[];
  await for (final entry in directory.list(followLinks: false)) {
    if (entry is! Directory) continue;
    final name = sessionPathBasename(entry.path);
    final time = parseSessionFolderTime(name);
    if (time != null) folders.add(SessionFolder(name, entry.path, time));
  }
  folders.sort((a, b) {
    final comparison = a.time.compareTo(b.time);
    return comparison == 0 ? a.name.compareTo(b.name) : comparison;
  });
  return folders;
}

/// Selects the newest matching file of each requested kind in [directory].
///
/// Modification time decides first, followed by the full path for ties.
Future<Map<LogFile, File>> selectSessionLogFiles(
  Directory directory,
  Iterable<LogFile> kinds,
) async {
  final selected = <LogFile, (DateTime, File)>{};
  await for (final entry in directory.list(followLinks: false)) {
    if (entry is! File) continue;
    for (final kind in kinds) {
      if (!sessionLogFilePatterns[kind]!.hasMatch(entry.path)) continue;
      final modified = (await entry.stat()).modified;
      final previous = selected[kind];
      if (previous == null ||
          modified.isAfter(previous.$1) ||
          (modified == previous.$1 &&
              entry.path.compareTo(previous.$2.path) > 0)) {
        selected[kind] = (modified, entry);
      }
    }
  }
  return {for (final entry in selected.entries) entry.key: entry.value.$2};
}
