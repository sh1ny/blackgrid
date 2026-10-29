import 'package:blackgrid/application/scan_coordinator.dart';
import 'package:blackgrid/data/vision/marker_template.dart';
import 'package:blackgrid/data/vision/vision_failure.dart';
import 'package:blackgrid/ui/scan_evidence_panel.dart';
import 'package:blackgrid/ui/theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/m1_widget_harness.dart';
import 'support/scan_ui_support.dart';

void main() {
  for (final size in [
    const Size(1672, 941),
    const Size(1912, 823),
    const Size(960, 640),
  ]) {
    for (final scale in [1.0, 1.25, 1.5]) {
      testWidgets(
        'two retained surfaces avoid overflow at $size scale $scale',
        (tester) async {
          await pumpM1(tester, size: size, scale: scale);
          expect(tester.takeException(), isNull);
          await tester.tap(find.byKey(const Key('nav-scanner')));
          await tester.pumpAndSettle();
          expect(tester.takeException(), isNull);
          expect(find.text('Live scan off • no capture'), findsOneWidget);
          expect(find.text('Scanner Ready'), findsNothing);
          expect(find.text('Auto-scan'), findsNothing);
          expect(find.text('Capture Preview'), findsNothing);
          expect(find.text('High confidence'), findsNothing);
        },
      );
    }
  }
  testWidgets('reference panel positions and proportions at Scanner aspect', (
    tester,
  ) async {
    await pumpM1(tester);
    await tester.tap(find.byKey(const Key('nav-scanner')));
    await tester.pumpAndSettle();
    Rect panel(String title) => tester.getRect(
      find.byWidgetPredicate((w) => w is GridPanel && w.title == title),
    );
    final left = panel('Scanner'),
        evidence = panel('Scan evidence'),
        current = panel('Current manual inspection'),
        history = panel('Recent item activity');
    expect(left.left, 14);
    expect(current.left, greaterThan(left.right));
    expect(evidence.left, greaterThan(current.right));
    expect(history.left, evidence.left);
    expect(history.width, evidence.width);
    final width = left.width + current.width + history.width;
    expect(left.width / width, closeTo(.19, .01));
    expect(current.width / width, closeTo(.57, .01));
    expect(history.width / width, closeTo(.24, .01));
    expect(evidence.top, history.top - evidence.height - 14);
    expect(history.top, greaterThan(evidence.bottom));
    expect(
      evidence.height / (evidence.height + history.height),
      closeTo(.6, .03),
    );
    final needs = panel('Requirements & uses'), source = panel('Data sources');
    expect(needs.top, greaterThan(current.bottom));
    expect(source.top, needs.top);
    expect(
      Theme.of(tester.element(find.byKey(const Key('nav-map'))))
          .scaffoldBackgroundColor,
      GridColors.background,
    );
  });
  testWidgets('scan evidence survives Map and back', (tester) async {
    final ports = ScanFakePorts();
    final h = await pumpM1(tester, scanPorts: ports);
    await tester.tap(find.byKey(const Key('nav-scanner')));
    await tester.pumpAndSettle();
    await tester.runAsync(
      () => publishTargetedScan(
        h.services.scanner,
        ports,
        text: 'Alternative component',
      ),
    );
    await tester.pumpAndSettle();
    final before = tester.widget<Text>(find.byKey(const Key('scan-item'))).data;
    expect(before, contains('Alternative component'));

    await tester.tap(find.byKey(const Key('nav-map')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('nav-scanner')));
    await tester.pumpAndSettle();

    expect(
      tester.widget<Text>(find.byKey(const Key('scan-item'))).data,
      before,
    );
    // The end state now lives inside the collapsed Details section.
    expect(find.byKey(const Key('scan-end')), findsNothing);
  });
  testWidgets('scan evidence Details stays expanded across Map and back', (
    tester,
  ) async {
    final ports = ScanFakePorts();
    final h = await pumpM1(tester, scanPorts: ports);
    await tester.tap(find.byKey(const Key('nav-scanner')));
    await tester.pumpAndSettle();
    await tester.runAsync(
      () => publishTargetedScan(
        h.services.scanner,
        ports,
        text: 'Alternative component',
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(
      find.descendant(
        of: find.byType(ScanEvidencePanel),
        matching: find.text('Details'),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('scan-marker')), findsOneWidget);

    await tester.tap(find.byKey(const Key('nav-map')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('nav-scanner')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('scan-marker')), findsOneWidget);
    expect(find.byKey(const Key('scan-timing-total')), findsOneWidget);
  });
  for (final size in [const Size(1672, 941), const Size(960, 640)]) {
    testWidgets('scan evidence panel does not overflow at $size', (
      tester,
    ) async {
      final ports = ScanFakePorts();
      final h = await pumpM1(tester, size: size, scale: 1.5, scanPorts: ports);
      await tester.tap(find.byKey(const Key('nav-scanner')));
      await tester.pumpAndSettle();
      await tester.runAsync(
        () => publishTargetedScan(
          h.services.scanner,
          ports,
          text: 'Alternative component',
        ),
      );
      await tester.pumpAndSettle();
      if (size.width < 1100) {
        // Compact layout: the evidence panel is further down the list.
        // Dragging would start on the manual results list at the viewport
        // centre, so move the outer list directly past the first panel.
        final outer = find
            .descendant(
              of: find.byKey(const PageStorageKey('scanner-compact-scroll')),
              matching: find.byType(Scrollable),
            )
            .first;
        tester.state<ScrollableState>(outer).position.jumpTo(1200);
        await tester.pumpAndSettle();
      }
      expect(tester.takeException(), isNull);
      expect(find.byKey(const Key('scan-item')), findsOneWidget);
    });
  }

  Future<void> openScanner(WidgetTester tester) async {
    await tester.tap(find.byKey(const Key('nav-scanner')));
    await tester.pumpAndSettle();
  }

  Rect evidenceFrame(WidgetTester tester) => tester.getRect(
    find.byWidgetPredicate((w) => w is GridPanel && w.title == 'Scan evidence'),
  );

  ScrollPosition desktopPage(WidgetTester tester) => tester
      .state<ScrollableState>(
        find
            .descendant(
              of: find.byKey(const PageStorageKey('scanner-desktop-scroll')),
              matching: find.byType(Scrollable),
            )
            .first,
      )
      .position;

  testWidgets('scan evidence panel is fully on screen at 1660x870', (
    tester,
  ) async {
    await pumpM1(tester, size: const Size(1660, 870));
    await openScanner(tester);
    final frame = evidenceFrame(tester);
    expect(frame.top, greaterThanOrEqualTo(0));
    expect(frame.bottom, lessThanOrEqualTo(870));
    expect(frame.left, greaterThanOrEqualTo(0));
    expect(frame.right, lessThanOrEqualTo(1660));
    // The page has nothing to scroll at this size.
    expect(desktopPage(tester).maxScrollExtent, 0);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'scan evidence panel is on screen at 1100x720 with a long recent list',
    (tester) async {
      final ports = ScanFakePorts();
      final h = await pumpM1(
        tester,
        size: const Size(1100, 720),
        scanPorts: ports,
      );
      await openScanner(tester);
      await tester.runAsync(() async {
        for (var i = 0; i < 10; i++) {
          await publishTargetedScan(
            h.services.scanner,
            ports,
            text: 'Alternative component $i',
            index: i,
            qpc: 1000 * (i + 1),
          );
        }
      });
      await tester.pumpAndSettle();
      expect(h.services.scanner.recent, hasLength(10));
      // Desktop layout, read with the page unscrolled.
      expect(desktopPage(tester).pixels, 0);
      final frame = evidenceFrame(tester);
      final scannerPanel = tester.getRect(
        find.byWidgetPredicate((w) => w is GridPanel && w.title == 'Scanner'),
      );
      expect(frame.left, greaterThan(scannerPanel.right));
      expect(frame.top, greaterThanOrEqualTo(0));
      expect(frame.bottom, lessThanOrEqualTo(720));
      // The list scrolls inside the panel: its last row starts off screen.
      final scroll = tester.state<ScrollableState>(
        find
            .descendant(
              of: find.byType(ScanEvidencePanel),
              matching: find.byType(Scrollable),
            )
            .first,
      );
      expect(scroll.position.maxScrollExtent, greaterThan(0));
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('compact layout puts evidence right after the Scanner controls', (
    tester,
  ) async {
    await pumpM1(tester, size: const Size(900, 1600));
    await openScanner(tester);
    final scanner = tester.getRect(
      find.byWidgetPredicate((w) => w is GridPanel && w.title == 'Scanner'),
    );
    final evidence = evidenceFrame(tester);
    expect(evidence.top, scanner.bottom + 14);
    expect(evidence.left, scanner.left);
  });

  Finder footer(String text) => find.text(text);

  testWidgets('footer says live scan is on when ready', (tester) async {
    final ports = ScanFakePorts();
    final h = await pumpM1(tester, scanPorts: ports);
    await tester.runAsync(() async {
      await h.services.scanner.setLiveScan(true);
      await h.services.scanner.settled;
    });
    await tester.pumpAndSettle();
    expect(h.services.scanner.status.state, LiveScanState.ready);
    expect(footer('Live scan on • captures on click'), findsOneWidget);
    expect(find.textContaining('No capture'), findsNothing);
  });

  testWidgets('footer says live scan is off and nothing is captured', (
    tester,
  ) async {
    await pumpM1(tester);
    expect(footer('Live scan off • no capture'), findsOneWidget);
  });

  testWidgets('footer says live scan is unavailable', (tester) async {
    final ports = ScanFakePorts()
      ..markerOverride = const MarkerTemplateUnavailable(
        VisionMissingFile('data/vision/inspection_marker.pgm'),
      );
    final h = await pumpM1(tester, scanPorts: ports);
    await tester.runAsync(() async {
      await h.services.scanner.setLiveScan(true);
      await h.services.scanner.settled;
    });
    await tester.pumpAndSettle();
    expect(h.services.scanner.status.state, LiveScanState.unavailable);
    expect(footer('Live scan unavailable'), findsOneWidget);
  });
}
