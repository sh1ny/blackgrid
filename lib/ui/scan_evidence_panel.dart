import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../application/catalog_controller.dart';
import '../application/scan_coordinator.dart';
import '../data/vision/inspection_evidence.dart';
import '../domain/title_matching.dart';
import 'theme.dart';

/// What the last accepted scan found (the latest published scan before any is
/// accepted), a note for a later scan that was not accepted, the phase of the
/// scan in flight, the latest scan's stage timings and the recent scans.
///
/// It only shows evidence. It never selects an item or reads a decision, so a
/// scan cannot change what the decision card shows.
class ScanEvidencePanel extends StatefulWidget {
  /// Creates the panel over [scanner]; [catalog] supplies item names.
  const ScanEvidencePanel({
    super.key,
    required this.scanner,
    required this.catalog,
  });

  /// The coordinator whose phase, last accepted, latest and recent scans are
  /// shown.
  final ScanCoordinator scanner;

  /// The catalog the item names come from.
  final CatalogController catalog;

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
    subtitle: 'Evidence only • never a decision',
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
              ..._report(context, shown),
            ],
            if (latest != null) ...[
              const SizedBox(height: 10),
              Text(
                'TIMINGS • Scan #${latest.id}',
                key: const Key('scan-timings-label'),
                style: Theme.of(context).textTheme.titleSmall,
              ),
              ..._timings(latest, frequency),
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
                    _recentRow(report, frequency),
                    key: Key('scan-recent-${report.id}'),
                  ),
                ),
          ],
        );
      },
    ),
  );

  List<Widget> _phase(ScanPhase phase) => switch (phase) {
    ScanPhase.idle => const [],
    ScanPhase.targeted => const [
      Text('Scan running: targeted', key: Key('scan-phase')),
      SizedBox(height: 8),
    ],
    ScanPhase.fallback => const [
      Text('Fallback underway', key: Key('scan-phase')),
      SizedBox(height: 8),
    ],
  };

  List<Widget> _report(BuildContext context, ScanReport report) {
    final entry = shownEvidence(report);
    final match = switch (report.end) {
      ScanAccepted(:final outcome) => outcome.match,
      ScanRejected(:final outcome) => outcome?.match,
      ScanFailed() || ScanSuperseded() => null,
    };
    final bold = Theme.of(context).textTheme.titleSmall;
    return [
      Text('Scan #${report.id}', style: bold),
      Text(_endLabel(report.end), key: const Key('scan-end')),
      if (report.winningPass case final ScanPass pass)
        Text('Pass: ${pass.name}', key: const Key('scan-pass')),
      ..._outcome(report.end, match),
      if (entry != null)
        ..._entry(entry)
      else if (shownBestMarkerScore(report) case final double score)
        ..._noEntry(score),
    ];
  }

  /// The note for [report], a later scan that was not accepted: its reason or
  /// failure, and when present its OCR text, marker score and best candidate.
  List<Widget> _note(BuildContext context, ScanReport report) {
    final entry = shownEvidence(report);
    return [
      Text(
        'Last scan not accepted',
        key: const Key('scan-note'),
        style: Theme.of(context).textTheme.titleSmall,
      ),
      Text('Scan #${report.id}'),
      ...switch (report.end) {
        ScanRejected(:final reason, :final outcome) => [
          Text('Reason: ${reason.name}', key: const Key('scan-note-reason')),
          if (entry != null) ...[
            Text(
              'Marker score ${_score(entry.markerScore)}',
              key: const Key('scan-note-marker'),
            ),
            Text(
              'OCR text: ${entry.text.isEmpty ? '(empty)' : entry.text}',
              key: const Key('scan-note-text'),
            ),
          ],
          ..._candidates(outcome?.match, accepted: false, prefix: 'scan-note'),
        ],
        ScanFailed(:final failure) => [
          Text(
            'Failure: ${failure.code.name}',
            key: const Key('scan-note-reason'),
          ),
          const Text('No candidate'),
        ],
        ScanAccepted() || ScanSuperseded() => const <Widget>[],
      },
      const Divider(height: 24),
    ];
  }

  List<Widget> _outcome(ScanEnd end, TitleMatch? match) => switch (end) {
    ScanAccepted(:final itemId) => [
      Text('Item: ${_itemLabel(itemId)}', key: const Key('scan-item')),
      ..._candidates(match, accepted: true),
    ],
    ScanRejected(:final reason, :final fallbackFailure) => [
      Text('Reason: ${reason.name}', key: const Key('scan-reason')),
      if (fallbackFailure case final ScanFailure failure)
        Text(
          'Fallback failure: ${failure.code.name}',
          key: const Key('scan-fallback-failure'),
        ),
      ..._candidates(match, accepted: false),
    ],
    ScanFailed(:final failure) => [
      Text('Failure: ${failure.code.name}', key: const Key('scan-reason')),
      Text(failure.message, key: const Key('scan-failure-message')),
      const Text('No candidate'),
    ],
    ScanSuperseded() => const [],
  };

  List<Widget> _candidates(
    TitleMatch? match, {
    required bool accepted,
    String prefix = 'scan',
  }) {
    final bestId = match?.bestId;
    if (match == null || bestId == null) {
      return accepted ? const [] : const [Text('No candidate')];
    }
    return [
      Text(
        accepted
            ? 'Best: ${_itemLabel(bestId)} ${_score(match.bestScore)}'
            : 'Best candidate (not accepted): ${_itemLabel(bestId)} '
                  '${_score(match.bestScore)}',
        key: Key('$prefix-best'),
      ),
      if (match.runnerUpId case final String runnerUp)
        Text(
          'Runner-up: ${_itemLabel(runnerUp)} ${_score(match.runnerUpScore)}',
          key: Key('$prefix-runner-up'),
        ),
      Text('Margin ${_score(match.margin)}', key: Key('$prefix-margin')),
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

  String _recentRow(ScanReport report, int? frequency) {
    final subject = switch (report.end) {
      ScanAccepted(:final itemId) => _itemName(itemId),
      ScanRejected(:final reason) => reason.name,
      ScanFailed(:final failure) => failure.code.name,
      ScanSuperseded() => '',
    };
    final published = report.timeline.published;
    final total = published == null || frequency == null
        ? 'no total'
        : _ms(report.timeline.msFromTrigger(published, frequency));
    final via = report.byHotkey ? ' · hotkey' : '';
    return '#${report.id} ${_endLabel(report.end)} · $subject · $total$via';
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
