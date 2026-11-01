import 'package:flutter/material.dart';

import '../application/app_services.dart';
import '../data/database.dart';
import '../domain/import_preview.dart';
import 'theme.dart';

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

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('Import saved settings and history'),
    content: SizedBox(
      width: 720,
      height: MediaQuery.sizeOf(context).height * .68,
      child: ListView(
        children: [
          const Text(
            'Enter the paths of the files you want to import. Blackgrid only reads them and never changes them. It does not look for files on its own and does not import tokens.',
            style: TextStyle(color: GridColors.muted),
          ),
          const SizedBox(height: 14),
          TextField(
            controller: settingsPath,
            enabled: !busy,
            onChanged: (_) => setState(() => preview = null),
            decoration: const InputDecoration(
              labelText: 'Settings file path (optional)',
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: historyPath,
            enabled: !busy,
            onChanged: (_) => setState(() => preview = null),
            decoration: const InputDecoration(
              labelText: 'History file path (optional)',
            ),
          ),
          const SizedBox(height: 12),
          Align(
            alignment: Alignment.centerLeft,
            child: OutlinedButton.icon(
              onPressed: busy ? null : readPreview,
              icon: const Icon(Icons.preview_outlined),
              label: const Text('Read files and preview'),
            ),
          ),
          const SizedBox(height: 12),
          if (error != null)
            Text(
              error!,
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
          if (imported)
            const Text(
              'Import finished; your files were not changed',
              style: TextStyle(color: GridColors.green),
            ),
          if (preview case final candidate?) ...[
            Text(
              candidate.alreadyImported
                  ? 'These files were already imported.'
                  : '${candidate.accounting.length} records found • ${candidate.pins.length} pins • ${candidate.winningActivity.length} history entries to keep',
            ),
            const SizedBox(height: 8),
            SelectableText(
              'File fingerprint: ${candidate.digest}',
              style: Theme.of(context).textTheme.bodySmall,
            ),
            if (candidate.settings != null)
              Text(
                'Settings: ${modeLabel(candidate.settings!.mode)} • ${mapLabel(candidate.settings!.selectedMap)} • remember marker filters: ${candidate.settings!.saveMarkerFilters ? 'yes' : 'no'} • use Tracker progress: ${candidate.settings!.trackerEnabled ? 'yes' : 'no'}',
              ),
            ...candidate.pins.map(
              (p) => Text('Pin ${p.mapId}/${p.id} at (${p.x}, ${p.y})'),
            ),
            const Divider(height: 24),
            ...candidate.accounting.map(
              (row) => Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '${row.kind} #${row.inputOrder} • ${row.key} • ${row.disposition}',
                      style: const TextStyle(color: GridColors.gold),
                    ),
                    Text(
                      row.reason,
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ],
                ),
              ),
            ),
            const Divider(height: 24),
            Text(
              'Left out: ${candidate.exclusions.isEmpty ? 'nothing' : candidate.exclusions.join(', ')}',
            ),
            const Text(
              'Never imported: tokens, prices, item data, progress, corrections, found-in-raid choices, accepted scans, images, screenshot, overlay, hotkey and game log settings.',
              style: TextStyle(color: GridColors.muted),
            ),
            CheckboxListTile(
              contentPadding: EdgeInsets.zero,
              value: replace,
              onChanged: busy || candidate.alreadyImported
                  ? null
                  : (value) => setState(() => replace = value ?? false),
              title: const Text('Replace entries that already exist here'),
              subtitle: const Text(
                'Off by default: entries you already have are kept. When the files hold the same entry twice, the newest one is used.',
              ),
            ),
          ],
        ],
      ),
    ),
    actions: [
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
    ],
  );
}
