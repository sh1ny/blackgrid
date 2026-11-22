import 'dart:io';

import '../domain/screenshot_cleanup.dart';

/// The result of reading a screenshot folder.
sealed class ScreenshotFolderListing {
  const ScreenshotFolderListing();
}

/// A folder that was read successfully.
final class ScreenshotFolderListed extends ScreenshotFolderListing {
  /// Creates a successful listing.
  const ScreenshotFolderListed(this.entries);

  /// Metadata for the folder's direct regular files.
  final List<ScreenshotEntry> entries;
}

/// A screenshot folder that does not exist.
final class ScreenshotFolderMissing extends ScreenshotFolderListing {
  /// Creates a missing-folder result.
  const ScreenshotFolderMissing();
}

/// A screenshot folder that could not be read.
final class ScreenshotFolderUnreadable extends ScreenshotFolderListing {
  /// Creates an unreadable-folder result.
  const ScreenshotFolderUnreadable();
}

/// Reads direct file metadata without following links in a screenshot folder.
class ScreenshotFolderLister {
  /// Lists [folder], dropping individual entries whose metadata is unavailable.
  Future<ScreenshotFolderListing> list(String folder) async {
    final entries = <ScreenshotEntry>[];
    try {
      await for (final entity in Directory(folder).list(followLinks: false)) {
        if (entity is! File) continue;
        try {
          final stat = await entity.stat();
          if (stat.type != FileSystemEntityType.file) continue;
          final path = entity.path;
          final slash = path.lastIndexOf('/');
          final backslash = path.lastIndexOf('\\');
          final separator = slash > backslash ? slash : backslash;
          entries.add(
            ScreenshotEntry(
              name: path.substring(separator + 1),
              isFile: true,
              isLink: false,
              modified: stat.modified,
            ),
          );
        } on FileSystemException {
          // A single vanished or inaccessible entry does not invalidate others.
        }
      }
      return ScreenshotFolderListed(entries);
    } on FileSystemException catch (error) {
      final code = error.osError?.errorCode;
      if (code == 2 || (Platform.isWindows && code == 3)) {
        return const ScreenshotFolderMissing();
      }
      return const ScreenshotFolderUnreadable();
    }
  }
}
