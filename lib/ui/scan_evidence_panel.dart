import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../application/catalog_controller.dart';
import '../application/scan_coordinator.dart';
import '../data/vision/inspection_evidence.dart';
import '../domain/title_matching.dart';
import 'labels.dart';
import 'theme.dart';

/// What the last accepted scan found (the latest published scan before any is
/// accepted), a note for a later scan that was not accepted, the phase of the
/// scan in flight and the recent scans, in plain words. Scores, codes, the
/// title crop and the stage timings sit in a Details section.
///
/// It only shows evidence. It never selects an item or reads a decision, so a
/// scan cannot change what the decision card shows.
class ScanEvidencePanel extends StatefulWidget {
  /// Creates the panel over [scanner]; [catalog] supplies item names.
  const ScanEvidencePanel({
    super.key,
    required this.scanner,
    required this.catalog,
    required this.detailsExpanded,
    required this.onDetailsExpandedChanged,
  });

  /// The coordinator whose phase, last accepted, latest and recent scans are
  /// shown.
  final ScanCoordinator scanner;

  /// The catalog the item names come from.
  final CatalogController catalog;

  /// Whether the Details section is expanded; owned by the screen.
  final bool detailsExpanded;

  /// Called when the Details section asks to expand or collapse.
  final ValueChanged<bool> onDetailsExpandedChanged;

  @override
  State<ScanEvidencePanel> createState() => _ScanEvidencePanelState();
}

class _ScanEvidencePanelState extends State<ScanEvidencePanel> {
  /// The decoded title crop of the report [_imageFor], else null.
  ui.Image? _image;

  /// The id of the report whose crop is decoded or being decoded.
  int? _imageFor;

  @override
  void initState() {
    super.initState();
    widget.scanner.addListener(_syncImage);
    _syncImage();
  }

  @override
  void didUpdateWidget(ScanEvidencePanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.scanner != widget.scanner) {
      oldWidget.scanner.removeListener(_syncImage);
      widget.scanner.addListener(_syncImage);
      _imageFor = null;
      _syncImage();
    }
  }

  @override
  void dispose() {
    widget.scanner.removeListener(_syncImage);
    _imageFor = null;
    _image?.dispose();
    _image = null;
    super.dispose();
  }

  /// Decodes the shown report's crop once per report id and disposes the
  /// image it replaces.
  void _syncImage() {
    final report = _shown(widget.scanner);
    final entry = report == null ? null : shownEvidence(report);
    final id = entry != null && _hasCrop(entry) ? report!.id : null;
    if (id == _imageFor) return;
    _imageFor = id;
    final old = _image;
    _image = null;
    if (old != null) {
      if (mounted) setState(() {});
      old.dispose();
    }
    if (id == null || entry == null) return;
    ui.decodeImageFromPixels(
      _grayToRgba(entry.crop),
      entry.cropWidth,
      entry.cropHeight,
      ui.PixelFormat.rgba8888,
      (image) {
        if (!mounted || _imageFor != id) {
          image.dispose();
          return;
        }
        setState(() => _image = image);
      },
    );
  }

  @override
  Widget build(BuildContext context) => GridPanel(
    title: 'Scan evidence',
    icon: Icons.fact_check_outlined,
    subtitle: 'Latest scan · shows what was read, never a keep/sell call',
    child: ListenableBuilder(
      listenable: Listenable.merge([widget.scanner, widget.catalog]),
      builder: (context, _) {
        final scanner = widget.scanner;
        final latest = scanner.latest;
        final shown = _shown(scanner);
        final frequency = scanner.clock?.qpcFrequency();
        return ListView(
          key: const PageStorageKey('scan-evidence-scroll'),
          children: [
            ..._phase(scanner.phase),
            if (shown == null)
              const Text('No scan published yet')
            else ...[
              if (latest != null && latest.id != shown.id)
                ..._note(context, latest),
              ..._summary(shown),
            ],
            const Divider(height: 24),
            const Text(
              'RECENT SCANS',
              style: TextStyle(
                color: GridColors.gold,
                fontSize: 12,
                letterSpacing: 1,
              ),
            ),
            const SizedBox(height: 6),
            if (scanner.recent.isEmpty)
              const Text('None yet')
            else
              for (final report in scanner.recent)
                Padding(
                  padding: const EdgeInsets.only(bottom: 4),
                  child: Text(
                    _recentRow(report),
                    key: Key('scan-recent-${report.id}'),
                  ),
                ),
            const Divider(height: 24),
            DetailsSection(
              expanded: widget.detailsExpanded,
              onExpandedChanged: widget.onDetailsExpandedChanged,
              builder: (context) =>
                  _details(context, shown, latest, scanner.recent, frequency),
            ),
          ],
        );
      },
    ),
  );

  List<Widget> _phase(ScanPhase phase) => switch (phase) {
    ScanPhase.idle => const [],
    ScanPhase.targeted => const [
      Text('Reading the item…', key: Key('scan-phase')),
      SizedBox(height: 8),
    ],
    ScanPhase.fallback => const [
      Text('Trying a wider scan…', key: Key('scan-phase')),
      SizedBox(height: 8),
    ],
  };

  /// The open-view note for [report], a later scan that was not accepted.
  List<Widget> _note(BuildContext context, ScanReport report) {
    final (reason, match) = switch (report.end) {
      ScanRejected(:final reason, :final outcome) => (
        scanRejectReasonLabel(reason),
        outcome?.match,
      ),
      ScanFailed(:final failure) => (scanFailureCodeLabel(failure.code), null),
      ScanAccepted() || ScanSuperseded() => ('', null),
    };
    return [
      Text(
        'Last scan not recognised: $reason',
        key: const Key('scan-note-reason'),
        style: Theme.of(context).textTheme.titleSmall,
      ),
      _candidate(match, key: 'scan-note-best'),
      const Divider(height: 24),
    ];
  }

  /// The open-view summary of the shown [report]: the accepted item's name, or
  /// the plain reason and the best candidate, labelled not accepted.
  List<Widget> _summary(ScanReport report) => switch (report.end) {
    ScanAccepted(:final itemId) => [
      Text(_itemName(itemId), key: const Key('scan-item')),
    ],
    ScanRejected(:final reason, :final outcome) => [
      Text(scanRejectReasonLabel(reason), key: const Key('scan-reason')),
      _candidate(outcome?.match, key: 'scan-candidate'),
    ],
    ScanFailed(:final failure) => [
      Text(scanFailureCodeLabel(failure.code), key: const Key('scan-reason')),
      const Text('No candidate'),
    ],
    ScanSuperseded() => [
      Text(
        scanFailureCodeLabel(ScanFailureCode.visionSuperseded),
        key: const Key('scan-reason'),
      ),
    ],
  };

  /// The best candidate of [match] as `<name> (not accepted)`, else
  /// `No candidate`.
  Widget _candidate(TitleMatch? match, {required String key}) =>
      switch (match?.bestId) {
        final String id => Text(
          '${_itemName(id)} (not accepted)',
          key: Key(key),
        ),
        null => const Text('No candidate'),
      };

  /// The Details content, in order: the note scan's code, OCR text and marker
  /// score; the shown scan's evidence; the timings; each recent entry's end
  /// state and total.
  Widget _details(
    BuildContext context,
    ScanReport? shown,
    ScanReport? latest,
    List<ScanReport> recent,
    int? frequency,
  ) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      if (shown != null) ...[
        if (latest != null && latest.id != shown.id)
          ..._noteDetails(context, latest),
        ..._shownDetails(context, shown),
      ],
      if (latest != null) ...[
        const SizedBox(height: 10),
        Text(
          'Timings • Scan #${latest.id}',
          key: const Key('scan-timings-label'),
          style: Theme.of(context).textTheme.titleSmall,
        ),
        ..._timings(latest, frequency),
      ],
      if (recent.isNotEmpty) ...[
        const SizedBox(height: 10),
        Text('Recent scans', style: Theme.of(context).textTheme.titleSmall),
        for (final report in recent)
          Text(
            _recentDetail(report, frequency),
            key: Key('scan-recent-detail-${report.id}'),
          ),
      ],
    ],
  );

  /// Code, OCR text and marker score of the note scan [report].
  List<Widget> _noteDetails(BuildContext context, ScanReport report) {
    final entry = shownEvidence(report);
    final code = switch (report.end) {
      ScanRejected(:final reason) => reason.logCode,
      ScanFailed(:final failure) => failure.code.logCode,
      ScanAccepted() || ScanSuperseded() => null,
    };
    return [
      Text(
        'Last scan • Scan #${report.id}',
        style: Theme.of(context).textTheme.titleSmall,
      ),
      if (code != null) Text('Code: $code', key: const Key('scan-note-code')),
      if (entry != null) ...[
        Text(
          'OCR text: ${entry.text.isEmpty ? '(empty)' : entry.text}',
          key: const Key('scan-note-text'),
        ),
        Text(
          'Marker score ${_score(entry.markerScore)}',
          key: const Key('scan-note-marker'),
        ),
      ],
      const Divider(height: 24),
    ];
  }

  /// End state, pass, marker score, crop, OCR text, candidates, item ID and
  /// code of the shown [report].
  List<Widget> _shownDetails(BuildContext context, ScanReport report) {
    final entry = shownEvidence(report);
    final match = switch (report.end) {
      ScanAccepted(:final outcome) => outcome.match,
      ScanRejected(:final outcome) => outcome?.match,
      ScanFailed() || ScanSuperseded() => null,
    };
    return [
      Text('Scan #${report.id}', style: Theme.of(context).textTheme.titleSmall),
      Text(_endLabel(report.end), key: const Key('scan-end')),
      if (report.winningPass case final ScanPass pass)
        Text('Pass: ${scanPassLabel(pass)}', key: const Key('scan-pass')),
      if (entry != null)
        ..._entry(entry)
      else if (shownBestMarkerScore(report) case final double score)
        ..._noEntry(score),
      ..._candidates(match, accepted: report.end is ScanAccepted),
      ...switch (report.end) {
        ScanAccepted(:final itemId) => [
          Text('Item ID: $itemId', key: const Key('scan-item-id')),
        ],
        ScanRejected(:final reason, :final fallbackFailure) => [
          Text('Code: ${reason.logCode}', key: const Key('scan-reason-code')),
          if (fallbackFailure case final ScanFailure failure)
            Text(
              'Wider scan failure: ${failure.code.logCode}',
              key: const Key('scan-fallback-failure'),
            ),
        ],
        ScanFailed(:final failure) => [
          Text(
            'Code: ${failure.code.logCode}',
            key: const Key('scan-reason-code'),
          ),
          Text(failure.message, key: const Key('scan-failure-message')),
        ],
        ScanSuperseded() => const <Widget>[],
      },
    ];
  }

  List<Widget> _candidates(TitleMatch? match, {required bool accepted}) {
    final bestId = match?.bestId;
    if (match == null || bestId == null) return const [];
    return [
      Text(
        accepted
            ? 'Best: ${_itemLabel(bestId)} ${_score(match.bestScore)}'
            : 'Best candidate (not accepted): ${_itemLabel(bestId)} '
                  '${_score(match.bestScore)}',
        key: const Key('scan-best'),
      ),
      if (match.runnerUpId case final String runnerUp)
        Text(
          'Runner-up: ${_itemLabel(runnerUp)} ${_score(match.runnerUpScore)}',
          key: const Key('scan-runner-up'),
        ),
      Text('Margin ${_score(match.margin)}', key: const Key('scan-margin')),
    ];
  }

  List<Widget> _entry(InspectionEvidence entry) {
    final image = _image;
    return [
      Text(
        'Marker score ${_score(entry.markerScore)}',
        key: const Key('scan-marker'),
      ),
      const SizedBox(height: 6),
      if (image != null && _imageFor != null)
        Align(
          alignment: Alignment.centerLeft,
          child: SizedBox(
            width: 200,
            child: AspectRatio(
              aspectRatio: image.width / image.height,
              child: RawImage(
                key: const Key('scan-crop-image'),
                image: image,
                fit: BoxFit.contain,
                filterQuality: FilterQuality.none,
              ),
            ),
          ),
        )
      else
        Text(
          _hasCrop(entry) ? 'Decoding title crop…' : 'No title crop',
          key: const Key('scan-crop-placeholder'),
        ),
      const SizedBox(height: 6),
      Text(
        'OCR text: ${entry.text.isEmpty ? '(empty)' : entry.text}',
        key: const Key('scan-text'),
      ),
    ];
  }

  /// The evidence rows of a pass that produced no entry, such as `noMarker`.
  List<Widget> _noEntry(double bestMarkerScore) => [
    Text(
      'Best marker score ${_score(bestMarkerScore)} (no entry)',
      key: const Key('scan-marker'),
    ),
    const SizedBox(height: 6),
    const Text('No title crop', key: Key('scan-crop-placeholder')),
    const SizedBox(height: 6),
    const Text('OCR text: (none)', key: Key('scan-text')),
  ];

  List<Widget> _timings(ScanReport report, int? frequency) {
    final timeline = report.timeline;
    String ms(int? stamp) => stamp == null || frequency == null
        ? 'absent'
        : _ms(timeline.msFromTrigger(stamp, frequency));
    Text stage(String key, String label, int? stamp) {
      final value = ms(stamp);
      return Text(
        value == 'absent' ? '$label absent' : '$label $value',
        key: Key(key),
      );
    }

    List<Widget> pass(String name, PassTimeline? timeline) => timeline == null
        ? const []
        : [
            Text('${name[0].toUpperCase()}${name.substring(1)} pass'),
            stage(
              'scan-timing-$name-capture',
              'Capture',
              timeline.captureAnswered,
            ),
            stage('scan-timing-$name-vision', 'Vision', timeline.jobFinished),
            stage(
              'scan-timing-$name-matching',
              'Matching',
              timeline.matchFinished,
            ),
          ];
    final published = timeline.published;
    return [
      ...pass('targeted', timeline.targeted),
      ...pass('fallback', timeline.fallback),
      Text(
        published == null || frequency == null
            ? 'Total absent'
            : 'Total ${_ms(timeline.msFromTrigger(published, frequency))}',
        key: const Key('scan-timing-total'),
      ),
    ];
  }

  /// The open-view recent row: the item name or plain reason, and "hotkey"
  /// when the hotkey started the scan.
  String _recentRow(ScanReport report) {
    final subject = switch (report.end) {
      ScanAccepted(:final itemId) => _itemName(itemId),
      ScanRejected(:final reason) => scanRejectReasonLabel(reason),
      ScanFailed(:final failure) => scanFailureCodeLabel(failure.code),
      ScanSuperseded() => scanFailureCodeLabel(
        ScanFailureCode.visionSuperseded,
      ),
    };
    return report.byHotkey ? '$subject · hotkey' : subject;
  }

  /// The Details recent row: the end state and the total.
  String _recentDetail(ScanReport report, int? frequency) {
    final published = report.timeline.published;
    final total = published == null || frequency == null
        ? 'no total'
        : _ms(report.timeline.msFromTrigger(published, frequency));
    return '#${report.id} ${_endLabel(report.end)} · $total';
  }

  String _itemName(String id) => widget.catalog.snapshot?.items[id]?.name ?? id;

  String _itemLabel(String id) {
    final name = widget.catalog.snapshot?.items[id]?.name;
    return name == null ? id : '$name ($id)';
  }
}

/// The report whose evidence the panel shows: the last accepted scan, else
/// the latest published one.
ScanReport? _shown(ScanCoordinator scanner) =>
    scanner.lastAccepted ?? scanner.latest;

/// The evidence entry the panel shows for [report]: the accepted or best
/// ranked entry, else the first entry of the winning or any pass.
InspectionEvidence? shownEvidence(ScanReport report) => switch (report.end) {
  ScanAccepted(:final outcome) => outcome.evidence,
  ScanRejected(:final outcome) =>
    outcome?.evidence ??
        _firstEntry(report.fallback) ??
        _firstEntry(report.targeted),
  ScanFailed() || ScanSuperseded() => null,
};

/// The best marker score the panel shows for [report] when it has no
/// [shownEvidence]: that of the winning pass, else of the last pass that
/// recognised. Null for a superseded scan or one with no recognition.
double? shownBestMarkerScore(ScanReport report) {
  if (report.end is ScanSuperseded) return null;
  final passes = switch (report.winningPass) {
    ScanPass.targeted => [report.targeted],
    ScanPass.fallback => [report.fallback],
    null => [report.fallback, report.targeted],
  };
  for (final pass in passes) {
    final score = switch (pass?.recognition) {
      InspectionRecognised(:final bestMarkerScore) => bestMarkerScore,
      InspectionRejected(:final bestMarkerScore) => bestMarkerScore,
      null => null,
    };
    if (score != null) return score;
  }
  return null;
}

InspectionEvidence? _firstEntry(PassReport? pass) =>
    switch (pass?.recognition) {
      InspectionRecognised(:final evidence) when evidence.isNotEmpty =>
        evidence.first,
      _ => null,
    };

bool _hasCrop(InspectionEvidence entry) =>
    entry.cropWidth > 0 &&
    entry.cropHeight > 0 &&
    entry.crop.length == entry.cropWidth * entry.cropHeight;

Uint8List _grayToRgba(Uint8List gray) {
  final rgba = Uint8List(gray.length * 4);
  for (var i = 0; i < gray.length; i++) {
    final j = i * 4;
    rgba[j] = rgba[j + 1] = rgba[j + 2] = gray[i];
    rgba[j + 3] = 255;
  }
  return rgba;
}

String _endLabel(ScanEnd end) => switch (end) {
  ScanAccepted() => 'Accepted',
  ScanRejected() => 'Rejected',
  ScanFailed() => 'Failed',
  ScanSuperseded() => 'Superseded',
};

String _score(double value) => value.toStringAsFixed(2);

String _ms(double value) => value == value.roundToDouble()
    ? '${value.round()} ms'
    : '${value.toStringAsFixed(1)} ms';
