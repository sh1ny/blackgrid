import 'package:blackgrid/application/catalog_controller.dart';
import 'package:blackgrid/application/progress_controller.dart';
import 'package:blackgrid/application/scan_coordinator.dart';
import 'package:blackgrid/domain/inspection_context.dart';
import 'package:blackgrid/domain/map_session.dart';
import 'package:blackgrid/domain/raid_panel_text_parser.dart';
import 'package:blackgrid/domain/settings.dart';
import 'package:blackgrid/ui/labels.dart';
import 'package:flutter_test/flutter_test.dart';

void _expectPlain<T extends Enum>(List<T> values, String Function(T) label) {
  for (final value in values) {
    final text = label(value);
    final reason = '${value.runtimeType}.${value.name} -> "$text"';
    expect(text, isNotEmpty, reason: reason);
    expect(text, isNot(matches(RegExp('[a-z][A-Z]'))), reason: reason);
    if (!RegExp(r'^[a-z]+$').hasMatch(value.name)) {
      expect(text, isNot(equals(value.name)), reason: reason);
    }
  }
}

void main() {
  test('every value of every shown kind has a plain label', () {
    _expectPlain(CatalogStatus.values, catalogStatusLabel);
    _expectPlain(ProgressStatus.values, progressStatusLabel);
    _expectPlain(MapInputStatus.values, mapInputStatusLabel);
    _expectPlain(RaidPanelState.values, raidPanelStateLabel);
    _expectPlain(ScanRejectReason.values, scanRejectReasonLabel);
    _expectPlain(ScanFailureCode.values, scanFailureCodeLabel);
    _expectPlain(ScanPass.values, scanPassLabel);
    _expectPlain(FirState.values, firLabel);
    _expectPlain(ActivitySource.values, activitySourceLabel);
  });

  test('targeted pass reads Targeted', () {
    expect(scanPassLabel(ScanPass.targeted), 'Targeted');
  });

  group('localTimeLabel', () {
    final now = DateTime(2026, 10, 3, 18, 0);

    test('localTimeLabel gives time only for the same local day', () {
      expect(localTimeLabel(DateTime(2026, 10, 3, 9, 5), now: now), '09:05');
    });

    test('localTimeLabel gives date and time for an earlier day', () {
      expect(
        localTimeLabel(DateTime(2026, 10, 2, 14, 32), now: now),
        '2 Oct 14:32',
      );
      expect(
        localTimeLabel(DateTime(2025, 1, 21, 0, 7), now: now),
        '21 Jan 00:07',
      );
    });

    test('localTimeLabel gives unknown for null', () {
      expect(localTimeLabel(null, now: now), 'unknown');
    });
  });
}
