import 'package:blackgrid/application/scan_coordinator.dart';
import 'package:blackgrid/data/capture/capture_service.dart';
import 'package:flutter_test/flutter_test.dart';

import '../data/capture/support/holdable_capture_platform.dart';

void main() {
  group('capture port', () {
    test('a service that never failed has no unavailable reason', () {
      final service = CaptureService(platformFactory: failingFactory);
      addTearDown(service.close);

      expect(scanCapturePort(service).unavailableReason, isNull);
    });

    test('an unavailable service reports its own reason', () {
      final service = CaptureService(platformFactory: failingFactory);
      addTearDown(service.close);
      service.debugReportWorkerError('crafted worker error');

      final reason = scanCapturePort(service).unavailableReason;
      expect(reason?.code, ScanFailureCode.captureUnavailable);
      expect(reason?.message, contains('crafted worker error'));
    });
  });
}
