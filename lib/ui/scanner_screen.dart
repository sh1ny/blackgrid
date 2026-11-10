import 'package:flutter/material.dart';

import '../application/app_services.dart';
import 'ember/ember_tokens.dart';
import 'evidence_panels.dart';
import 'live_scan_text.dart';
import 'scan_evidence_panel.dart';
import 'scanner_sections.dart';

/// Narrowest window width, in logical pixels, that gets the desktop layout.
const double desktopWindowWidth = 1100;

/// Narrowest main column, in logical pixels, that places Why beside Prices.
const double sideBySideColumnWidth = 720;

/// The Scanner's main column: Why, Prices and Scan evidence in one scroll view.
///
/// The sections are flat and sit on the column surface. Why and Prices sit
/// side by side when the column is at least [sideBySideColumnWidth] wide and
/// stack below that, with Scan evidence last. The recording-stopped note comes
/// first when it shows. The whole column scrolls as one.
class ScannerScreen extends StatefulWidget {
  /// Creates the column over [services].
  const ScannerScreen({super.key, required this.services});

  /// The services whose selection and scans the sections show.
  final AppServices services;

  @override
  State<ScannerScreen> createState() => _ScannerScreenState();
}

class _ScannerScreenState extends State<ScannerScreen> {
  /// Keeps optional uses open per inspected item while the Scanner is mounted.
  late RequirementExpansion _expansion;

  @override
  void initState() {
    super.initState();
    _expansion = RequirementExpansion(widget.services.selection);
  }

  @override
  void didUpdateWidget(ScannerScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.services.selection != widget.services.selection) {
      _expansion.dispose();
      _expansion = RequirementExpansion(widget.services.selection);
    }
  }

  @override
  void dispose() {
    _expansion.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final services = widget.services;
    return LayoutBuilder(
      builder: (context, constraints) {
        final why = WhySection(
          selection: services.selection,
          expansion: _expansion,
        );
        final prices = PricesSection(selection: services.selection);
        final sideBySide = constraints.maxWidth >= sideBySideColumnWidth;
        return SingleChildScrollView(
          key: PageStorageKey(
            MediaQuery.sizeOf(context).width < desktopWindowWidth
                ? 'scanner-compact-scroll'
                : 'scanner-desktop-scroll',
          ),
          padding: const EdgeInsets.all(EmberSpace.lg),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              RecordingStopNote(scanner: services.scanner),
              if (sideBySide)
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(child: why),
                    const SizedBox(width: EmberSpace.xl),
                    Expanded(child: prices),
                  ],
                )
              else ...[
                why,
                const SizedBox(height: EmberSpace.xl),
                prices,
              ],
              const SizedBox(height: EmberSpace.xl),
              ScanEvidenceSection(
                scanner: services.scanner,
                catalog: services.catalog,
              ),
            ],
          ),
        );
      },
    );
  }
}
