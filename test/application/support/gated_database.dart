import 'dart:async';

import 'package:blackgrid/data/database.dart';
import 'package:blackgrid/domain/settings.dart';

/// A database whose settings writes can be held at [saveGate].
class GatedDatabase extends BlackgridDatabase {
  GatedDatabase(super.executor);

  /// When set, settings writes wait for it before writing.
  Completer<void>? saveGate;

  /// Completes when a held settings write starts waiting.
  final Completer<void> saveEntered = Completer<void>();

  @override
  Future<void> saveSettings(AppSettings settings) async {
    final gate = saveGate;
    if (gate != null) {
      if (!saveEntered.isCompleted) saveEntered.complete();
      await gate.future;
    }
    await super.saveSettings(settings);
  }
}
