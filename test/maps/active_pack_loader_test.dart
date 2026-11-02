import 'dart:io';
import 'dart:typed_data';

import 'package:blackgrid/maps/prepared_map_loader.dart';
import 'package:flutter_test/flutter_test.dart';

/// Loads the committed active generation through the real loader, as the app
/// does from its asset bundle.
void main() {
  test('the real loader loads the committed active pack', () async {
    final pack = await PreparedMapPackLoader(
      loadBytes: (path) async =>
          ByteData.sublistView(await File(path).readAsBytes()),
    ).load();
    expect(pack.maps, hasLength(13));
  });
}
