import 'dart:io';

import 'package:flutter/services.dart';

class LocalPaths {
  const LocalPaths(this.root);
  final Directory root;
  File get database =>
      File('${root.path}${Platform.pathSeparator}blackgrid.sqlite');
  Directory get credentials =>
      Directory('${root.path}${Platform.pathSeparator}credentials');

  static Future<LocalPaths> resolve() async {
    if (!Platform.isWindows) {
      throw UnsupportedError('Blackgrid supports Windows desktop only.');
    }
    const channel = MethodChannel('blackgrid/credentials');
    final path = await channel.invokeMethod<String>('localDataPath');
    if (path == null || path.isEmpty) {
      throw const FileSystemException('Local application data unavailable.');
    }
    final root = Directory('$path${Platform.pathSeparator}Blackgrid');
    await root.create(recursive: true);
    final result = LocalPaths(root);
    await result.credentials.create();
    return result;
  }
}
