import 'package:flutter/material.dart';

import '../../application/app_services.dart';
import '../evidence_panels.dart';
import '../map_diagnostics.dart';
import '../scan_evidence_panel.dart';

/// The body of the Diagnostics section: Map inputs, Scans and Data sources,
/// each under a small heading.
///
/// The section's own expansion decides whether this is built at all, so a
/// collapsed Diagnostics does no scan or source work.
class SettingsDiagnosticsBody extends StatelessWidget {
  /// Creates the body over [services].
  const SettingsDiagnosticsBody({super.key, required this.services});

  /// The services whose detail is shown.
  final AppServices services;

  Widget _heading(BuildContext context, String title) => Padding(
    padding: const EdgeInsets.only(top: 14, bottom: 6),
    child: Text(title, style: Theme.of(context).textTheme.titleSmall),
  );

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      _heading(context, 'Map inputs'),
      MapDiagnostics(key: const Key('map-input-status'), services: services),
      _heading(context, 'Scans'),
      ScanDiagnostics(scanner: services.scanner, catalog: services.catalog),
      _heading(context, 'Data sources'),
      DataSourceDiagnostics(services: services),
    ],
  );
}
