import 'package:flutter/material.dart';

import '../application/app_services.dart';
import 'live_scan_panel.dart';
import 'scan_evidence_panel.dart';

/// Narrowest window width, in logical pixels, that gets the desktop layout.
const double desktopWindowWidth = 1100;

/// Scan evidence beneath the shared answer.
///
/// Desktop keeps the evidence frame in view and scrolls its content inside.
/// Compact layouts allow the frame to scroll when text needs more room.
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
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      RecordingStopNote(scanner: services.scanner),
      Expanded(
        child: LayoutBuilder(
          builder: (context, constraints) {
            final evidence = ScanEvidencePanel(
              scanner: services.scanner,
              catalog: services.catalog,
              detailsExpanded: _scanDetailsExpanded,
              onDetailsExpandedChanged: (value) =>
                  setState(() => _scanDetailsExpanded = value),
            );
            return SingleChildScrollView(
              key: PageStorageKey(
                MediaQuery.sizeOf(context).width < desktopWindowWidth
                    ? 'scanner-compact-scroll'
                    : 'scanner-desktop-scroll',
              ),
              child: SizedBox(
                height: MediaQuery.sizeOf(context).width < desktopWindowWidth
                    ? constraints.maxHeight.clamp(
                        240 * MediaQuery.textScalerOf(context).scale(1),
                        double.infinity,
                      )
                    : constraints.maxHeight,
                child: evidence,
              ),
            );
          },
        ),
      ),
    ],
  );
}
