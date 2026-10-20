import 'package:blackgrid/application/accepted_scan.dart';
import 'package:blackgrid/application/scan_epoch.dart';
import 'package:blackgrid/application/session_scan_state.dart';
import 'package:blackgrid/domain/catalog.dart';
import 'package:blackgrid/domain/decision.dart';
import 'package:flutter_test/flutter_test.dart';

AcceptedScan scan(int reportId, {String itemId = 'b'}) => AcceptedScan(
  reportId: reportId,
  itemId: itemId,
  mode: GameMode.pvp,
  catalogRevision: 'r1',
  acceptedAt: DateTime.utc(2026, 10, 20, 12, reportId),
  epoch: const ScanEpoch(1, 1),
  decisionAtAcceptance: ItemDecision(
    recommendation: Recommendation.keep,
    reasons: const [],
    warnings: const [],
  ),
);

void main() {
  late SessionScanState state;
  late int notified;

  setUp(() {
    state = SessionScanState();
    notified = 0;
    state.addListener(() => notified++);
  });

  tearDown(() => state.dispose());

  test('is empty at construction', () {
    expect(state.latest, isNull);
    expect(state.hasAcceptedScan, isFalse);
  });

  test('a newer report replaces the latest scan', () {
    final first = scan(7);
    final newer = scan(8, itemId: 'e');

    state.advance(first);
    expect(state.latest, same(first));
    expect(state.hasAcceptedScan, isTrue);

    state.advance(newer);
    expect(state.latest, same(newer));
    expect(notified, 2);
  });

  test('ignores an equal or lower report id without notifying', () {
    final current = scan(7);
    state.advance(current);

    state.advance(scan(7, itemId: 'c'));
    state.advance(scan(5, itemId: 'd'));

    expect(state.latest, same(current));
    expect(notified, 1);
  });

  test('clear empties it, notifies and keeps the report-id mark', () {
    state.advance(scan(7));

    state.clear();
    expect(state.latest, isNull);
    expect(state.hasAcceptedScan, isFalse);
    expect(notified, 2);

    state.advance(scan(5));
    expect(state.latest, isNull);
    expect(notified, 2);

    final next = scan(8);
    state.advance(next);
    expect(state.latest, same(next));
    expect(notified, 3);
  });

  test('clear on an empty state does not notify', () {
    state.clear();
    expect(notified, 0);
  });
}
