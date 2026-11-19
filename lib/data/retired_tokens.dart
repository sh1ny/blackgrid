import 'dart:io';

import 'package:flutter/foundation.dart';

import 'local_paths.dart';

/// Matches the three token files and the old store's crash leftovers.
///
/// The store wrote `<mode>.dpapi` and, while replacing it,
/// `<mode>.dpapi.<pid>.<microseconds>.tmp`. Anything else is not ours.
final RegExp _retiredTokenName = RegExp(
  r'^(pvp|pve|seasonal)\.dpapi(\.[^.\/]+\.[^.\/]+\.tmp)?$',
);

Future<void> _deleteFile(File file) => file.delete();

/// Deletes the saved progress-site tokens the app no longer uses.
///
/// Removes `pvp.dpapi`, `pve.dpapi`, `seasonal.dpapi` and their
/// `<mode>.dpapi.*.tmp` crash leftovers from the `credentials` folder under
/// [paths], then the folder itself only when it is empty. The files are never
/// read, and nothing else is deleted: the folder is listed without recursion
/// and a file with any other name is kept. A missing folder is left missing.
///
/// Every failure is reported with one `debugPrint` and swallowed, so start-up
/// never waits on it or fails because of it. The next launch tries again.
///
/// [deleteFile] replaces the real delete so tests can simulate a locked file.
Future<void> deleteRetiredTokens(
  LocalPaths paths, {
  Future<void> Function(File file) deleteFile = _deleteFile,
}) async {
  try {
    final folder = Directory(
      '${paths.root.path}${Platform.pathSeparator}credentials',
    );
    if (!await folder.exists()) return;
    await for (final entry in folder.list(followLinks: false)) {
      if (entry is! File) continue;
      final name = entry.uri.pathSegments.last;
      if (!_retiredTokenName.hasMatch(name)) continue;
      try {
        await deleteFile(entry);
      } on Object catch (error) {
        // One locked file must not stop the others from being deleted.
        debugPrint('Retired token file kept until the next launch ($error)');
      }
    }
    if (await folder.list(followLinks: false).isEmpty) await folder.delete();
  } on Object catch (error) {
    debugPrint('Retired token clean-up deferred to the next launch ($error)');
  }
}
