import 'package:flutter/material.dart';

import '../application/app_services.dart';
import '../domain/catalog.dart';
import 'theme.dart';

Future<void> showSettings(BuildContext context, AppServices services) =>
    showDialog<void>(
      context: context,
      builder: (context) => SettingsDialog(services: services),
    );

class SettingsDialog extends StatefulWidget {
  const SettingsDialog({super.key, required this.services});
  final AppServices services;
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
          () => message =
              'Protected credential operation failed. No plaintext fallback.',
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
        title: const Text('Blackgrid configuration'),
        content: SizedBox(
          width: 560,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Manual mode is used when configured Map logs cannot establish a mode. Blackgrid reads saved files only and never interacts with the game.',
                  style: TextStyle(color: GridColors.muted),
                ),
                const SizedBox(height: 18),
                DropdownButtonFormField<GameMode>(
                  key: ValueKey(services.catalog.mode),
                  initialValue: services.catalog.mode,
                  decoration: const InputDecoration(
                    labelText: 'Live game mode',
                  ),
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
                  label: const Text('Refresh complete catalog'),
                ),
                Text(
                  'Catalog: ${services.catalog.status.name}',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
                const Divider(height: 28),
                Text(
                  'Map file inputs',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: gameLogs,
                  enabled: !services.settings.busy,
                  decoration: const InputDecoration(
                    labelText: 'Game log directory',
                    helperText: "Leave empty to auto-detect the game's Logs folder. Monitoring is independent of Follow logs.",
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: screenshots,
                  enabled: !services.settings.busy,
                  decoration: const InputDecoration(
                    labelText: 'Screenshot directory',
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
                        ? 'Saving map inputs…'
                        : 'Save map inputs',
                  ),
                ),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Follow logs'),
                  subtitle: const Text(
                    'Use the detected map when available. Manual map selection turns this off; configured logs continue to be monitored.',
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
                  title: const Text('Enable read-only Tracker integration'),
                  subtitle: const Text(
                    'GET /token and /progress only. GP permission required.',
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
                  'Protected credential: ${services.progress.hasCredential ? 'Present for ${modeLabel(services.progress.mode)}' : 'Not configured'}',
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: token,
                  obscureText: true,
                  autocorrect: false,
                  enableSuggestions: false,
                  decoration: const InputDecoration(
                    labelText: 'Tracker token • active mode only',
                    helperText: 'PVP_, PVE_ or SZN_ prefix. Never imported or stored in SQLite.',
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
                              'Current-user DPAPI credential saved.',
                            ),
                      child: const Text('Save protected token'),
                    ),
                    OutlinedButton(
                      onPressed:
                          busy || !known || !services.progress.hasCredential
                          ? null
                          : () => action(
                              services.progress.removeCredential,
                              'Protected credential removed; progress authority cleared.',
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
                              'Progress request completed.',
                            ),
                      child: const Text('Refresh progress'),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Text(
                  message ??
                      services.progress.error ??
                      'Progress: ${services.progress.status.name}',
                ),
                const SizedBox(height: 10),
                const Text(
                  'Credentials use Windows current-user DPAPI in LocalAppData/Blackgrid/credentials. Progress and account identity are session memory only; restart requires new authorization.',
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
