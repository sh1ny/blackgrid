import 'dart:async';

import 'package:blackgrid/application/history_controller.dart';
import 'package:blackgrid/domain/settings.dart';

/// Completes once [history] holds a row for which [matches] is true.
Future<void> untilRow(
  HistoryController history,
  bool Function(ItemActivity row) matches,
) {
  if (history.rows.any(matches)) return Future.value();
  final done = Completer<void>();
  void listen() {
    if (history.rows.any(matches) && !done.isCompleted) done.complete();
  }

  history.addListener(listen);
  return done.future.whenComplete(() => history.removeListener(listen));
}
