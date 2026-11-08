import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../application/app_services.dart';
import 'live_scan_panel.dart';
import 'manual_controls.dart';
import 'scan_evidence_panel.dart';
import 'panels.dart';

/// Narrowest window width, in logical pixels, that gets the desktop layout.
const double desktopWindowWidth = 1100;

/// Horizontal padding the shell puts around the Scanner screen (14 per side).
const double _shellPadding = 28;

/// Height the manual search controls need at text scale 1. A shorter
/// desktop column scrolls them inside their panel.
const double leftHeight = 920;

/// Minimum height of the scan evidence panel at text scale 1.
const double evidenceHeight = 520;

/// Scan evidence and interim search controls beneath the shared answer.
///
/// Desktop keeps the evidence frame in view and scrolls its content inside;
/// compact layouts put that frame before the remaining search controls.
class ScannerScreen extends StatefulWidget {
  const ScannerScreen({super.key, required this.services});
  final AppServices services;
  @override
  State<ScannerScreen> createState() => _ScannerScreenState();
}

class _ScannerScreenState extends State<ScannerScreen> {
  /// Whether the scan evidence Details section is open. Lives here, above the
  /// breakpoint switch, so it survives a resize. Never saved.
  bool _scanDetailsExpanded = false;

  AppServices get services => widget.services;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final scale = MediaQuery.textScalerOf(context).scale(1);
      final left = GridPanel(
        title: 'Scanner',
        icon: Icons.center_focus_weak,
        // The controls need `leftHeight`; on a shorter column they scroll
        // inside their own panel instead of overflowing.
        child: LayoutBuilder(
          builder: (context, box) => SingleChildScrollView(
            key: const PageStorageKey('scanner-left-scroll'),
            child: SizedBox(
              height: math.max(box.maxHeight, leftHeight * scale),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  RecordingStopNote(scanner: services.scanner),
                  const Divider(height: 24),
                  Expanded(
                    child: ManualControls(
                      services: services,
                      storageKey: 'scanner-results',
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
      final evidence = ScanEvidencePanel(
        scanner: services.scanner,
        catalog: services.catalog,
        detailsExpanded: _scanDetailsExpanded,
        onDetailsExpandedChanged: (value) =>
            setState(() => _scanDetailsExpanded = value),
      );
      if (constraints.maxWidth + _shellPadding < desktopWindowWidth) {
        return ListView(
          key: const PageStorageKey('scanner-compact-scroll'),
          children: [
            SizedBox(height: evidenceHeight * scale, child: evidence),
            const SizedBox(height: 14),
            SizedBox(height: leftHeight * scale, child: left),
          ],
        );
      }
      return SingleChildScrollView(
        key: const PageStorageKey('scanner-desktop-scroll'),
        child: SizedBox(
          height: constraints.maxHeight,
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(flex: 3, child: left),
              const SizedBox(width: 14),
              Expanded(flex: 7, child: evidence),
            ],
          ),
        ),
      );
    },
  );
}
