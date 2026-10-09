import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../application/app_services.dart';
import 'evidence_panels.dart';
import 'item_decision_card.dart';
import 'live_scan_panel.dart';
import 'manual_controls.dart';
import 'scan_evidence_panel.dart';
import 'theme.dart';

/// Height of the live scan and manual controls panel at text scale 1.
const double leftHeight = 760;

/// Minimum height of the scan evidence panel at text scale 1.
const double evidenceHeight = 520;

class ScannerScreen extends StatelessWidget {
  const ScannerScreen({super.key, required this.services});
  final AppServices services;
  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final scale = MediaQuery.textScalerOf(context).scale(1);
      final left = GridPanel(
        title: 'Scanner',
        icon: Icons.center_focus_weak,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            LiveScanPanel(
              scanner: services.scanner,
              timingLog: services.scanTimingLog,
            ),
            const Divider(height: 24),
            Expanded(
              child: ManualControls(
                services: services,
                storageKey: 'scanner-results',
              ),
            ),
          ],
        ),
      );
      final evidence = ScanEvidencePanel(
        scanner: services.scanner,
        catalog: services.catalog,
      );
      final current = ItemDecisionCard(services: services);
      final needs = RequirementPanel(services: services);
      final sources = SourcePanel(services: services);
      final history = HistoryPanel(services: services);
      if (constraints.maxWidth < 1100) {
        return ListView(
          key: const PageStorageKey('scanner-compact-scroll'),
          children: [
            SizedBox(height: leftHeight * scale, child: left),
            const SizedBox(height: 14),
            SizedBox(height: evidenceHeight * scale, child: evidence),
            const SizedBox(height: 14),
            SizedBox(height: 490 * scale, child: current),
            const SizedBox(height: 14),
            SizedBox(height: 420 * scale, child: needs),
            const SizedBox(height: 14),
            SizedBox(height: 430 * scale, child: sources),
            const SizedBox(height: 14),
            SizedBox(height: 440 * scale, child: history),
          ],
        );
      }
      return SingleChildScrollView(
        key: const PageStorageKey('scanner-desktop-scroll'),
        child: SizedBox(
          height: math.max(constraints.maxHeight, 700 * scale),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(
                flex: 19,
                child: SingleChildScrollView(
                  key: const PageStorageKey('scanner-left-scroll'),
                  child: Column(
                    children: [
                      SizedBox(height: leftHeight * scale, child: left),
                      const SizedBox(height: 14),
                      SizedBox(
                        height: math.max(
                          constraints.maxHeight - (leftHeight * scale) - 14,
                          evidenceHeight * scale,
                        ),
                        child: evidence,
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                flex: 57,
                child: Column(
                  children: [
                    Expanded(flex: 46, child: current),
                    const SizedBox(height: 14),
                    Expanded(
                      flex: 54,
                      child: Row(
                        children: [
                          Expanded(child: needs),
                          const SizedBox(width: 14),
                          Expanded(child: sources),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 14),
              Expanded(flex: 24, child: history),
            ],
          ),
        ),
      );
    },
  );
}
