import 'dart:io';

import 'package:blackgrid/data/local_paths.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('logs directory lives under the data root', () {
    final root = Directory('data-root');
    expect(
      LocalPaths(Directory('data-root')).logs.path,
      '${root.path}${Platform.pathSeparator}logs',
    );
  });
}
