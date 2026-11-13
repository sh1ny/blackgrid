import 'dart:async';

import 'package:flutter/material.dart';

import '../../application/manual_progress_controller.dart';
import '../../application/task_log_progress_controller.dart';
import '../../domain/catalog.dart';
import '../../domain/progress_wipe_store.dart';
import '../ember/ember_tokens.dart';
import '../ember/theme_access.dart';
import '../labels.dart';
import 'your_progress_panel.dart';

const _modes = [GameMode.pvp, GameMode.pve, GameMode.seasonal];

/// The active local wipes, log-reading actions and latest run status.
class LocalProgressSettings extends StatefulWidget {
  /// Creates the settings over [controller], using [clock] for picker dates.
  const LocalProgressSettings({
    super.key,
    required this.controller,
    this.clock,
    this.manualProgress,
  });

  /// The source of wipe and log-reading state and actions.
  final TaskLogProgressSource controller;

  /// The effective mode's manual progress, when available.
  final ManualProgressController? manualProgress;

  /// The current local time, or `null` to use the system clock.
  final DateTime Function()? clock;

  @override
  State<LocalProgressSettings> createState() => _LocalProgressSettingsState();
}

class _LocalProgressSettingsState extends State<LocalProgressSettings> {
  final _replayDates = <GameMode, (String?, DateTime)>{};
  final _newWipeDates = <GameMode, DateTime>{};

  DateTime? _replayDate(GameMode mode, ProgressWipe? wipe) {
    final selection = _replayDates[mode];
    return selection != null && selection.$1 == wipe?.cycleId
        ? selection.$2
        : wipe?.startDate;
  }

  Future<void> _chooseDate(GameMode mode, {required bool replay}) async {
    final wipe = widget.controller.wipes[mode];
    final now = (widget.clock ?? DateTime.now)();
    final today = DateTime(now.year, now.month, now.day);
    final oldest = widget.controller.oldestFolderDate;
    var first = oldest == null
        ? DateTime(2017)
        : DateTime(oldest.year, oldest.month, oldest.day);
    if (first.isAfter(today)) first = today;
    final selected = replay ? _replayDate(mode, wipe) : _newWipeDates[mode];
    var initial = selected ?? today;
    initial = DateTime(initial.year, initial.month, initial.day);
    if (initial.isBefore(first)) initial = first;
    if (initial.isAfter(today)) initial = today;
    final date = await showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: first,
      lastDate: today,
    );
    if (!mounted || date == null) return;
    setState(() {
      if (replay) {
        _replayDates[mode] = (wipe?.cycleId, date);
      } else {
        _newWipeDates[mode] = date;
      }
    });
  }

  Future<void> _confirmNewWipe(GameMode mode, DateTime date) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Start a new wipe?'),
        content: Text(
          'Start a new ${modeLabel(mode)} wipe on ${_date(date)}? '
          'Your old wipe history will be kept.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Start a new wipe'),
          ),
        ],
      ),
    );
    if (!mounted || confirmed != true) return;
    // The controller admits the request against the current raid and run state.
    await widget.controller.startNewWipe(mode, date);
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: widget.controller,
    builder: (context, _) {
      final controller = widget.controller;
      final ember = context.ember;
      final note = EmberType.label.copyWith(color: ember.inkTertiary);
      final error = EmberType.label.copyWith(color: ember.errInk);
      final reason =
          controller.disabledReason ??
          (controller.running ? 'Another log read is running' : null);
      final result = controller.lastResult;
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (final mode in _modes) _modeRow(context, mode, reason),
          Padding(
            padding: const EdgeInsets.only(top: EmberSpace.md),
            child: Text(
              'Closing Blackgrid stops replay. To finish, replay again from the same date.',
              style: note,
            ),
          ),
          if (controller.running)
            Padding(
              padding: const EdgeInsets.only(top: EmberSpace.md),
              child: Text(
                controller.currentReadFolder == null
                    ? 'Reading game logs…'
                    : 'Reading folder: ${controller.currentReadFolder}',
                style: note,
              ),
            )
          else if (result != null)
            Padding(
              padding: const EdgeInsets.only(top: EmberSpace.md),
              child: Text(_resultText(result), style: note),
            ),
          if (controller.error case final message?)
            Padding(
              padding: const EdgeInsets.only(top: EmberSpace.sm),
              child: Text(message, style: error),
            ),
          if (widget.manualProgress case final manualProgress?)
            YourProgressPanel(controller: manualProgress),
        ],
      );
    },
  );

  Widget _modeRow(BuildContext context, GameMode mode, String? reason) {
    final controller = widget.controller;
    final wipe = controller.wipes[mode];
    final unavailable = controller.unavailableModes.contains(mode);
    final replayDate = _replayDate(mode, wipe);
    final newWipeDate = _newWipeDates[mode];
    final ember = context.ember;
    final note = EmberType.label.copyWith(color: ember.inkTertiary);
    final status = unavailable
        ? 'Wipe unavailable'
        : wipe == null
        ? 'No wipe yet'
        : 'Started ${_date(wipe.startDate)} · Last folder: '
              '${wipe.lastFolder ?? 'None read yet'}';
    return Container(
      key: Key('local-progress-${mode.name}'),
      padding: const EdgeInsets.symmetric(vertical: EmberSpace.md),
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: ember.hairline)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            modeLabel(mode),
            style: EmberType.body.copyWith(color: ember.ink),
          ),
          const SizedBox(height: EmberSpace.sm),
          Text(status, style: note),
          if (reason != null) ...[
            const SizedBox(height: EmberSpace.sm),
            Text(reason, style: note),
          ],
          const SizedBox(height: EmberSpace.sm),
          Wrap(
            spacing: EmberSpace.sm,
            runSpacing: EmberSpace.sm,
            children: [
              OutlinedButton(
                key: Key('replay-date-${mode.name}'),
                onPressed: () => _chooseDate(mode, replay: true),
                child: Text(
                  replayDate == null
                      ? 'Replay date: Choose date'
                      : 'Replay date: ${_date(replayDate)}',
                ),
              ),
              OutlinedButton(
                key: Key('replay-${mode.name}'),
                onPressed: reason == null && !unavailable && replayDate != null
                    ? () => unawaited(controller.replay(mode, replayDate))
                    : null,
                child: const Text('Replay game logs'),
              ),
              OutlinedButton(
                key: Key('new-wipe-date-${mode.name}'),
                onPressed: () => _chooseDate(mode, replay: false),
                child: Text(
                  newWipeDate == null
                      ? 'New wipe date: Choose date'
                      : 'New wipe date: ${_date(newWipeDate)}',
                ),
              ),
              OutlinedButton(
                key: Key('new-wipe-${mode.name}'),
                onPressed: reason == null && newWipeDate != null
                    ? () => unawaited(_confirmNewWipe(mode, newWipeDate))
                    : null,
                child: const Text('Start a new wipe'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

String _date(DateTime date) =>
    '${date.year.toString().padLeft(4, '0')}-'
    '${date.month.toString().padLeft(2, '0')}-'
    '${date.day.toString().padLeft(2, '0')}';

String _resultText(TaskLogRunResult result) {
  final kind = switch (result.kind) {
    TaskLogRunKind.catchUp => 'Catch-up',
    TaskLogRunKind.replay => 'Replay',
    TaskLogRunKind.newWipe => 'New wipe',
  };
  final modes = _modes.where(result.modes.contains).map(modeLabel).join(', ');
  final finished = result.finishedAt.toLocal();
  final time =
      '${_date(finished)} '
      '${finished.hour.toString().padLeft(2, '0')}:'
      '${finished.minute.toString().padLeft(2, '0')}';
  return '$kind · $modes · $time\n'
      '${result.foldersRead} folders read · ${result.eventsRecorded} events recorded\n'
      'Skipped: ${result.skippedNoMode} no mode · '
      '${result.rejectedRecords} rejected · '
      '${result.identityOverBudget} record IDs too long · '
      '${result.conflictingRecords} conflicting records\n'
      '${result.unreadableFolders} unreadable folders'
      '${result.stoppedByRaid ? '\nStopped by a raid' : ''}'
      '${result.lastStoredFolder == null ? '' : '\nLast stored folder: ${result.lastStoredFolder}'}'
      '${result.failure == null ? '' : '\nFailed: ${result.failure}'}'
      '${result.retryFrom == null ? '' : '\nReplay again from ${_date(result.retryFrom!)}'}';
}
