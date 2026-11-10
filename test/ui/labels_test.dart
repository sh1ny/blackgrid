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

  group('relativeAgeLabel', () {
    final now = DateTime(2026, 10, 3, 18, 0);
    String at(Duration ago) => relativeAgeLabel(now.subtract(ago), now);

    test('reads just now under ten seconds', () {
      expect(at(Duration.zero), 'just now');
      expect(at(const Duration(seconds: 9)), 'just now');
    });

    test('counts seconds, minutes, hours and days, flooring each', () {
      expect(at(const Duration(seconds: 10)), '10 s');
      expect(at(const Duration(seconds: 59)), '59 s');
      expect(at(const Duration(seconds: 60)), '1 min');
      expect(at(const Duration(seconds: 179)), '2 min');
      expect(at(const Duration(minutes: 59)), '59 min');
      expect(at(const Duration(minutes: 60)), '1 h');
      expect(at(const Duration(hours: 23)), '23 h');
      expect(at(const Duration(hours: 24)), '1 d');
      expect(at(const Duration(days: 2, hours: 5)), '2 d');
    });

    test('a future time reads just now', () {
      expect(
        relativeAgeLabel(now.add(const Duration(minutes: 5)), now),
        'just now',
      );
    });
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
