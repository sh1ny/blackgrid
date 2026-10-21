import 'dart:io';

import 'package:blackgrid/data/local_paths.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('logs directory lives under the data root', () {
    final root = Directory('data-root');
    expect(
      LocalPaths(Directory('data-root')).logs.path,
      '${root.path}${Platform.pathSeparator}logs',
    );
  });

  test('item icons directory lives under the data root', () {
    final root = Directory('data-root');
    expect(
      LocalPaths(root).itemIcons.path,
      '${root.path}${Platform.pathSeparator}item-icons',
    );
  });

  test('resolve does not need the logs directory', () async {
    final data = Directory.systemTemp.createTempSync('blackgrid-paths-');
    addTearDown(() => data.deleteSync(recursive: true));
    final root = Directory('${data.path}${Platform.pathSeparator}Blackgrid')
      ..createSync();
    // A file where the logs directory would go must not block startup; the
    // timing log reports it as unavailable on its first write instead.
    File('${root.path}${Platform.pathSeparator}logs').writeAsStringSync('x');
    const channel = MethodChannel('blackgrid/credentials');
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(
      channel,
      (call) async => call.method == 'localDataPath' ? data.path : null,
    );
    addTearDown(() => messenger.setMockMethodCallHandler(channel, null));

    final paths = await LocalPaths.resolve();

    expect(paths.root.path, root.path);
    expect(paths.credentials.existsSync(), isTrue);
  });
}
