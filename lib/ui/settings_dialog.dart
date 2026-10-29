import 'package:flutter/material.dart';

import '../application/app_services.dart';
import '../application/app_version.dart' as app_version;
import '../domain/catalog.dart';
import 'labels.dart';
import 'theme.dart';

Future<void> showSettings(BuildContext context, AppServices services) =>
    showDialog<void>(
      context: context,
      builder: (context) => SettingsDialog(services: services),
    );

class SettingsDialog extends StatefulWidget {
  const SettingsDialog({
    super.key,
    required this.services,
    this.version = app_version.appVersion,
  });
  final AppServices services;
  final String version;
  @override
  State<SettingsDialog> createState() => _SettingsDialogState();
}

class _SettingsDialogState extends State<SettingsDialog> {
  final token = TextEditingController();
  late final gameLogs = TextEditingController(
    text: widget.services.settings.settings.gameLogDirectory,
  );
  late final screenshots = TextEditingController(
    text: widget.services.settings.settings.screenshotDirectory,
  );
  bool busy = false;
  String? message;
  @override
  void dispose() {
    token.clear();
    token.dispose();
    gameLogs.dispose();
    screenshots.dispose();
    super.dispose();
  }

  Future<void> action(Future<void> Function() work, String success) async {
    setState(() {
      busy = true;
      message = null;
    });
    try {
      await work();
      if (!mounted) return;
      token.clear();
      setState(() => message = widget.services.progress.error ?? success);
    } catch (_) {
      if (mounted) {
        setState(
          () => message = 'Tracker token operation failed. Nothing was stored as plain text.',
        );
      }
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: Listenable.merge([
      widget.services.settings,
      widget.services.catalog,
      widget.services.progress,
    ]),
    builder: (context, _) {
      final services = widget.services;
      final known = services.catalog.mode != GameMode.unknown;
      return AlertDialog(
        title: const Text('Settings'),
        content: SizedBox(
          width: 560,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Version ${widget.version}',
                  style: const TextStyle(color: GridColors.muted),
                ),
                const SizedBox(height: 8),
                const Text(
                  'The game mode below is used when the game logs do not say which mode you are playing. Blackgrid only reads saved files and never interacts with the game.',
                  style: TextStyle(color: GridColors.muted),
                ),
                const SizedBox(height: 18),
                DropdownButtonFormField<GameMode>(
                  key: ValueKey(services.catalog.mode),
                  initialValue: services.catalog.mode,
                  decoration: const InputDecoration(labelText: 'Game mode'),
                  items: GameMode.values
                      .map(
                        (m) => DropdownMenuItem(
                          value: m,
                          child: Text(modeLabel(m)),
                        ),
                      )
                      .toList(),
                  onChanged: busy || services.settings.busy
                      ? null
                      : (m) {
                          if (m != null) services.setMode(m);
                        },
                ),
                const SizedBox(height: 14),
                OutlinedButton.icon(
                  onPressed: known && !services.catalog.loading
                      ? services.catalog.refresh
                      : null,
                  icon: const Icon(Icons.refresh),
                  label: const Text('Refresh item data'),
                ),
                Text(
                  'Item data: ${catalogStatusLabel(services.catalog.status)}',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
                const Divider(height: 28),
                Text(
                  'Map files',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: gameLogs,
                  enabled: !services.settings.busy,
                  decoration: const InputDecoration(
                    labelText: 'Game log folder',
                    helperText: "Leave empty to find the game's Logs folder automatically. Logs are watched even when Follow logs is off.",
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: screenshots,
                  enabled: !services.settings.busy,
                  decoration: const InputDecoration(
                    labelText: 'Screenshot folder',
                    helperText: r'Leave empty to use Documents\Escape from Tarkov\Screenshots.',
                  ),
                ),
                const SizedBox(height: 12),
                FilledButton(
                  onPressed: services.settings.busy
                      ? null
                      : () => services.settings.setMapInputs(
                          gameLogDirectory: gameLogs.text.trim(),
                          screenshotDirectory: screenshots.text.trim(),
                        ),
                  child: Text(
                    services.settings.busy
                        ? 'Saving map files…'
                        : 'Save map files',
                  ),
                ),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Follow logs'),
                  subtitle: const Text(
                    'Use the map found in the game logs when there is one. Choosing a map yourself turns this off; the logs are still watched.',
                  ),
                  value: services.settings.settings.followGameLogs,
                  onChanged: services.settings.busy
                      ? null
                      : (value) => services.settings.setMapInputs(
                          followGameLogs: value,
                        ),
                ),
                const Divider(height: 28),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Use Tracker progress'),
                  subtitle: const Text(
                    'Blackgrid only reads your progress. Your token needs the GP permission.',
                  ),
                  value: services.settings.settings.trackerEnabled,
                  onChanged: busy
                      ? null
                      : (value) async {
                          final success = await services.settings.save(
                            services.settings.settings.copyWith(
                              trackerEnabled: value,
                            ),
                          );
                          if (success && !value) {
                            await services.progress.setMode(
                              services.catalog.mode,
                            );
                          }
                        },
                ),
                const SizedBox(height: 12),
                Text(
                  'Tracker token: ${services.progress.hasCredential ? 'saved for ${modeLabel(services.progress.mode)}' : 'not saved'}',
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: token,
                  obscureText: true,
                  autocorrect: false,
                  enableSuggestions: false,
                  decoration: const InputDecoration(
                    labelText: 'Tracker token (current game mode)',
                    helperText: 'Starts with PVP_, PVE_ or SZN_. It is never imported or kept in the database.',
                  ),
                ),
                const SizedBox(height: 12),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    FilledButton(
                      onPressed: busy || !known
                          ? null
                          : () => action(
                              () => services.progress.saveCredential(
                                token.text.trim(),
                              ),
                              'Tracker token saved',
                            ),
                      child: const Text('Save token'),
                    ),
                    OutlinedButton(
                      onPressed:
                          busy || !known || !services.progress.hasCredential
                          ? null
                          : () => action(
                              services.progress.removeCredential,
                              'Token removed',
                            ),
                      child: const Text('Remove token'),
                    ),
                    OutlinedButton(
                      onPressed:
                          busy ||
                              !services.progress.hasCredential ||
                              !services.settings.settings.trackerEnabled
                          ? null
                          : () => action(
                              services.progress.refresh,
                              'Progress refreshed',
                            ),
                      child: const Text('Refresh progress'),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Text(
                  message ??
                      services.progress.error ??
                      'Progress: ${progressStatusLabel(services.progress.status)}',
                ),
                const SizedBox(height: 10),
                const Text(
                  'Your Tracker token is stored encrypted for your Windows account. Your progress is kept only while Blackgrid is open, so refresh it after a restart.',
                  style: TextStyle(color: GridColors.muted),
                ),
                if (services.settings.error != null)
                  Text(
                    services.settings.error!,
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.error,
                    ),
                  ),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: busy ? null : () => Navigator.pop(context),
            child: const Text('Close'),
          ),
        ],
      );
    },
  );
}
