import 'package:blackgrid/domain/catalog.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/m1_widget_harness.dart';

void main() {
  testWidgets(
    'Unknown first run is honest and has exactly two primary surfaces',
    (tester) async {
      final h = await pumpM1(tester, mode: GameMode.unknown);
      expect(find.byKey(const Key('nav-map')), findsOneWidget);
      expect(find.byKey(const Key('nav-scanner')), findsOneWidget);
      expect(find.text('Database'), findsNothing);
      expect(find.text('Progression'), findsNothing);
      expect(find.text('Tools'), findsNothing);
      expect(find.text('No accepted scan this session'), findsOneWidget);
      expect(h.requests, isEmpty);
      expect(tester.takeException(), isNull);
    },
  );
}
