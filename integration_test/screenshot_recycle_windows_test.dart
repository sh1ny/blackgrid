@Tags(['qualification'])
library;

import 'dart:io';

import 'package:blackgrid/application/recycle_port.dart';
import 'package:blackgrid/data/channel_recycle_port.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

import 'm1_windows_smoke_test.dart' show requireGameClosed;

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('native recycle leaves a nonrecyclable screenshot unchanged', (
    _,
  ) async {
    await requireGameClosed();
    final temp = Directory.systemTemp.path;
    final networkRoot =
        Platform.environment['BLACKGRID_RECYCLE_TEST_SHARE'] ??
        (temp.startsWith(r'\\')
            ? temp
            : '\\\\localhost\\${temp[0]}\$${temp.substring(2)}');
    final root = Directory(networkRoot);
    expect(
      networkRoot.startsWith(r'\\') && await root.exists(),
      isTrue,
      reason:
          'Set BLACKGRID_RECYCLE_TEST_SHARE to a writable UNC fixture root.',
    );
    final folder = await root.createTemp('blackgrid-recycle-');
    addTearDown(() => folder.delete(recursive: true));
    const name =
        '2026-11-22[14-05]_-120.5, 2.1, 33.4_0, 0.70711, 0, 0.70711_1.png';
    const contents = [1, 2, 3];
    final screenshot = await File('${folder.path}\\$name')
        .writeAsBytes(contents);

    final reply = await ChannelRecyclePort()
        .recycle(folder.path, [name])
        .timeout(const Duration(seconds: 10));

    expect(await screenshot.readAsBytes(), contents);
    expect(
      reply,
      isA<RecycleStatuses>().having(
        (reply) => reply.statuses[name],
        'file outcome',
        isA<RecycleNotRecyclable>(),
      ),
    );
  }, skip: !Platform.isWindows);
}
