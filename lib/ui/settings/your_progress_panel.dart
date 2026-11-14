import 'dart:async';

import 'package:flutter/material.dart';

import '../../application/manual_progress_controller.dart';
import '../../domain/catalog.dart';
import '../../domain/local_progress.dart';
import '../ember/ember_tokens.dart';
import '../ember/theme_access.dart';
import '../labels.dart';

/// Player-facing names for the edition identifiers in the progress catalog.
const progressEditionNames = <String, String>{
  'standard': 'Standard',
  'left-behind': 'Left Behind',
  'prepare-for-escape': 'Prepare for Escape',
  'edge-of-darkness': 'Edge of Darkness',
  'unheard': 'The Unheard Edition',
};

/// The effective mode's manually editable local progress.
class YourProgressPanel extends StatefulWidget {
  /// Creates a panel backed by [controller].
  const YourProgressPanel({super.key, required this.controller});

  /// The shared projection and actions for local manual progress.
  final ManualProgressController controller;

  @override
  State<YourProgressPanel> createState() => _YourProgressPanelState();
}

class _YourProgressPanelState extends State<YourProgressPanel> {
  final _level = TextEditingController();
  final _search = TextEditingController();
  GameMode? _levelMode;
  ProgressValue? _levelValue;

  @override
  void initState() {
    super.initState();
    _attach(widget.controller);
  }

  void _attach(ManualProgressController controller) {
    controller.addListener(_onProgressChanged);
    _syncLevel();
    controller.attach();
  }

  void _detach(ManualProgressController controller) {
    controller.removeListener(_onProgressChanged);
    controller.detach();
  }

  void _syncLevel() {
    final controller = widget.controller;
    final value = controller.value(playerLevelTarget);
    if (_levelMode == controller.mode && _levelValue == value) return;
    _levelMode = controller.mode;
    _levelValue = value;
    _level.text = switch (value) {
      ProgressInteger(:final value) => '$value',
      _ => '',
    };
  }

  void _onProgressChanged() {
    _syncLevel();
    if (mounted) setState(() {});
  }

  @override
  void didUpdateWidget(covariant YourProgressPanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != widget.controller) {
      _detach(oldWidget.controller);
      _levelMode = null;
      _levelValue = null;
      _attach(widget.controller);
    }
  }

  @override
  void dispose() {
    _detach(widget.controller);
    _level.dispose();
    _search.dispose();
    super.dispose();
  }

  bool _enabled(ProgressTarget target) =>
      widget.controller.disabledReason == null &&
      !widget.controller.pending(target);

  @override
  Widget build(BuildContext context) {
    final controller = widget.controller;
    final ember = context.ember;
    final note = EmberType.label.copyWith(color: ember.inkTertiary);
    final heading = EmberType.body.copyWith(color: ember.ink);
    final mode = controller.mode;
    return Padding(
      padding: const EdgeInsets.only(top: EmberSpace.xl),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            mode == GameMode.unknown
                ? 'Your progress'
                : 'Your progress · ${modeLabel(mode)}',
            style: heading,
          ),
          const SizedBox(height: EmberSpace.sm),
          if (mode == GameMode.unknown)
            Text('Choose a game mode to enter your progress.', style: note)
          else ...[
            if (controller.disabledReason case final reason?)
              Text(reason, style: EmberType.label.copyWith(color: ember.errInk))
            else if (controller.loading)
              Text('Loading local progress…', style: note)
            else if (!controller.hasWipe)
              Text(
                'The first entry starts a wipe dated today, or the current '
                'game session’s date if it is earlier.',
                style: note,
              ),
            _levelRow(context),
            _factionRow(context),
            _editionRow(context),
            const SizedBox(height: EmberSpace.lg),
            Text('Trader loyalty', style: heading),
            if (controller.progressCatalog == null ||
                controller.progressCatalog!.traders == null)
              _catalogUnavailable(note)
            else
              for (final trader in controller.traders)
                _integerRow(
                  context,
                  id: 'trader-${trader.id}',
                  title: trader.name,
                  target: ProgressTarget(
                    kind: ProgressEntityKind.trader,
                    id: trader.id,
                    field: ProgressField.loyalty,
                  ),
                  options: {
                    for (final level in trader.levels!) level: '$level',
                  },
                  onChanged: (value) => controller.setLoyalty(trader.id, value),
                ),
            if (controller.progressCatalog?.traders?.any(
                  (trader) => trader.levels == null,
                ) ??
                false)
              _catalogUnavailable(note),
            const SizedBox(height: EmberSpace.lg),
            Text('Hideout stations', style: heading),
            if (controller.progressCatalog == null)
              _catalogUnavailable(note)
            else
              for (final station in controller.stations)
                _integerRow(
                  context,
                  id: 'station-${station.id}',
                  title: station.name,
                  target: ProgressTarget(
                    kind: ProgressEntityKind.station,
                    id: station.id,
                    field: ProgressField.level,
                  ),
                  options: {
                    0: 'Not built',
                    for (final level in station.levels)
                      if (level.level > 0) level.level: '${level.level}',
                  },
                  onChanged: (value) =>
                      controller.setStationLevel(station.id, value),
                ),
            const SizedBox(height: EmberSpace.lg),
            Text('Task search', style: heading),
            if (controller.progressCatalog == null)
              _catalogUnavailable(note)
            else ...[
              const SizedBox(height: EmberSpace.sm),
              TextField(
                key: const Key('progress-task-search'),
                controller: _search,
                decoration: const InputDecoration(
                  labelText: 'Search tasks',
                  hintText: 'Enter a task name',
                ),
                onChanged: (_) => setState(() {}),
              ),
              if (_search.text.trim().isNotEmpty) ...[
                if (controller.searchTasks(_search.text).isEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: EmberSpace.sm),
                    child: Text('No matching tasks.', style: note),
                  )
                else ...[
                  for (final task in controller.searchTasks(_search.text))
                    _taskRow(context, task.id, task.name),
                  if (controller.searchTruncated(_search.text))
                    Padding(
                      padding: const EdgeInsets.only(top: EmberSpace.sm),
                      child: Text(
                        'More tasks match; refine your search.',
                        style: note,
                      ),
                    ),
                ],
              ],
            ],
          ],
        ],
      ),
    );
  }

  Widget _catalogUnavailable(TextStyle style) => Padding(
    padding: const EdgeInsets.only(top: EmberSpace.sm),
    child: Text('Task data is not loaded yet.', style: style),
  );

  Widget _levelRow(BuildContext context) {
    final controller = widget.controller;
    final enabled = _enabled(playerLevelTarget);
    final value = controller.value(playerLevelTarget);
    return _row(
      context,
      id: 'level',
      title: 'Level',
      target: playerLevelTarget,
      controls: [
        SizedBox(
          width: 160,
          child: TextField(
            key: const Key('progress-level-input'),
            controller: _level,
            enabled: enabled,
            keyboardType: TextInputType.number,
            textInputAction: TextInputAction.done,
            decoration: const InputDecoration(
              labelText: 'Level',
              hintText: 'Unknown',
            ),
            onSubmitted: enabled
                ? (input) => unawaited(controller.setLevel(input))
                : null,
          ),
        ),
        OutlinedButton(
          onPressed: enabled
              ? () => unawaited(controller.setLevel(_level.text))
              : null,
          child: const Text('Set'),
        ),
        Text(
          value is ProgressInteger ? 'Current: ${value.value}' : 'Unknown',
          style: EmberType.label.copyWith(color: context.ember.inkTertiary),
        ),
      ],
    );
  }

  Widget _factionRow(BuildContext context) => _stringRow(
    context,
    id: 'faction',
    title: 'Faction',
    target: playerFactionTarget,
    options: const {'bear': 'BEAR', 'usec': 'USEC'},
    onChanged: widget.controller.setFaction,
  );

  Widget _editionRow(BuildContext context) => _stringRow(
    context,
    id: 'edition',
    title: 'Edition',
    target: playerEditionTarget,
    options: {
      for (final id in widget.controller.editions)
        id: progressEditionNames[id] ?? id,
    },
    onChanged: widget.controller.setEdition,
  );

  Widget _stringRow(
    BuildContext context, {
    required String id,
    required String title,
    required ProgressTarget target,
    required Map<String, String> options,
    required Future<void> Function(String) onChanged,
  }) {
    final value = widget.controller.value(target);
    final current = value is ProgressText && options.containsKey(value.value)
        ? value.value
        : null;
    return _row(
      context,
      id: id,
      title: title,
      target: target,
      controls: [
        DropdownButton<String>(
          key: Key('progress-control-$id'),
          value: current,
          hint: const Text('Unknown'),
          items: [
            for (final entry in options.entries)
              DropdownMenuItem(value: entry.key, child: Text(entry.value)),
          ],
          onChanged: _enabled(target)
              ? (value) {
                  if (value != null) unawaited(onChanged(value));
                }
              : null,
        ),
      ],
    );
  }

  Widget _integerRow(
    BuildContext context, {
    required String id,
    required String title,
    required ProgressTarget target,
    required Map<int, String> options,
    required Future<void> Function(int) onChanged,
  }) {
    final value = widget.controller.value(target);
    final current = value is ProgressInteger && options.containsKey(value.value)
        ? value.value
        : null;
    return _row(
      context,
      id: id,
      title: title,
      target: target,
      controls: [
        DropdownButton<int>(
          key: Key('progress-control-$id'),
          value: current,
          hint: const Text('Unknown'),
          items: [
            for (final entry in options.entries)
              DropdownMenuItem(value: entry.key, child: Text(entry.value)),
          ],
          onChanged: _enabled(target)
              ? (value) {
                  if (value != null) unawaited(onChanged(value));
                }
              : null,
        ),
      ],
    );
  }

  Widget _taskRow(BuildContext context, String id, String title) {
    final controller = widget.controller;
    final target = ProgressTarget(
      kind: ProgressEntityKind.task,
      id: id,
      field: ProgressField.state,
    );
    final value = controller.value(target);
    final current = value is ProgressTaskState ? value.value.name : null;
    return _row(
      context,
      id: 'task-$id',
      title: title,
      target: target,
      controls: [
        DropdownButton<String>(
          key: Key('progress-control-task-$id'),
          value: current,
          hint: const Text('Unknown'),
          items: const [
            DropdownMenuItem(value: 'unset', child: Text('Not started')),
            DropdownMenuItem(value: 'started', child: Text('Started')),
            DropdownMenuItem(value: 'failed', child: Text('Failed')),
            DropdownMenuItem(value: 'finished', child: Text('Finished')),
          ],
          onChanged: _enabled(target)
              ? (value) {
                  if (value == null) return;
                  final state = switch (value) {
                    'started' => ProgressTaskStatus.started,
                    'failed' => ProgressTaskStatus.failed,
                    'finished' => ProgressTaskStatus.finished,
                    _ => null,
                  };
                  unawaited(controller.setTaskState(id, state));
                }
              : null,
        ),
      ],
    );
  }

  Widget _row(
    BuildContext context, {
    required String id,
    required String title,
    required ProgressTarget target,
    required List<Widget> controls,
  }) {
    final controller = widget.controller;
    final enabled = _enabled(target);
    final source = controller.sourceLabel(target);
    final action = controller.actionLabel(target);
    final failure = controller.failure(target);
    final ember = context.ember;
    return Container(
      key: Key('progress-row-$id'),
      padding: const EdgeInsets.symmetric(vertical: EmberSpace.md),
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: ember.hairline)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: EmberType.body.copyWith(color: ember.ink)),
          if (source != null) ...[
            const SizedBox(height: EmberSpace.xs),
            Text(
              source,
              style: EmberType.label.copyWith(color: ember.inkTertiary),
            ),
          ],
          Wrap(
            spacing: EmberSpace.sm,
            runSpacing: EmberSpace.sm,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              ...controls,
              OutlinedButton(
                onPressed: enabled && controller.canClear(target)
                    ? () => unawaited(controller.clear(target))
                    : null,
                child: const Text('Clear'),
              ),
              if (action != null)
                OutlinedButton(
                  onPressed: enabled
                      ? () => unawaited(controller.undoOrRedo(target))
                      : null,
                  child: Text(action),
                ),
            ],
          ),
          if (failure != null) ...[
            const SizedBox(height: EmberSpace.sm),
            Text(failure, style: EmberType.label.copyWith(color: ember.errInk)),
          ],
        ],
      ),
    );
  }
}
