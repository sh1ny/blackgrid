import 'dart:io';

import '../../domain/raid_lifecycle.dart';
import 'game_log_parsers.dart';
import 'log_file_tail.dart';
import 'session_folders.dart';

/// The task observations and diagnostics from one session folder.
final class FolderTaskRead {
  /// Creates the result of a one-shot folder read.
  const FolderTaskRead({
    required this.folder,
    required this.tasks,
    required this.skippedNoMode,
    required this.rejected,
    required this.unreadable,
  });

  /// The session folder basename.
  final String folder;

  /// The task observations with a known mode.
  final List<TaskTransition> tasks;

  /// The number of task observations without a known folder mode.
  final int skippedNoMode;

  /// The number of framing and parser rejections.
  final int rejected;

  /// Whether the folder or a selected log could not be read completely.
  final bool unreadable;
}

/// Reads the application and push logs in [folderPath] without changing them.
///
/// Files are read only to their sizes at stat. If the folder or a selected
/// file cannot be read, the result is unreadable and contains no partial data.
/// The function is safe to invoke from a separate isolate.
Future<FolderTaskRead> readSessionFolderTasks(String folderPath) async {
  final folder = sessionPathBasename(folderPath);
  FolderTaskRead unreadable() => FolderTaskRead(
    folder: folder,
    tasks: const [],
    skippedNoMode: 0,
    rejected: 0,
    unreadable: true,
  );

  try {
    final directory = Directory(folderPath);
    if (!await directory.exists()) return unreadable();
    const kinds = [LogFile.application, LogFile.pushNotifications];
    final files = await selectSessionLogFiles(directory, kinds);
    final sizes = <LogFile, int>{};
    for (final kind in kinds) {
      final file = files[kind];
      if (file == null) continue;
      final stat = await file.stat();
      if (stat.type != FileSystemEntityType.file) return unreadable();
      sizes[kind] = stat.size;
    }

    final events = <RecordedGameLogEvent>[];
    var rejected = 0;
    for (final kind in kinds) {
      final file = files[kind];
      if (file == null) continue;
      final size = sizes[kind]!;
      final tail = LogFileTail(kind: kind);
      // Bound each batch as well as the tail's own input chunks.
      do {
        final end = (tail.offset + 256 * 1024).clamp(0, size);
        final batch = await tail.read(file, end);
        if (batch.restarted || (tail.offset < end && batch.bytesRead == 0)) {
          return unreadable();
        }
        for (final item in batch.items) {
          switch (item) {
            case TailRejection():
              rejected++;
            case TailRecord():
              switch (parseGameLogRecord(folder, kind, item)) {
                case ParseRejected():
                  rejected++;
                case ParsedNothing():
                  break;
                case ParsedEvent(:final event):
                  if (event is SessionModeChanged ||
                      event is TaskStarted ||
                      event is TaskFailed ||
                      event is TaskFinished) {
                    events.add(event);
                  }
              }
          }
        }
      } while (tail.offset < size);
    }

    events.sort((a, b) {
      var comparison = a.time.compareTo(b.time);
      if (comparison == 0) {
        comparison = a.id.file.index.compareTo(b.id.file.index);
      }
      return comparison == 0 ? a.id.offset.compareTo(b.id.offset) : comparison;
    });
    var state = reduce(
      RaidLifecycleState.initial,
      SessionFolderChanged(folder, parseSessionFolderTime(folder)),
    ).$1;
    final tasks = <TaskTransition>[];
    var skippedNoMode = 0;
    for (final event in events) {
      final (next, transitions) = reduce(state, event);
      state = next;
      for (final transition in transitions) {
        if (transition is! TaskTransition) continue;
        if (transition.mode == null) {
          skippedNoMode++;
        } else {
          tasks.add(transition);
        }
      }
    }
    return FolderTaskRead(
      folder: folder,
      tasks: tasks,
      skippedNoMode: skippedNoMode,
      rejected: rejected,
      unreadable: false,
    );
  } on FileSystemException {
    return unreadable();
  }
}
