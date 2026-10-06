import 'package:flutter/material.dart';

import '../application/app_services.dart';
import '../domain/import_preview.dart';
import 'theme.dart';

Future<void> showLegacyImport(BuildContext context, AppServices services) =>
    showDialog<void>(
      context: context,
      builder: (context) => ImportDialog(services: services),
    );

class ImportDialog extends StatefulWidget {
  const ImportDialog({super.key, required this.services});
  final AppServices services;
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
        setState(() => error = '${failure.message} No destination changes.');
      }
    } catch (_) {
      if (mounted) {
        setState(
          () => error =
              'Selected file could not be read. No destination changes.',
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
      await widget.services.importer.commit(
        candidate,
        replaceExisting: replace,
      );
      await widget.services.reloadAfterImport();
      if (mounted) {
        setState(() {
          imported = true;
          preview = null;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(
          () => error = 'Import failed or source was already imported. No success was published.',
        );
      }
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('Explicit one-time legacy import'),
    content: SizedBox(
      width: 720,
      height: MediaQuery.sizeOf(context).height * .68,
      child: ListView(
        children: [
          const Text(
            'Enter only the local files you choose to import. Files are read-only and never modified. No automatic discovery or credential import.',
            style: TextStyle(color: GridColors.muted),
          ),
          const SizedBox(height: 14),
          TextField(
            controller: settingsPath,
            enabled: !busy,
            onChanged: (_) => setState(() => preview = null),
            decoration: const InputDecoration(
              labelText: 'Selected settings JSON path • optional',
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: historyPath,
            enabled: !busy,
            onChanged: (_) => setState(() => preview = null),
            decoration: const InputDecoration(
              labelText: 'Selected history JSON path • optional',
            ),
          ),
          const SizedBox(height: 12),
          Align(
            alignment: Alignment.centerLeft,
            child: OutlinedButton.icon(
              onPressed: busy ? null : readPreview,
              icon: const Icon(Icons.preview_outlined),
              label: const Text('Read and preview selected files'),
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
              'Import committed atomically. Sources were unchanged.',
              style: TextStyle(color: GridColors.green),
            ),
          if (preview case final candidate?) ...[
            Text(
              candidate.alreadyImported
                  ? 'These exact source bytes were already imported.'
                  : '${candidate.accounting.length} supported records accounted for • ${candidate.pins.length} pins • ${candidate.winningActivity.length} activity winners',
            ),
            const SizedBox(height: 8),
            SelectableText(
              'Source digest: ${candidate.digest}',
              style: Theme.of(context).textTheme.bodySmall,
            ),
            if (candidate.settings != null)
              Text(
                'Preferences: ${modeLabel(candidate.settings!.mode)} • ${mapLabel(candidate.settings!.selectedMap)} • saved filters ${candidate.settings!.saveMarkerFilters} • Tracker preference ${candidate.settings!.trackerEnabled}',
              ),
            ...candidate.pins.map(
              (p) => Text(
                'Pin ${p.mapId}/${p.id}: (${p.x}, ${p.y}) • ${p.frame} revision ${p.frameRevision}',
              ),
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
              'Excluded fields: ${candidate.exclusions.isEmpty ? 'None supplied' : candidate.exclusions.join(', ')}',
            ),
            const Text(
              'Always excluded: credentials, prices/catalog/progress, corrections/FIR, accepted scans, images/OCR, screenshot/overlay/hotkey/game-log settings.',
              style: TextStyle(color: GridColors.muted),
            ),
            CheckboxListTile(
              contentPadding: EdgeInsets.zero,
              value: replace,
              onChanged: busy || candidate.alreadyImported
                  ? null
                  : (value) => setState(() => replace = value ?? false),
              title: const Text(
                'Explicitly replace conflicting destination records',
              ),
              subtitle: const Text(
                'Default: preserve existing destination values. Source collision winners remain deterministic.',
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
        child: Text(busy ? 'Working…' : 'Accept preview and import'),
      ),
    ],
  );
}
