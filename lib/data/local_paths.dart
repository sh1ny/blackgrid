import 'dart:io';

import 'package:flutter/services.dart';

/// Name of the native channel that reports the local data folder.
///
/// It must equal the name registered in `windows/runner/local_data_channel.cpp`;
/// a source test keeps the two in step.
const String localDataChannelName = 'blackgrid/local_data';

class LocalPaths {
  const LocalPaths(this.root);
  final Directory root;
  File get database =>
      File('${root.path}${Platform.pathSeparator}blackgrid.sqlite');

  /// Directory for diagnostic logs such as `scan-timings.jsonl`.
  Directory get logs => Directory('${root.path}${Platform.pathSeparator}logs');

  /// Directory for opt-in scan frame recordings, one folder per session.
  Directory get scanFrames =>
      Directory('${root.path}${Platform.pathSeparator}scan-frames');

  /// Directory for cached item icons, created by the icon cache when it opens.
  Directory get itemIcons =>
      Directory('${root.path}${Platform.pathSeparator}item-icons');

  static Future<LocalPaths> resolve() async {
    if (!Platform.isWindows) {
      throw UnsupportedError('Blackgrid supports Windows desktop only.');
    }
    const channel = MethodChannel(localDataChannelName);
    final path = await channel.invokeMethod<String>('localDataPath');
    if (path == null || path.isEmpty) {
      throw const FileSystemException('Local application data unavailable.');
    }
    final root = Directory('$path${Platform.pathSeparator}Blackgrid');
    await root.create(recursive: true);
    // The logs directory is optional: the timing log creates it on its first
    // write and reports a failure as unavailable, so it never blocks startup.
    return LocalPaths(root);
  }
}
