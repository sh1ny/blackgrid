import 'dart:io';

import 'package:flutter/services.dart';

/// Loads the app's own Geist and Literata fonts into the test process.
///
/// Widget tests draw text in a placeholder font whose glyphs are full squares,
/// far wider than Geist, so a width check in that font fails layouts that fit
/// in the app. Fonts load for the whole test process, so call this only from a
/// test file whose every test is meant to measure the real fonts. Run it inside
/// `tester.runAsync`, because it reads files.
Future<void> loadRealFonts() async {
  for (final (family, path) in const [
    ('Geist', 'assets/fonts/Geist[wght].ttf'),
    ('Literata', 'assets/fonts/Literata[opsz,wght].ttf'),
  ]) {
    final bytes = await File(path).readAsBytes();
    await (FontLoader(
      family,
    )..addFont(Future.value(ByteData.sublistView(bytes)))).load();
  }
}
