import 'package:flutter/material.dart';

import '../application/app_services.dart';
import 'ember/ember_tokens.dart';
import 'ember/theme_access.dart';
import 'evidence_panels.dart';
import 'live_scan_text.dart';

/// The Scanner's inspector: Recent items, which scrolls, and a Live scan note
/// pinned below it.
///
/// The note sits outside the scroll view, so it stays on screen however long
/// the history grows (half the inspector at most, scrolling past that).
/// Nothing between the history rows and their scroll view
/// fixes a height, so no row is clipped.
class ScannerInspector extends StatelessWidget {
  /// Creates the inspector over [services].
  const ScannerInspector({super.key, required this.services});

  /// The services whose history and live scan state the inspector shows.
  final AppServices services;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) => Column(
      children: [
        Expanded(child: HistoryPanel(services: services)),
        // At most half the inspector, so a short window or large text scrolls
        // the note instead of overflowing.
        ConstrainedBox(
          constraints: BoxConstraints(maxHeight: constraints.maxHeight / 2),
          child: SingleChildScrollView(child: LiveScanNote(services: services)),
        ),
      ],
    ),
  );
}

/// A short note that says whether live scan is on and where to change it.
class LiveScanNote extends StatelessWidget {
  /// Creates the note over [services].
  const LiveScanNote({super.key, required this.services});

  /// The services whose scanner state the note reads.
  final AppServices services;

  @override
  Widget build(BuildContext context) {
    final ember = context.ember;
    return DecoratedBox(
      decoration: BoxDecoration(
        border: Border(top: BorderSide(color: ember.hairline)),
      ),
      child: Padding(
        key: const Key('live-scan-note'),
        padding: const EdgeInsets.all(EmberSpace.md),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Live scan',
              style: EmberType.uiHeading.copyWith(color: ember.ink),
            ),
            ListenableBuilder(
              listenable: services.scanner,
              builder: (context, _) => Text(
                '${LiveScanLines.statusText(services.scanner.status)}. '
                'Turn it on or off in the status bar or in Settings.',
                style: EmberType.label.copyWith(color: ember.inkSecondary),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
