import 'package:flutter/material.dart';

import '../application/app_services.dart';
import '../data/database.dart';
import '../domain/import_preview.dart';
import 'labels.dart';
import 'ember/ember_tokens.dart';
import 'ember/theme_access.dart';
import 'settings/settings_row.dart';

Future<void> showLegacyImport(BuildContext context, AppServices services) =>
    showDialog<void>(
      context: context,
      builder: (context) => ImportDialog(services: services),
    );

class ImportDialog extends StatefulWidget {
  const ImportDialog({super.key, required this.services, this.reload});
  final AppServices services;

  /// Reloads the app after a committed import. Defaults to
  /// [AppServices.reloadAfterImport]; tests inject a failing one.
  final Future<void> Function()? reload;
  @override
  State<ImportDialog> createState() => _ImportDialogState();
}

class _ImportDialogState extends State<ImportDialog> {
  final settingsPath = TextEditingController();
  final historyPath = TextEditingController();
  ImportPreview? preview;
  String? error;
  bool busy = false, replace = false, imported = false;

  /// Whether the file fingerprint and the per-record lines show. Collapsed
  /// again whenever a preview is read.
  bool detailsExpanded = false;
  @override
  void dispose() {
    settingsPath.dispose();
    historyPath.dispose();
    super.dispose();
  }

  Future<void> readPreview() async {
    setState(() {
      busy = true;
      error = null;
      preview = null;
      imported = false;
      detailsExpanded = false;
    });
    try {
      final result = await widget.services.importer.previewFiles(
        settingsPath: settingsPath.text.trim(),
        historyPath: historyPath.text.trim(),
      );
      if (mounted) setState(() => preview = result);
    } on FormatException catch (failure) {
      if (mounted) {
        setState(() => error = '${failure.message} Nothing was changed.');
      }
    } catch (_) {
      if (mounted) {
        setState(
          () => error = 'That file could not be read. Nothing was changed.',
        );
      }
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> commit() async {
    final candidate = preview;
    if (candidate == null || candidate.alreadyImported) return;
    setState(() {
      busy = true;
      error = null;
    });
    try {
      try {
        await widget.services.importer.commit(
          candidate,
          replaceExisting: replace,
        );
      } catch (failure) {
        if (mounted) {
          setState(
            () => error = switch (failure) {
              ImportAlreadyCommitted() =>
                'These files were already imported. Nothing was changed.',
              _ => 'The import could not be saved. Nothing was changed.',
            },
          );
        }
        return;
      }
      // The import is saved from here on, so a failed reload must not say
      // that nothing changed.
      try {
        await (widget.reload ?? widget.services.reloadAfterImport)();
      } catch (_) {
        if (mounted) {
          setState(() {
            preview = null;
            error =
                'The import was saved, but Blackgrid could not reload it. '
                'Restart Blackgrid to see the imported data.';
          });
        }
        return;
      }
      if (mounted) {
        setState(() {
          imported = true;
          preview = null;
        });
      }
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  /// The rows of the dialog body, each built only when the list scrolls to it,
  /// so a preview with many records builds nothing for its detail lines until
  /// Details is open and they come into view.
  List<WidgetBuilder> _rows(BuildContext context) {
    final ember = context.ember;
    final secondary = EmberType.label.copyWith(color: ember.inkSecondary);
    final candidate = preview;
    return [
      (_) => Text(
        'Enter the paths of the files you want to import. Blackgrid only reads them and never changes them. It does not look for files on its own and does not import tokens.',
        style: secondary,
      ),
      (_) => const SizedBox(height: EmberSpace.md),
      (_) => TextField(
        controller: settingsPath,
        enabled: !busy,
        onChanged: (_) => setState(() => preview = null),
        decoration: const InputDecoration(
          labelText: 'Settings file path (optional)',
        ),
      ),
      (_) => const SizedBox(height: EmberSpace.md),
      (_) => TextField(
        controller: historyPath,
        enabled: !busy,
        onChanged: (_) => setState(() => preview = null),
        decoration: const InputDecoration(
          labelText: 'History file path (optional)',
        ),
      ),
      (_) => const SizedBox(height: EmberSpace.md),
      (_) => Align(
        alignment: Alignment.centerLeft,
        child: OutlinedButton.icon(
          onPressed: busy ? null : readPreview,
          icon: const Icon(Icons.preview_outlined),
          label: const Text('Read files and preview'),
        ),
      ),
      (_) => const SizedBox(height: EmberSpace.md),
      if (error != null)
        (_) =>
            Text(error!, style: EmberType.body.copyWith(color: ember.errInk)),
      if (imported)
        (_) => Text(
          'Import finished; your files were not changed',
          style: EmberType.body.copyWith(color: context.blackgrid.okInk),
        ),
      if (candidate != null) ...[
        (_) => Text(
          candidate.alreadyImported
              ? 'These files were already imported.'
              : '${candidate.accounting.length} records found • ${candidate.pins.length} pins • ${candidate.winningActivity.length} history entries to keep',
          style: EmberType.uiHeading.copyWith(color: ember.ink),
        ),
        (_) => const SizedBox(height: EmberSpace.sm),
        if (candidate.settings != null)
          (_) => Text(
            'Settings: ${modeLabel(candidate.settings!.mode)} • ${mapLabel(candidate.settings!.selectedMap)} • remember marker filters: ${candidate.settings!.saveMarkerFilters ? 'yes' : 'no'} • use Tracker progress: ${candidate.settings!.trackerEnabled ? 'yes' : 'no'}',
          ),
        for (final p in candidate.pins)
          (_) => Text('Pin ${p.mapId}/${p.id} at (${p.x}, ${p.y})'),
        (_) => const SizedBox(height: EmberSpace.sm),
        (_) => Text(
          'Left out: ${candidate.exclusions.isEmpty ? 'nothing' : candidate.exclusions.join(', ')}',
        ),
        (_) => Text(
          'Never imported: tokens, prices, item data, progress, corrections, found-in-raid choices, accepted scans, images, screenshot, overlay, hotkey and game log settings.',
          style: secondary,
        ),
        (_) => SettingsRow.toggle(
          name: 'Replace entries that already exist here',
          explanation: 'Off by default: entries you already have are kept.',
          value: replace,
          enabled: !(busy || candidate.alreadyImported),
          onChanged: (value) => setState(() => replace = value),
        ),
        (_) => Text(
          'When the files hold the same entry twice, the newest one is used.',
          style: EmberType.label.copyWith(color: ember.inkTertiary),
        ),
        (_) => Align(
          alignment: Alignment.centerLeft,
          child: TextButton.icon(
            key: const Key('import-details-toggle'),
            onPressed: () => setState(() => detailsExpanded = !detailsExpanded),
            icon: Icon(
              detailsExpanded ? Icons.expand_less : Icons.expand_more,
              size: EmberSize.icon,
            ),
            label: const Text('Details'),
          ),
        ),
        if (detailsExpanded) ...[
          (_) => SelectableText(
            'File fingerprint: ${candidate.digest}',
            style: secondary,
          ),
          for (final row in candidate.accounting)
            (_) => Padding(
              padding: const EdgeInsets.only(top: EmberSpace.sm),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '${row.kind} #${row.inputOrder} • ${row.key} • ${row.disposition}',
                    style: secondary,
                  ),
                  Text(
                    row.reason,
                    style: EmberType.label.copyWith(color: ember.inkTertiary),
                  ),
                ],
              ),
            ),
        ],
      ],
    ];
  }

  @override
  Widget build(BuildContext context) {
    final rows = _rows(context);
    return AlertDialog(
      title: const Text('Import saved settings and history'),
      content: SizedBox(
        width: 720,
        height: MediaQuery.sizeOf(context).height * .68,
        child: ListView.builder(
          itemCount: rows.length,
          itemBuilder: (context, index) => rows[index](context),
        ),
      ),
      actions: _actions(),
    );
  }

  List<Widget> _actions() => [
    TextButton(
      onPressed: busy ? null : () => Navigator.pop(context),
      child: const Text('Close'),
    ),
    FilledButton(
      onPressed: busy || preview == null || preview!.alreadyImported
          ? null
          : commit,
      child: Text(busy ? 'Working…' : 'Import now'),
    ),
  ];
}
